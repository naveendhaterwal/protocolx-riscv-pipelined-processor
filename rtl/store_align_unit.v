// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       store_align_unit.v
// Description: Store side of byte/half-word memory access (Phase II).
//              Memory is organised as 32-bit words. To store one byte (SB) or
//              half-word (SH) we must (1) move the data into the right byte lane
//              and (2) tell memory which of the 4 bytes to change (byte_en).
//              The load side is mem_align_unit.v (by Shagun).
//
//   Example: SB with address ...01 (byte_offset = 1), data 0x000000AB
//            -> write_data = 0xABABABAB, byte_en = 4'b0010 (only byte 1 changes)
//
// Misaligned accesses (e.g. SW to address ...01) are not supported: the address
// is simply rounded down to the word. Our programs only use aligned accesses.
// =============================================================================

`timescale 1ns / 1ps

module store_align_unit (
    input  wire [2:0]  funct3,       // SB (000), SH (001), SW (010)
    input  wire [1:0]  byte_offset,  // address[1:0]
    input  wire [31:0] store_data,   // rs2 value
    output reg  [31:0] write_data,   // data placed in the right byte lane(s)
    output reg  [3:0]  byte_en       // which bytes of the word to write
);
    always @(*) begin
        case (funct3)
            3'b000: begin  // SB: copy the byte to all 4 lanes, enable only one
                write_data = {4{store_data[7:0]}};
                byte_en    = 4'b0001 << byte_offset;
            end
            3'b001: begin  // SH: copy the half-word to both halves, enable one half
                write_data = {2{store_data[15:0]}};
                byte_en    = byte_offset[1] ? 4'b1100 : 4'b0011;
            end
            default: begin // SW
                write_data = store_data;
                byte_en    = 4'b1111;
            end
        endcase
    end
endmodule
