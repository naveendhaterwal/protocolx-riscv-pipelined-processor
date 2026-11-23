// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       data_memory_ar.v
// Description: Synchronous Data Memory (RAM) for Load and Store instructions.
//              Synchronous write on posedge clk, asynchronous read access.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines_n.vh"

module data_memory #(
    parameter MEM_DEPTH = 1024
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              mem_read,
    input  wire              mem_write,
    input  wire [`XLEN-1:0]  address,
    input  wire [`XLEN-1:0]  write_data,
    output wire [`XLEN-1:0]  read_data
);

    reg [`XLEN-1:0] memory [0:MEM_DEPTH-1];
    integer i;

    // Word-aligned addressing
    wire [$clog2(MEM_DEPTH)-1:0] word_addr = address[$clog2(MEM_DEPTH)+1:2];

    // The RAM starts as all zeros (simulation). There is deliberately NO reset
    // loop: clearing every word in one cycle forces FPGA tools to build the RAM
    // out of thousands of flip-flops instead of real RAM resources. (rst_n is
    // kept as a port so the module interface does not change.)
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = {`XLEN{1'b0}};
    end

    always @(posedge clk) begin
        if (mem_write && (address < (MEM_DEPTH * 4))) begin
            memory[word_addr] <= write_data;
        end
    end

    assign read_data = (mem_read && (address < (MEM_DEPTH * 4))) ? memory[word_addr] : {`XLEN{1'b0}};

endmodule
