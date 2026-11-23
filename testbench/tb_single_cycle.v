// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       tb_single_cycle.v
// Description: Runs a program on the single-cycle BASELINE core and reports
//              PASS / FAIL and the number of instructions executed.
//              In a single-cycle core every instruction takes exactly one
//              cycle, so cycles = instructions (N) and CPI = 1.
//              Same self-checking protocol as tb_programs.v (TOHOST = 0xFFC).
//   -P tb_single_cycle.PROG="testbench/programs/bench_sum.hex"
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module tb_single_cycle;
    parameter PROG = "testbench/programs/bench_sum.hex";
    parameter MAX  = 500000;
    localparam [31:0] TOHOST = 32'h00000FFC;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    single_cycle_core #(.IMEM_DEPTH(4096), .DMEM_DEPTH(1024), .INIT_FILE(PROG)) dut (
        .clk(clk), .rst_n(rst_n), .current_pc(), .wb_data_out());

    wire tohost_write = dut.mem_write && (dut.result == TOHOST);

    integer done_instr = 0;    // instructions fully executed before the current cycle
    always @(posedge clk) if (rst_n) done_instr = done_instr + 1;

    initial begin
        #22 rst_n = 1'b1;
        @(posedge clk); #1;    // look 1 ns after each edge (see tb_programs.v)
        while (!tohost_write) begin @(posedge clk); #1; end
        // The TOHOST store is executing right now: it is instruction number done_instr + 1.
        $display("RESULT %0s | %0s | single-cycle | instructions=%0d",
                 (dut.store_val == 1) ? "PASS" : "FAIL", PROG, done_instr + 1);
        $finish;
    end

    initial begin
        #(MAX * 10);
        $display("[FAIL] TIMEOUT after %0d cycles: %0s", MAX, PROG);
        $finish;
    end
endmodule
