`timescale 1ns / 1ps
module mem_align_unit (
    input  wire [2:0]  funct3,       // LB (000), LH (001), LW (010), LBU (100), LHU (101)
    input  wire [1:0]  byte_offset,  // Address[1:0]
    input  wire [31:0] raw_data_in,  // 32-bit word read from RAM
    output reg  [31:0] aligned_data
);
    wire [7:0]  selected_byte = (byte_offset == 2'b00) ? raw_data_in[7:0]   :
                                (byte_offset == 2'b01) ? raw_data_in[15:8]  :
                                (byte_offset == 2'b10) ? raw_data_in[23:16] : raw_data_in[31:24];
    wire [15:0] selected_half = byte_offset[1] ? raw_data_in[31:16] : raw_data_in[15:0];

    always @(*) begin
        case (funct3)
            3'b000:  aligned_data = {{24{selected_byte[7]}}, selected_byte}; // LB (signed)
            3'b100:  aligned_data = {24'b0, selected_byte};                  // LBU (unsigned)
            3'b001:  aligned_data = {{16{selected_half[15]}}, selected_half}; // LH (signed)
            3'b101:  aligned_data = {16'b0, selected_half};                  // LHU (unsigned)
            3'b010:  aligned_data = raw_data_in;                             // LW (full word)
            default: aligned_data = raw_data_in;
        endcase
    end
endmodule
