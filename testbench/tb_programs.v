// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       tb_programs.v
// Description: Runs any assembled program (Phase II) on the pipelined core and
//              reports PASS / FAIL plus hardware-measured cycles, instructions
//              and CPI (from perf_counter).
//
// Protocol with the program:
//   * The program stores its result to TOHOST (0x800000F0):
//       1 = PASS, anything else = number of the failing test.
//   * GPIO_IN is driven with 0xCAFE1234 so programs can test reading it.
//   * If the program writes 0xE1 to GPIO_OUT, this testbench raises the
//     external interrupt line (ext_irq) until GPIO_OUT changes again.
//
// Parameters (set from the command line with  -P tb_programs.NAME=value):
//   PROG   hex file to load               BP   1 = branch prediction on, 0 = off
//   MAX    timeout in cycles
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module tb_programs;
    parameter PROG = "testbench/programs/isa_test.hex";
    parameter BP   = 1;
    parameter MAX  = 200000;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    wire [31:0] gpio_out;
    wire        ext_irq = (gpio_out == 32'hE1);   // program asks for an external interrupt

    riscv_core #(
        .IMEM_DEPTH(4096),
        .DMEM_DEPTH(1024),
        .INIT_FILE(PROG),
        .BRANCH_PREDICTION(BP)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .gpio_in(32'hCAFE1234),
        .gpio_out(gpio_out),
        .ext_irq(ext_irq),
        .current_pc(), .current_instr(), .wb_data_out(), .wb_rd_out(), .wb_reg_write_out()
    );

    // A store to TOHOST is visible in the MEM stage
    wire tohost_write = dut.mem_write_mem && dut.valid_mem && (dut.alu_result_mem == `MMIO_TOHOST);

    reg [31:0] result;
    reg [63:0] cycles, instret;
    integer    mispredicts = 0, branches = 0, stalls = 0, traps = 0;
    integer    whole, frac;

    // Extra statistics, counted the same way the hardware sees them
    always @(posedge clk) if (rst_n) begin
        if (dut.valid_ex && dut.branch_ex) branches    = branches + 1;
        if (dut.valid_ex && dut.mispredict_ex) mispredicts = mispredicts + 1;
        if (!dut.pc_write)                stalls      = stalls + 1;
        if (dut.trap_ex)                  traps       = traps + 1;
    end

    initial begin
        #22 rst_n = 1'b1;
        // Look 1 ns after each clock edge: at the edge itself the flip-flops
        // have not updated yet, so we would see the previous cycle's values.
        @(posedge clk); #1;
        while (!tohost_write) begin @(posedge clk); #1; end
        result = dut.write_data_mem;
        // Two more edges: the TOHOST store reaches WB and is counted as retired.
        @(posedge clk); @(posedge clk); #1;   // (count read 1 ns after the edge)
        cycles  = dut.cycle_count;
        instret = dut.inst_count;
        whole   = cycles / instret;
        frac    = ((cycles * 1000) / instret) % 1000;
        $display("RESULT %0s | %0s | bp=%0d | cycles=%0d instret=%0d CPI=%0d.%03d | branches=%0d mispredicts=%0d stall_cycles=%0d traps=%0d",
                 (result == 1) ? "PASS" : "FAIL", PROG, BP, cycles, instret, whole, frac,
                 branches, mispredicts, stalls, traps);
        if (result != 1) $display("[FAIL] program reported failing test number %0d", result);
        $finish;
    end

    initial begin
        #(MAX * 10);
        $display("[FAIL] TIMEOUT after %0d cycles: %0s (PC = %h)", MAX, PROG, dut.pc_reg);
        $finish;
    end
endmodule
