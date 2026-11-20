// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       timer_unit.v
// Description: Machine timer (Phase II), the standard RISC-V way to get a
//              periodic interrupt.
//                mtime     counts up by 1 every clock cycle (64 bits).
//                mtimecmp  is set by software.
//                timer_irq = 1 while mtime >= mtimecmp.
//              Software handles the interrupt and writes a new, larger mtimecmp
//              to clear it. Both are memory-mapped (see riscv_defines.vh):
//                0x80000010 / 14  mtime    (low / high word)
//                0x80000018 / 1C  mtimecmp (low / high word)
// =============================================================================

`timescale 1ns / 1ps

module timer_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,
    output reg         timer_irq
);
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;   // "never" until software sets it
        end else begin
            // A software write to mtime wins over the normal +1 increment.
            if (mem_write && addr == 32'h80000010)      mtime[31:0]  <= write_data;
            else if (mem_write && addr == 32'h80000014) mtime[63:32] <= write_data;
            else                                        mtime        <= mtime + 64'd1;

            if (mem_write && addr == 32'h80000018) mtimecmp[31:0]  <= write_data;
            if (mem_write && addr == 32'h8000001C) mtimecmp[63:32] <= write_data;
        end
    end

    always @(*) begin
        case (addr)
            32'h80000010: read_data = mtime[31:0];
            32'h80000014: read_data = mtime[63:32];
            32'h80000018: read_data = mtimecmp[31:0];
            32'h8000001C: read_data = mtimecmp[63:32];
            default:      read_data = 32'd0;
        endcase
    end

    // The 64-bit compare is registered (timer_irq is 1 cycle late). Without this
    // flip-flop, "compare -> trap decision -> PC redirect" was the longest logic
    // path in the whole pipeline (found with Yosys "ltp", see docs/LEARNING_GUIDE.md).
    // One cycle of extra interrupt delay is invisible to software.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) timer_irq <= 1'b0;
        else        timer_irq <= (mtime >= mtimecmp);
    end
endmodule
