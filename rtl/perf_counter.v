`timescale 1ns / 1ps
module perf_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        inst_retired,  // 1 when an instruction reaches WB
    output reg  [63:0] cycle_count,
    output reg  [63:0] inst_count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 64'd0;
            inst_count  <= 64'd0;
        end else begin
            cycle_count <= cycle_count + 64'd1;
            if (inst_retired)
                inst_count <= inst_count + 64'd1;
        end
    end
endmodule
