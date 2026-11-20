// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       pipe_ex_mem.v
// Description: EX/MEM Pipeline Register. Latches memory stage control signals,
//              computed ALU result, forwarded store data, PC+4, and destination register.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
//              Aditya Raj   (2401010032) - Pipeline Design
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module pipe_ex_mem (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      flush,          // Phase II: trap in EX -> insert bubble

    // Control Signals Input
    input  wire                      reg_write_in,
    input  wire [1:0]                mem_to_reg_in,
    input  wire                      mem_read_in,
    input  wire                      mem_write_in,
    input  wire                      valid_in,
    input  wire [2:0]                funct3_in,      // Phase II: LB/LH/LW/SB/SH... in MEM

    // Datapath Values Input
    input  wire [`XLEN-1:0]          pc_plus4_in,
    input  wire [`XLEN-1:0]          alu_result_in,
    input  wire [`XLEN-1:0]          write_data_in,
    input  wire [`REG_ADDR_WIDTH-1:0] rd_in,

    // Control Signals Output
    output reg                       reg_write_out,
    output reg  [1:0]                mem_to_reg_out,
    output reg                       mem_read_out,
    output reg                       mem_write_out,
    output reg                       valid_out,
    output reg  [2:0]                funct3_out,

    // Datapath Values Output
    output reg  [`XLEN-1:0]          pc_plus4_out,
    output reg  [`XLEN-1:0]          alu_result_out,
    output reg  [`XLEN-1:0]          write_data_out,
    output reg  [`REG_ADDR_WIDTH-1:0] rd_out
);

    // Reset (asynchronous) and flush (synchronous) are separate branches:
    // an async-reset branch may only test the reset signal, or synthesis fails.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 2'b00;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            valid_out      <= 1'b0;
            funct3_out     <= 3'b000;

            pc_plus4_out   <= {`XLEN{1'b0}};
            alu_result_out <= {`XLEN{1'b0}};
            write_data_out <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
        end else if (flush) begin
            // A bubble only needs its "do something" bits cleared: it must not
            // write a register, touch memory, or count as a retired instruction.
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 2'b00;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            valid_out      <= 1'b0;
            funct3_out     <= 3'b000;

            pc_plus4_out   <= {`XLEN{1'b0}};
            alu_result_out <= {`XLEN{1'b0}};
            write_data_out <= {`XLEN{1'b0}};
            rd_out         <= 5'd0;
        end else begin
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            valid_out      <= valid_in;
            funct3_out     <= funct3_in;

            pc_plus4_out   <= pc_plus4_in;
            alu_result_out <= alu_result_in;
            write_data_out <= write_data_in;
            rd_out         <= rd_in;
        end
    end

endmodule
