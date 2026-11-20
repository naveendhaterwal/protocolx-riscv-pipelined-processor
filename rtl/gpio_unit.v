`timescale 1ns / 1ps
// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       gpio_unit.v
// Description: Memory-mapped GPIO (General Purpose Input/Output).
//              The CPU talks to it with ordinary SW / LW instructions:
//                0x80000000  GPIO_OUT  write: set output pins (e.g. LEDs), read: last value written
//                0x80000004  GPIO_IN   read : current input pins (e.g. switches)
//              Phase II adds the read port and the input register.
// Developer:  Ritik Ranjan (GPIO write path), Phase II read path added by the team.
// =============================================================================
module gpio_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire [31:0] gpio_in,        // from the outside world (switches)
    output reg  [31:0] gpio_out,       // to the outside world (LEDs)
    output reg  [31:0] read_data       // value returned to a load instruction
);
    // MMIO Address 0x80000000
    wire gpio_sel = (addr == 32'h80000000);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gpio_out <= 32'd0;
        else if (mem_write && gpio_sel)
            gpio_out <= write_data;
    end

    always @(*) begin
        case (addr)
            32'h80000000: read_data = gpio_out;
            32'h80000004: read_data = gpio_in;
            default:      read_data = 32'd0;
        endcase
    end
endmodule
