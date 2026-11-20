// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       execution_unit.v
// Description: EX stage datapath: forwarding multiplexers, ALU, multiply/divide
//              unit (Phase II), branch condition check and target address.
// Developers:  Aditya Raj   (2401010032) - Forwarding and branch logic
//              Naveen Kumar (2401020041) - Integration
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module execution_unit (
    input  wire [`XLEN-1:0]  pc,
    input  wire [`XLEN-1:0]  read_data1,
    input  wire [`XLEN-1:0]  read_data2,
    input  wire [`XLEN-1:0]  immediate,
    input  wire [2:0]        funct3,
    input  wire [3:0]        alu_op,
    input  wire              alu_src,
    input  wire              alu_src_a,
    input  wire              muldiv,           // Phase II: RV32M instruction
    input  wire              is_jalr,

    // Forwarding inputs
    input  wire [1:0]        forward_a,
    input  wire [1:0]        forward_b,
    input  wire [`XLEN-1:0]  forward_data_mem, // From EX/MEM stage
    input  wire [`XLEN-1:0]  forward_data_wb,  // From MEM/WB stage

    // Outputs
    output wire [`XLEN-1:0]  result,           // ALU or multiply/divide result
    output wire [`XLEN-1:0]  operand_a,        // forwarded rs1 (used by CSR instructions)
    output wire [`XLEN-1:0]  write_data_mem,   // forwarded rs2 = store data
    output reg               branch_cond,      // 1 if the branch condition is true
    output wire [`XLEN-1:0]  target_pc         // branch / jump target address
);

    // Forwarding Multiplexers: take the newest value of rs1 / rs2
    wire [`XLEN-1:0] fwd_operand_a = (forward_a == `FWD_MEM_STAGE) ? forward_data_mem :
                                     (forward_a == `FWD_WB_STAGE)  ? forward_data_wb  :
                                     read_data1;

    wire [`XLEN-1:0] fwd_operand_b = (forward_b == `FWD_MEM_STAGE) ? forward_data_mem :
                                     (forward_b == `FWD_WB_STAGE)  ? forward_data_wb  :
                                     read_data2;

    assign operand_a      = fwd_operand_a;
    assign write_data_mem = fwd_operand_b;

    // ALU input multiplexers
    wire [`XLEN-1:0] alu_input_a = alu_src_a ? pc : fwd_operand_a;
    wire [`XLEN-1:0] alu_input_b = alu_src ? immediate : fwd_operand_b;

    wire [`XLEN-1:0] alu_result;
    alu u_alu (
        .alu_op(alu_op),
        .a(alu_input_a),
        .b(alu_input_b),
        .result(alu_result),
        .zero(),
        .less_than(),
        .less_than_unsigned()
    );

    // Phase II: RV32M multiply / divide (always uses the two registers)
    wire [`XLEN-1:0] muldiv_result;
    muldiv_unit u_muldiv (
        .funct3(funct3),
        .a(fwd_operand_a),
        .b(fwd_operand_b),
        .result(muldiv_result)
    );

    assign result = muldiv ? muldiv_result : alu_result;

    // Branch Condition Evaluation
    always @(*) begin
        case (funct3)
            `FUNCT3_BEQ:  branch_cond = (fwd_operand_a == fwd_operand_b);
            `FUNCT3_BNE:  branch_cond = (fwd_operand_a != fwd_operand_b);
            `FUNCT3_BLT:  branch_cond = ($signed(fwd_operand_a) < $signed(fwd_operand_b));
            `FUNCT3_BGE:  branch_cond = ($signed(fwd_operand_a) >= $signed(fwd_operand_b));
            `FUNCT3_BLTU: branch_cond = (fwd_operand_a < fwd_operand_b);
            `FUNCT3_BGEU: branch_cond = (fwd_operand_a >= fwd_operand_b);
            default:      branch_cond = 1'b0;
        endcase
    end

    // Target PC calculation (JALR: rs1 + imm with bit 0 cleared; others: PC + imm)
    wire [`XLEN-1:0] base_address = is_jalr ? fwd_operand_a : pc;
    wire [`XLEN-1:0] raw_target   = base_address + immediate;
    assign target_pc = is_jalr ? (raw_target & ~32'd1) : raw_target;

endmodule
