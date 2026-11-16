`timescale 1ns / 1ps
module gpio_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] gpio_out
);
    // MMIO Address 0x80000000
    wire gpio_sel = (addr == 32'h80000000);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gpio_out <= 32'd0;
        else if (mem_write && gpio_sel)
            gpio_out <= write_data;
    end
endmodule
