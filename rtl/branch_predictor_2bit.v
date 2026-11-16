`timescale 1ns / 1ps

// =============================================================================
// Project:     ProtocolX RISC-V 5-Stage Pipelined Processor
// Module:      branch_predictor_2bit.v
// Description: 2-bit Saturating Counter Dynamic Branch History Table (BHT).
//              Predicts branch direction in IF stage:
//                2'b00: Strongly Not Taken (SNT)
//                2'b01: Weakly Not Taken (WNT)
//                2'b10: Weakly Taken (WT)
//                2'b11: Strongly Taken (ST)
// Developer:   Aditya Raj (2401010032) - Pipeline Design & Verification
// =============================================================================

module branch_predictor_2bit #(
    parameter TABLE_ENTRIES = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc_if,          // PC in IF stage (for lookup)
    input  wire [31:0] pc_ex,          // PC in EX stage (for update)
    input  wire        is_branch_ex,   // 1 if instruction in EX is branch
    input  wire        actual_taken_ex,// 1 if branch was actually taken
    output wire        predict_taken   // Predicted direction for IF stage
);
    // 4-bit index from PC word address [5:2]
    wire [3:0] read_idx  = pc_if[5:2];
    wire [3:0] write_idx = pc_ex[5:2];

    reg [1:0] bht [0:TABLE_ENTRIES-1];
    integer i;

    // Prediction in IF stage: predict taken if counter is 2'b10 or 2'b11
    assign predict_taken = bht[read_idx][1];

    // State transition update in EX stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TABLE_ENTRIES; i = i + 1)
                bht[i] <= 2'b01; // Default: Weakly Not Taken
        end else if (is_branch_ex) begin
            if (actual_taken_ex) begin
                if (bht[write_idx] != 2'b11)
                    bht[write_idx] <= bht[write_idx] + 2'b01; // Move towards Strongly Taken
            end else begin
                if (bht[write_idx] != 2'b00)
                    bht[write_idx] <= bht[write_idx] - 2'b01; // Move towards Strongly Not Taken
            end
        end
    end
endmodule
