// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       single_cycle_core.v
// Description: BASELINE for comparison: a single-cycle RV32I core.
//              Every instruction does fetch, decode, execute, memory and
//              write-back in ONE (long) clock cycle, so CPI = 1 exactly.
//              It reuses the same modules as the pipeline (control unit, ALU /
//              execution unit, register file, immediate generator, memories)
//              but has no pipeline registers, no hazards and no forwarding.
//
// Why build it: the course asks us to verify the single-cycle datapath first
// and compare against it. The pipeline needs MORE cycles than instructions
// (CPI > 1 because of stalls and flushes) but each cycle is SHORTER. Only by
// comparing both numbers (cycles x clock period) can we say whether
// pipelining made programs faster.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module single_cycle_core #(
    parameter IMEM_DEPTH = 1024,
    parameter DMEM_DEPTH = 1024,
    parameter INIT_FILE  = ""
)(
    input  wire              clk,
    input  wire              rst_n,
    output wire [`XLEN-1:0]  current_pc,
    output wire [`XLEN-1:0]  wb_data_out     // value being written back (probe / FPGA LEDs)
);
    // ---------------------------------------------------------------- fetch
    reg  [`XLEN-1:0] pc;
    wire [`XLEN-1:0] instr;
    instruction_memory #(.MEM_DEPTH(IMEM_DEPTH), .INIT_FILE(INIT_FILE)) u_imem (
        .address(pc), .instruction(instr));

    // ---------------------------------------------------------------- decode
    wire       reg_write, mem_read, mem_write, alu_src, alu_src_a, branch, jump, is_jalr;
    wire [1:0] mem_to_reg;
    wire [3:0] alu_op;
    control_unit u_control (
        .opcode(instr[6:0]), .funct3(instr[14:12]), .funct7(instr[31:25]),
        .reg_write(reg_write), .mem_to_reg(mem_to_reg), .mem_read(mem_read), .mem_write(mem_write),
        .alu_src(alu_src), .alu_src_a(alu_src_a), .branch(branch), .jump(jump), .is_jalr(is_jalr),
        .alu_op(alu_op));

    wire [`XLEN-1:0] rs1_val, rs2_val, wb_data, imm;
    // BYPASS = 0: in a single-cycle design the value being written depends on the
    // value being read in the same cycle, so a write-to-read bypass would form a
    // combinational loop. The new value is simply visible from the next cycle.
    reg_file #(.BYPASS(0)) u_regs (
        .clk(clk), .rst_n(rst_n), .reg_write(reg_write),
        .read_addr1(instr[19:15]), .read_addr2(instr[24:20]), .write_addr(instr[11:7]),
        .write_data(wb_data), .read_data1(rs1_val), .read_data2(rs2_val));

    imm_gen u_imm (.instruction(instr), .immediate(imm));

    // ---------------------------------------------------------------- execute
    wire [`XLEN-1:0] result, store_val, target;
    wire             taken;
    execution_unit u_exec (
        .pc(pc), .read_data1(rs1_val), .read_data2(rs2_val), .immediate(imm),
        .funct3(instr[14:12]), .alu_op(alu_op), .alu_src(alu_src), .alu_src_a(alu_src_a),
        .branch(branch), .jump(jump), .is_jalr(is_jalr),
        .forward_a(2'b00), .forward_b(2'b00), .forward_data_mem(32'd0), .forward_data_wb(32'd0),
        .alu_result(result), .write_data_mem(store_val), .branch_taken(taken), .target_pc(target));

    // ---------------------------------------------------------------- memory
    wire [`XLEN-1:0] load_val;
    data_memory #(.MEM_DEPTH(DMEM_DEPTH)) u_dmem (
        .clk(clk), .rst_n(rst_n), .mem_read(mem_read), .mem_write(mem_write),
        .address(result), .write_data(store_val), .read_data(load_val));

    // ---------------------------------------------------------------- write back
    wire [`XLEN-1:0] pc_plus4 = pc + 32'd4;
    assign wb_data = (mem_to_reg == 2'b01) ? load_val :
                     (mem_to_reg == 2'b10) ? pc_plus4 : result;
    assign wb_data_out = wb_data;

    // ---------------------------------------------------------------- next PC
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'd0;
        else        pc <= taken ? target : pc_plus4;
    end

    assign current_pc = pc;
endmodule
