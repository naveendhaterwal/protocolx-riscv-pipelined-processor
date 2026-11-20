// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       data_memory.v
// Description: Data RAM, 32-bit words, with per-byte write enables (Phase II)
//              so SB / SH / SW all work. Reads always return the whole word;
//              mem_align_unit.v picks out the byte / half-word for LB/LH/...
//
// Phase II changes and why:
//  * byte_en[3:0] replaces the single write enable (needed for SB / SH).
//  * The reset loop that cleared every word was removed. Clearing 1024 words in
//    one cycle forces synthesis to build the RAM from thousands of flip-flops;
//    without it the tools can use real RAM blocks. Contents start at 0 in
//    simulation (initial block); real programs initialise their own data.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module data_memory #(
    parameter MEM_DEPTH = 1024                  // number of 32-bit words (4 KB)
)(
    input  wire              clk,
    input  wire [3:0]        byte_en,           // byte lanes to write this cycle
    input  wire [`XLEN-1:0]  address,
    input  wire [`XLEN-1:0]  write_data,
    output wire [`XLEN-1:0]  read_data
);
    reg [`XLEN-1:0] memory [0:MEM_DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = {`XLEN{1'b0}};
    end

    // Word index = address / 4 (wraps around if the address is out of range)
    wire [$clog2(MEM_DEPTH)-1:0] word_addr = address[$clog2(MEM_DEPTH)+1:2];

    always @(posedge clk) begin
        if (byte_en[0]) memory[word_addr][7:0]   <= write_data[7:0];
        if (byte_en[1]) memory[word_addr][15:8]  <= write_data[15:8];
        if (byte_en[2]) memory[word_addr][23:16] <= write_data[23:16];
        if (byte_en[3]) memory[word_addr][31:24] <= write_data[31:24];
    end

    assign read_data = memory[word_addr];

endmodule
