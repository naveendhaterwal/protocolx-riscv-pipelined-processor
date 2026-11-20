// Synthesis-only stand-in used by fpga/run_fmax.sh for the "no M extension"
// timing runs: it removes the multiply/divide hardware so we can see how fast
// the rest of each core is. NOT functionally correct - never simulate with it.
`timescale 1ns / 1ps
module muldiv_unit (
    input  wire [2:0]  funct3,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] result
);
    assign result = 32'd0;
endmodule
