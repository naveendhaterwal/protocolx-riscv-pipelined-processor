// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       single_cycle_core.v
// Description: BASELINE for comparison (Phase II): a single-cycle RV32IM core.
//              Every instruction does fetch, decode, execute, memory and
//              write-back in ONE (long) clock cycle, so CPI = 1 exactly.
//              It reuses the same modules as the pipeline (control unit, ALU,
//              multiply/divide, memories, GPIO, timer) but has no pipeline
//              registers, no hazards, no forwarding and no branch prediction.
//              Not included: CSRs / traps (not needed by the benchmarks).
//
// Why build it: the course asks us to compare against a baseline. The pipeline
// needs MORE cycles than instructions (CPI > 1 because of stalls and flushes)
// but each cycle is SHORTER. Only by comparing both numbers (cycles x clock
// period) can we say whether pipelining made programs faster.
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
    input  wire [`XLEN-1:0]  gpio_in,
    output wire [`XLEN-1:0]  gpio_out,
    output wire [`XLEN-1:0]  current_pc,
    output reg  [63:0]       cycle_count      // = instructions executed (CPI = 1)
);
    // ---------------------------------------------------------------- fetch
    reg  [`XLEN-1:0] pc;
    wire [`XLEN-1:0] instr;
    instruction_memory #(.MEM_DEPTH(IMEM_DEPTH), .INIT_FILE(INIT_FILE)) u_imem (
        .address(pc), .instruction(instr));

    // ---------------------------------------------------------------- decode
    wire       reg_write, mem_read, mem_write, alu_src, alu_src_a, branch, jump, is_jalr;
    wire       muldiv, is_csr, is_ecall, is_ebreak, is_mret, illegal;
    wire [1:0] mem_to_reg;
    wire [3:0] alu_op;
    control_unit u_control (
        .opcode(instr[6:0]), .funct3(instr[14:12]), .funct7(instr[31:25]), .funct12(instr[31:20]),
        .reg_write(reg_write), .mem_to_reg(mem_to_reg), .mem_read(mem_read), .mem_write(mem_write),
        .alu_src(alu_src), .alu_src_a(alu_src_a), .branch(branch), .jump(jump), .is_jalr(is_jalr),
        .alu_op(alu_op), .muldiv(muldiv), .is_csr(is_csr), .is_ecall(is_ecall),
        .is_ebreak(is_ebreak), .is_mret(is_mret), .illegal(illegal));

    wire [`XLEN-1:0] rs1_val, rs2_val, wb_data, imm;
    reg_file #(.BYPASS(0)) u_regs (
        .clk(clk), .rst_n(rst_n), .reg_write(reg_write),
        .read_addr1(instr[19:15]), .read_addr2(instr[24:20]), .write_addr(instr[11:7]),
        .write_data(wb_data), .read_data1(rs1_val), .read_data2(rs2_val));

    imm_gen u_imm (.instruction(instr), .immediate(imm));

    // ---------------------------------------------------------------- execute
    wire [`XLEN-1:0] result, store_val, target;
    wire             cond;
    execution_unit u_exec (
        .pc(pc), .read_data1(rs1_val), .read_data2(rs2_val), .immediate(imm),
        .funct3(instr[14:12]), .alu_op(alu_op), .alu_src(alu_src), .alu_src_a(alu_src_a),
        .muldiv(muldiv), .is_jalr(is_jalr),
        .forward_a(2'b00), .forward_b(2'b00), .forward_data_mem(32'd0), .forward_data_wb(32'd0),
        .result(result), .operand_a(), .write_data_mem(store_val), .branch_cond(cond), .target_pc(target));

    // ---------------------------------------------------------------- memory
    wire             is_io = result[31];
    wire [`XLEN-1:0] st_data, mem_word, load_val, gpio_rdata, timer_rdata;
    wire [3:0]       st_en;
    store_align_unit u_st (.funct3(instr[14:12]), .byte_offset(result[1:0]), .store_data(store_val),
                           .write_data(st_data), .byte_en(st_en));
    data_memory #(.MEM_DEPTH(DMEM_DEPTH)) u_dmem (
        .clk(clk), .byte_en((mem_write && !is_io) ? st_en : 4'b0000),
        .address(result), .write_data(st_data), .read_data(mem_word));
    mem_align_unit u_ld (.funct3(instr[14:12]), .byte_offset(result[1:0]), .raw_data_in(mem_word),
                         .aligned_data(load_val));
    gpio_unit u_gpio (.clk(clk), .rst_n(rst_n), .mem_write(mem_write), .addr(result),
                      .write_data(store_val), .gpio_in(gpio_in), .gpio_out(gpio_out), .read_data(gpio_rdata));
    timer_unit u_timer (.clk(clk), .rst_n(rst_n), .mem_write(mem_write), .addr(result),
                        .write_data(store_val), .read_data(timer_rdata), .timer_irq());

    // ---------------------------------------------------------------- write back
    wire [`XLEN-1:0] pc_plus4 = pc + 32'd4;
    assign wb_data = (mem_to_reg == 2'b01) ? (is_io ? (gpio_rdata | timer_rdata) : load_val) :
                     (mem_to_reg == 2'b10) ? pc_plus4 : result;

    // ---------------------------------------------------------------- next PC
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc          <= 32'd0;
            cycle_count <= 64'd0;
        end else begin
            pc          <= (jump || (branch && cond)) ? target : pc_plus4;
            cycle_count <= cycle_count + 64'd1;
        end
    end

    assign current_pc = pc;
endmodule
