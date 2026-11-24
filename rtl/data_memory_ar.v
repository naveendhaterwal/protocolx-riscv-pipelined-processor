// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       data_memory_ar.v
// Description: Data memory (RAM) used by the load (lw) and store (sw) instructions.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
// Responsible for this file (reviews, explains, answers for): Archit Mamodiya
//
// HOW IT WORKS (in 3 lines):
//   - The memory is a list of 32-bit "boxes" (words). Each box has a number.
//   - STORE (sw): on the clock edge, put write_data into the box.
//   - LOAD  (lw): read_data shows the box right away (no clock needed).
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines_n.vh"

module data_memory #(
    parameter MEM_DEPTH = 1024          // how many 32-bit boxes (max 1024 = 4 KB; FPGA uses 256)
)(
    input  wire              clk,
    input  wire              rst_n,      // not used (kept so the ports do not change)
    input  wire              mem_read,   // 1 = this instruction is a load
    input  wire              mem_write,  // 1 = this instruction is a store
    input  wire [31:0]       address,    // BYTE address, comes from the ALU
    input  wire [31:0]       write_data, // value to store
    output wire [31:0]       read_data   // value that was loaded
);

    // The memory itself: MEM_DEPTH boxes, each 32 bits wide.
    reg [31:0] memory [0:MEM_DEPTH-1];

    // A byte address counts bytes (0, 1, 2, 3, 4 ...). Our boxes are 4 bytes
    // wide, so the box number is the address divided by 4.
    // "address[11:2]" drops the lowest 2 bits (= divide by 4) and keeps 10 bits,
    // enough to pick one of up to 1024 boxes (2^10 = 1024).
    wire [9:0] box_number = address[11:2];

    // Safety check: is the address really inside our memory?
    wire address_is_valid = (address < (MEM_DEPTH * 4));

    // At the start of the simulation, fill every box with 0.
    // (We do NOT clear it on reset: that would make FPGA tools build the memory
    //  from thousands of flip-flops instead of real RAM.)
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = 0;
    end

    // STORE: happens on the rising clock edge.
    always @(posedge clk) begin
        if (mem_write && address_is_valid)
            memory[box_number] <= write_data;
    end

    // LOAD: no clock needed. If it is a valid load, show the box, else show 0.
    assign read_data = (mem_read && address_is_valid) ? memory[box_number] : 0;

endmodule
