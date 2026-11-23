// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       fpga/fpga_top.v
// Description: Board-level top for an FPGA (written for a Basys-3-style board:
//              one clock, a reset button, 16 LEDs).
//                LEDs <- low 16 bits of the value written back by the CPU
//              The CPU runs fpga/fpga_demo.s in a loop, so the LEDs keep changing.
//              USE_PIPELINE = 1 builds the 5-stage pipeline, 0 the single-cycle
//              baseline, so both can be measured with exactly the same flow.
//              Used by scripts/run_fmax.sh to get a real post-place-and-route Fmax.
//
// Why an output at all: if nothing observable depended on the CPU, synthesis
// would (correctly) delete all of it. The LEDs depend on every instruction that
// writes a register, so the whole datapath has to be built.
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module fpga_top #(
    parameter PROG         = "fpga/fpga_demo.hex",
    parameter IMEM_DEPTH   = 128,
    parameter DMEM_DEPTH   = 256,
    parameter USE_PIPELINE = 1
)(
    input  wire        clk,
    input  wire        btn_rst,     // push button, active high
    output wire [15:0] led
);
    // Reset synchroniser: the button is not synchronous to clk, so pass it
    // through two flip-flops before it releases the CPU's reset.
    reg [1:0] rst_sync = 2'b00;
    always @(posedge clk) rst_sync <= {rst_sync[0], ~btn_rst};
    wire rst_n = rst_sync[1];

    wire [`XLEN-1:0] wb_data;

    generate
        if (USE_PIPELINE) begin : g_pipeline
            riscv_core #(
                .IMEM_DEPTH(IMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .INIT_FILE(PROG)
            ) u_core (
                .clk(clk), .rst_n(rst_n),
                .current_pc(), .current_instr(), .wb_data_out(wb_data),
                .wb_rd_out(), .wb_reg_write_out()
            );
        end else begin : g_single_cycle
            single_cycle_core #(
                .IMEM_DEPTH(IMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .INIT_FILE(PROG)
            ) u_core (
                .clk(clk), .rst_n(rst_n), .current_pc(), .wb_data_out(wb_data)
            );
        end
    endgenerate

    // The LED outputs come straight from flip-flops, like real board outputs.
    reg [15:0] led_r = 16'd0;
    always @(posedge clk) led_r <= wb_data[15:0];
    assign led = led_r;
endmodule
