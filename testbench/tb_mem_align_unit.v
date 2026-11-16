`timescale 1ns / 1ps
module tb_mem_align_unit;
    reg [2:0] funct3;
    reg [1:0] byte_offset;
    reg [31:0] raw_data;
    wire [31:0] out;
    mem_align_unit dut (.funct3(funct3), .byte_offset(byte_offset), .raw_data_in(raw_data), .aligned_data(out));
    initial begin
        raw_data = 32'h80FFEEDD;
        // Test LB (signed byte 0x80 -> -128)
        funct3 = 3'b000; byte_offset = 2'b11; #1;
        if (out === 32'hFFFFFF80) $display("[PASS] LB signed extension verified");
        // Test LBU (unsigned byte 0x80 -> 128)
        funct3 = 3'b100; byte_offset = 2'b11; #1;
        if (out === 32'h00000080) $display("[PASS] LBU zero extension verified");
        // Test LW
        funct3 = 3'b010; byte_offset = 2'b00; #1;
        if (out === 32'h80FFEEDD) $display("[PASS] LW pass-through verified");
        $finish;
    end
endmodule
