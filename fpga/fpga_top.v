// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       fpga/fpga_top.v
// Description: Board-level top for an FPGA (written for a Basys-3-style board:
//              one clock, a reset button, 16 switches, 16 LEDs).
//                switches -> GPIO_IN  (address 0x80000004)
//                LEDs     <- GPIO_OUT (address 0x80000000)
//              USE_PIPELINE = 1 builds the 5-stage pipeline, 0 the single-cycle
//              baseline, so both can be measured with the same flow.
//              Used by fpga/run_fmax.sh to get a real post-place-and-route Fmax.
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
    input  wire [15:0] sw,
    output wire [15:0] led
);
    // Reset synchroniser: the button is not synchronous to clk, so pass it
    // through two flip-flops before it releases the CPU's reset.
    reg [1:0] rst_sync = 2'b00;
    always @(posedge clk) rst_sync <= {rst_sync[0], ~btn_rst};
    wire rst_n = rst_sync[1];

    wire [31:0] gpio_out;

    generate
        if (USE_PIPELINE) begin : g_pipeline
            riscv_core #(
                .IMEM_DEPTH(IMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH),
                .INIT_FILE(PROG), .BRANCH_PREDICTION(1)
            ) u_core (
                .clk(clk), .rst_n(rst_n),
                .gpio_in({16'd0, sw}), .gpio_out(gpio_out), .ext_irq(1'b0),
                .current_pc(), .current_instr(), .wb_data_out(), .wb_rd_out(), .wb_reg_write_out()
            );
        end else begin : g_single_cycle
            single_cycle_core #(
                .IMEM_DEPTH(IMEM_DEPTH), .DMEM_DEPTH(DMEM_DEPTH), .INIT_FILE(PROG)
            ) u_core (
                .clk(clk), .rst_n(rst_n),
                .gpio_in({16'd0, sw}), .gpio_out(gpio_out),
                .current_pc(), .cycle_count()
            );
        end
    endgenerate

    assign led = gpio_out[15:0];
endmodule
