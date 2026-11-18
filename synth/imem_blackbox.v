// Synthesis-only stand-in for instruction_memory: a black box, so the fetched
// instruction is a free input and the datapath is not constant-folded away.
(* blackbox *)
module instruction_memory #(
    parameter MEM_DEPTH = 1024,
    parameter INIT_FILE = ""
)(
    input  wire [31:0] address,
    output wire [31:0] instruction
);
endmodule
