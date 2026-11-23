// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       tb_programs.v
// Description: Runs any assembled program on the 5-STAGE PIPELINE and reports
//              PASS / FAIL plus cycle, stall and flush counts.
//
// How a program reports its result (self-checking):
//   The program stores a value to TOHOST (data-RAM address 0xFFC, the last
//   word): 1 = PASS, anything else = failure code / failing test number.
//
// What is counted (so CPI can be computed as cycles / instructions):
//   cycles  = clock cycles from reset release until the TOHOST store has
//             passed through WB (the last instruction retires)
//   stalls  = cycles in which the PC was held (load-use hazard, 1 each)
//   flushes = taken branches / jumps (each wastes 2 fetched instructions)
//   Cycle model:  cycles = N + 4 + stalls + 2 * flushes
//   (N = instructions executed, taken from the single-cycle core; 4 = the
//   cycles needed to fill the pipeline). run_benchmarks.sh checks it.
//
// Parameters (set with  -P tb_programs.NAME=value):
//   PROG   hex file to load        MAX   timeout in cycles
// Optional waveform:  vvp sim.vvp +vcd=simulation/waveform_x.vcd
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines_n.vh"

module tb_programs;
    parameter PROG = "testbench/programs/isa_test.hex";
    parameter MAX  = 500000;
    localparam [31:0] TOHOST = 32'h00000FFC;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    riscv_core #(
        .IMEM_DEPTH(4096),
        .DMEM_DEPTH(1024),
        .INIT_FILE(PROG)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .current_pc(), .current_instr(), .wb_data_out(), .wb_rd_out(), .wb_reg_write_out()
    );

    // The TOHOST store is visible in the MEM stage (bubbles never write memory).
    wire tohost_write = dut.mem_write_mem && (dut.alu_result_mem == TOHOST);

    integer cycles = 0, stalls = 0, flushes = 0;
    reg [31:0] result;

    // Counters: sampled at every clock edge after reset is released.
    always @(posedge clk) if (rst_n) begin
        cycles = cycles + 1;
        if (!dut.pc_write)    stalls  = stalls  + 1;
        if (dut.if_id_flush)  flushes = flushes + 1;
    end

    reg [8*200-1:0] vcd_file;
    initial begin
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_programs);
        end
    end

    initial begin
        #22 rst_n = 1'b1;
        // Look 1 ns after each clock edge: at the edge itself the flip-flops
        // have not updated yet, so we would see the previous cycle's values.
        @(posedge clk); #1;
        while (!tohost_write) begin @(posedge clk); #1; end
        result = dut.write_data_mem;
        // The store is in MEM now; it reaches WB (retires) two edges later.
        $display("RESULT %0s | %0s | pipeline | cycles=%0d stalls=%0d flushes=%0d",
                 (result == 1) ? "PASS" : "FAIL", PROG, cycles + 2, stalls, flushes);
        if (result != 1) $display("[FAIL] program reported failure code / test number %0d", result);
        $finish;
    end

    initial begin
        #(MAX * 10);
        $display("[FAIL] TIMEOUT after %0d cycles: %0s (PC = %h)", MAX, PROG, dut.pc_reg);
        $finish;
    end
endmodule
