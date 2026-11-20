// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       control_unit.v
// Description: Main Control and ALU Decoder. Looks at the instruction's opcode,
//              funct3 and funct7 and turns them into control signals that steer
//              the datapath in later stages.
//              Phase II adds: RV32M (muldiv), CSR instructions, ECALL / EBREAK /
//              MRET, and an "illegal" flag for instructions we do not support.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
//              Aditya Raj   (2401010032) - Pipeline Architecture
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module control_unit (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [11:0] funct12,     // instr[31:20]: tells ECALL / EBREAK / MRET apart
    output reg         reg_write,
    output reg  [1:0]  mem_to_reg,  // 2'b00: ALU result, 2'b01: Mem Data, 2'b10: PC+4
    output reg         mem_read,
    output reg         mem_write,
    output reg         alu_src,     // 0: Reg B, 1: Immediate
    output reg         alu_src_a,   // 0: Reg A, 1: PC (for AUIPC)
    output reg         branch,
    output reg         jump,
    output reg         is_jalr,
    output reg  [3:0]  alu_op,
    // ---- Phase II ----
    output reg         muldiv,      // 1: use the multiply/divide unit instead of the ALU
    output reg         is_csr,      // 1: CSRRW/CSRRS/CSRRC (and the immediate forms)
    output reg         is_ecall,
    output reg         is_ebreak,
    output reg         is_mret,
    output reg         illegal      // 1: we don't know this instruction -> trap
);

    always @(*) begin
        // Default control settings (NOP behavior)
        reg_write  = 1'b0;
        mem_to_reg = 2'b00;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_src    = 1'b0;
        alu_src_a  = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        is_jalr    = 1'b0;
        alu_op     = `ALU_ADD;
        muldiv     = 1'b0;
        is_csr     = 1'b0;
        is_ecall   = 1'b0;
        is_ebreak  = 1'b0;
        is_mret    = 1'b0;
        illegal    = 1'b0;

        case (opcode)
            `OPCODE_R_TYPE: begin
                reg_write  = 1'b1;
                if (funct7 == `FUNCT7_MULDIV) begin
                    muldiv = 1'b1;                  // MUL..REMU: funct3 picks which one
                end else begin
                    case (funct3)
                        `FUNCT3_ADD_SUB: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SUB : `ALU_ADD;
                        `FUNCT3_SLL:     alu_op = `ALU_SLL;
                        `FUNCT3_SLT:     alu_op = `ALU_SLT;
                        `FUNCT3_SLTU:    alu_op = `ALU_SLTU;
                        `FUNCT3_XOR:     alu_op = `ALU_XOR;
                        `FUNCT3_SRL_SRA: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SRA : `ALU_SRL;
                        `FUNCT3_OR:      alu_op = `ALU_OR;
                        `FUNCT3_AND:     alu_op = `ALU_AND;
                        default:         alu_op = `ALU_ADD;
                    endcase
                end
            end

            `OPCODE_I_TYPE: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                case (funct3)
                    `FUNCT3_ADD_SUB: alu_op = `ALU_ADD;
                    `FUNCT3_SLT:     alu_op = `ALU_SLT;
                    `FUNCT3_SLTU:    alu_op = `ALU_SLTU;
                    `FUNCT3_XOR:     alu_op = `ALU_XOR;
                    `FUNCT3_OR:      alu_op = `ALU_OR;
                    `FUNCT3_AND:     alu_op = `ALU_AND;
                    `FUNCT3_SLL:     alu_op = `ALU_SLL;
                    `FUNCT3_SRL_SRA: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SRA : `ALU_SRL;
                    default:         alu_op = `ALU_ADD;
                endcase
            end

            `OPCODE_LOAD: begin            // LB, LH, LW, LBU, LHU (funct3 says which)
                reg_write  = 1'b1;
                mem_to_reg = 2'b01; // Data from Memory
                mem_read   = 1'b1;
                alu_src    = 1'b1;
                alu_op     = `ALU_ADD; // Address calculation
            end

            `OPCODE_STORE: begin           // SB, SH, SW (funct3 says which)
                mem_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = `ALU_ADD; // Address calculation
            end

            `OPCODE_BRANCH: begin
                branch     = 1'b1;
                alu_op     = `ALU_SUB; // Subtraction for comparison
            end

            `OPCODE_LUI: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = `ALU_PASS_B;
            end

            `OPCODE_AUIPC: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_src_a  = 1'b1; // Add PC
                alu_op     = `ALU_ADD;
            end

            `OPCODE_JAL: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b10; // PC + 4 written to rd
                jump       = 1'b1;
            end

            `OPCODE_JALR: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b10; // PC + 4 written to rd
                jump       = 1'b1;
                is_jalr    = 1'b1;
                alu_src    = 1'b1;
            end

            `OPCODE_SYSTEM: begin
                if (funct3 != 3'b000) begin          // CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
                    is_csr    = 1'b1;
                    reg_write = 1'b1;                // rd gets the old CSR value
                end else if (funct12 == 12'h000) begin
                    is_ecall  = 1'b1;
                end else if (funct12 == 12'h001) begin
                    is_ebreak = 1'b1;
                end else if (funct12 == 12'h302) begin
                    is_mret   = 1'b1;
                end else begin
                    illegal   = 1'b1;                // e.g. WFI, SRET: not supported
                end
            end

            `OPCODE_FENCE: begin
                // FENCE: orders memory accesses. Our core does every access in
                // program order already, so FENCE can safely do nothing (NOP).
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end

endmodule
