// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       instruction_memory.v
// Description: Instruction Memory (ROM/RAM model) storing RV32I machine code.
//              Supports preloading via $readmemh hex files. Word-aligned addressing.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module instruction_memory #(
    parameter MEM_DEPTH = 1024,
    parameter INIT_FILE = ""
)(
    input  wire [`XLEN-1:0] address,
    output wire [`XLEN-1:0] instruction
);

    reg [`XLEN-1:0] memory [0:MEM_DEPTH-1];
    integer i;

    initial begin
        // Simulation only: unused words read as NOP. Synthesis tools turn this
        // loop into memory WRITE ports instead of initial contents, which made
        // Yosys discard the program and optimise the whole CPU away (found in
        // the FPGA flow). SYNTHESIS is defined automatically by Yosys.
`ifndef SYNTHESIS
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = `INSTR_NOP;
        end
`endif
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    // Word-aligned word address [11:2]
    wire [$clog2(MEM_DEPTH)-1:0] word_addr = address[$clog2(MEM_DEPTH)+1:2];

    assign instruction = (address < (MEM_DEPTH * 4)) ? memory[word_addr] : `INSTR_NOP;

endmodule
