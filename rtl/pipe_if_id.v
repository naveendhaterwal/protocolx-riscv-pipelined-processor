// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       pipe_if_id.v
// Description: IF/ID Pipeline Register. Latches PC and fetched instruction.
//              Supports synchronous stall (hold) and flush (NOP insertion).
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
//              Aditya Raj   (2401010032) - Pipeline Design
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module pipe_if_id (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,      // if_id_write from Hazard Unit
    input  wire              flush,       // if_id_flush from Hazard Unit
    input  wire [`XLEN-1:0]  pc_in,
    input  wire [`XLEN-1:0]  pc_plus4_in,
    input  wire [`XLEN-1:0]  instruction_in,
    input  wire              pred_taken_in,   // Phase II: IF predicted this branch taken
    output reg  [`XLEN-1:0]  pc_out,
    output reg  [`XLEN-1:0]  pc_plus4_out,
    output reg  [`XLEN-1:0]  instruction_out,
    output reg               pred_taken_out,
    output reg               valid_out        // Phase II: 0 = bubble (flushed / reset)
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out          <= {`XLEN{1'b0}};
            pc_plus4_out    <= {`XLEN{1'b0}};
            instruction_out <= `INSTR_NOP;
            pred_taken_out  <= 1'b0;
            valid_out       <= 1'b0;
        end else if (flush) begin
            pc_out          <= {`XLEN{1'b0}};
            pc_plus4_out    <= {`XLEN{1'b0}};
            instruction_out <= `INSTR_NOP;
            pred_taken_out  <= 1'b0;
            valid_out       <= 1'b0;
        end else if (enable) begin
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            instruction_out <= instruction_in;
            pred_taken_out  <= pred_taken_in;
            valid_out       <= 1'b1;
        end
    end

endmodule
