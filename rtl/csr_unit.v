// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       csr_unit.v
// Description: Control and Status Registers + traps (Phase II, machine mode only).
//
// What it does, in the EX stage:
//  1. CSR instructions (CSRRW/S/C and the "I" forms): read the old CSR value
//     (goes to rd) and write the new one.
//  2. Exceptions: ECALL, EBREAK or an illegal instruction in EX -> trap.
//  3. Interrupts: timer or external interrupt pending and enabled -> trap,
//     using the instruction currently in EX as the place to come back to.
//  4. MRET: return from the handler (PC <- mepc).
//
// A "trap" means: save the PC of the instruction in EX into mepc, save the
// reason in mcause, disable interrupts (MIE <- 0, old value kept in MPIE) and
// jump to the handler address in mtvec. The core flushes the younger
// instructions, so the trap is "precise": everything before mepc finished,
// nothing from mepc onward did.
//
// mcause values:  2 illegal instruction, 3 breakpoint (EBREAK), 11 ECALL,
//                 0x80000007 timer interrupt, 0x8000000B external interrupt.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module csr_unit (
    input  wire        clk,
    input  wire        rst_n,
    // instruction in the EX stage
    input  wire        valid,        // 1 = real instruction (not a bubble)
    input  wire [31:0] pc,
    input  wire        is_csr,
    input  wire [2:0]  funct3,       // which CSR operation
    input  wire [11:0] csr_addr,
    input  wire [31:0] rs1_value,    // forwarded rs1 (register forms)
    input  wire [4:0]  zimm,         // rs1 field as a 5-bit constant (immediate forms)
    input  wire        is_ecall,
    input  wire        is_ebreak,
    input  wire        is_mret,
    input  wire        illegal,
    // interrupt sources
    input  wire        timer_irq,
    input  wire        ext_irq,
    // performance counters (read-only CSRs)
    input  wire [63:0] cycle_count,
    input  wire [63:0] inst_count,
    // outputs
    output reg  [31:0] csr_rdata,    // old CSR value, written to rd
    output wire        trap,         // take a trap now (redirect to mtvec, flush)
    output wire        mret,         // return now (redirect to mepc, flush)
    output wire [31:0] trap_vector,  // = mtvec
    output wire [31:0] return_pc     // = mepc
);
    // ---------------------------------------------------------------- registers
    reg        mstatus_mie;   // global interrupt enable
    reg        mstatus_mpie;  // previous MIE (saved on trap)
    reg        mie_mtie;      // timer interrupt enable
    reg        mie_meie;      // external interrupt enable
    reg [31:0] mtvec, mscratch, mepc, mcause, mtval;

    wire [31:0] mstatus = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0}; // MPP = 11 (machine)
    wire [31:0] mie     = {20'd0, mie_meie, 3'd0, mie_mtie, 7'd0};
    wire [31:0] mip     = {20'd0, ext_irq,  3'd0, timer_irq, 7'd0};

    // ---------------------------------------------------------------- trap decision
    wire irq_ext   = mstatus_mie & mie_meie & ext_irq;
    wire irq_timer = mstatus_mie & mie_mtie & timer_irq;
    wire interrupt = valid & (irq_ext | irq_timer);
    wire exception = valid & (is_ecall | is_ebreak | illegal);
    assign trap        = interrupt | exception;
    assign mret        = valid & is_mret & ~trap;
    assign trap_vector = mtvec;
    assign return_pc   = mepc;

    wire [31:0] cause = irq_ext   ? 32'h8000000B :   // external has priority over timer
                        irq_timer ? 32'h80000007 :
                        illegal   ? 32'd2 :
                        is_ebreak ? 32'd3 :
                                    32'd11;          // ECALL from machine mode

    // ---------------------------------------------------------------- CSR read
    always @(*) begin
        case (csr_addr)
            `CSR_MSTATUS:  csr_rdata = mstatus;
            `CSR_MIE:      csr_rdata = mie;
            `CSR_MTVEC:    csr_rdata = mtvec;
            `CSR_MSCRATCH: csr_rdata = mscratch;
            `CSR_MEPC:     csr_rdata = mepc;
            `CSR_MCAUSE:   csr_rdata = mcause;
            `CSR_MTVAL:    csr_rdata = mtval;
            `CSR_MIP:      csr_rdata = mip;
            `CSR_MCYCLE,   `CSR_CYCLE:    csr_rdata = cycle_count[31:0];
            `CSR_MCYCLEH,  `CSR_CYCLEH:   csr_rdata = cycle_count[63:32];
            `CSR_MINSTRET, `CSR_INSTRET:  csr_rdata = inst_count[31:0];
            `CSR_MINSTRETH,`CSR_INSTRETH: csr_rdata = inst_count[63:32];
            default:       csr_rdata = 32'd0;
        endcase
    end

    // ---------------------------------------------------------------- CSR write value
    wire [31:0] src = funct3[2] ? {27'd0, zimm} : rs1_value;   // CSRRxI use the constant
    reg  [31:0] new_value;
    always @(*) begin
        case (funct3[1:0])
            2'b01:   new_value = src;               // CSRRW: write
            2'b10:   new_value = csr_rdata | src;   // CSRRS: set bits
            default: new_value = csr_rdata & ~src;  // CSRRC: clear bits
        endcase
    end
    wire csr_write = valid & is_csr & ~trap;

    // ---------------------------------------------------------------- state update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mie_mtie     <= 1'b0;
            mie_meie     <= 1'b0;
            mtvec        <= 32'd0;
            mscratch     <= 32'd0;
            mepc         <= 32'd0;
            mcause       <= 32'd0;
            mtval        <= 32'd0;
        end else if (trap) begin
            mepc         <= pc;
            mcause       <= cause;
            mtval        <= 32'd0;          // optional by the spec; we keep it simple
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;           // no nested interrupts inside the handler
        end else if (mret) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (csr_write) begin
            case (csr_addr)
                `CSR_MSTATUS:  begin mstatus_mie <= new_value[3]; mstatus_mpie <= new_value[7]; end
                `CSR_MIE:      begin mie_mtie <= new_value[7]; mie_meie <= new_value[11]; end
                `CSR_MTVEC:    mtvec    <= {new_value[31:2], 2'b00};   // direct mode only
                `CSR_MSCRATCH: mscratch <= new_value;
                `CSR_MEPC:     mepc     <= {new_value[31:2], 2'b00};
                `CSR_MCAUSE:   mcause   <= new_value;
                `CSR_MTVAL:    mtval    <= new_value;
                default: ;                                             // read-only: ignore
            endcase
        end
    end
endmodule
