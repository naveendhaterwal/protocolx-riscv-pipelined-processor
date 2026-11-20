// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       tb_single_cycle.v
// Description: Runs a benchmark on the single-cycle BASELINE core and reports
//              PASS / FAIL and the cycle count (= instruction count, CPI = 1).
//              Same TOHOST protocol as tb_programs.v.
//   -P tb_single_cycle.PROG="testbench/programs/bench_sum.hex"
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module tb_single_cycle;
    parameter PROG = "testbench/programs/bench_sum.hex";
    parameter MAX  = 200000;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    single_cycle_core #(.IMEM_DEPTH(4096), .DMEM_DEPTH(1024), .INIT_FILE(PROG)) dut (
        .clk(clk), .rst_n(rst_n), .gpio_in(32'hCAFE1234), .gpio_out(), .current_pc(), .cycle_count());

    wire tohost_write = dut.mem_write && (dut.result == `MMIO_TOHOST);

    initial begin
        #22 rst_n = 1'b1;
        // Look 1 ns after each clock edge: at the edge itself the flip-flops
        // have not updated yet, so we would see the previous cycle's values.
        @(posedge clk); #1;
        while (!tohost_write) begin @(posedge clk); #1; end
        // cycle_count = instructions already finished; the TOHOST store is
        // executing in this cycle, so it is number cycle_count + 1.
        $display("RESULT %0s | %0s | single-cycle | cycles=%0d instret=%0d CPI=1.000",
                 (dut.store_val == 1) ? "PASS" : "FAIL", PROG, dut.cycle_count + 1, dut.cycle_count + 1);
        $finish;
    end

    initial begin
        #(MAX * 10);
        $display("[FAIL] TIMEOUT after %0d cycles: %0s", MAX, PROG);
        $finish;
    end
endmodule
