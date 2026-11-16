`timescale 1ns / 1ps
module tb_perf_counter;
    reg clk, rst_n, inst_retired;
    wire [63:0] cycle_count, inst_count;
    perf_counter dut (
        .clk(clk), .rst_n(rst_n), .inst_retired(inst_retired),
        .cycle_count(cycle_count), .inst_count(inst_count)
    );
    always #5 clk = ~clk;
    initial begin
        clk = 0; rst_n = 0; inst_retired = 0;
        #12 rst_n = 1;
        repeat(5) @(posedge clk);
        inst_retired = 1;
        repeat(5) @(posedge clk);
        inst_retired = 0;
        repeat(2) @(posedge clk);
        #1;
        if (cycle_count >= 12 && inst_count == 5)
            $display("[PASS] Performance Counter: %0d cycles, %0d retired insts", cycle_count, inst_count);
        else
            $display("[FAIL] Counter mismatch");
        $finish;
    end
endmodule
