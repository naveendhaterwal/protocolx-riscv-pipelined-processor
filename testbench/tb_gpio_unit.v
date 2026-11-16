`timescale 1ns / 1ps
module tb_gpio_unit;
    reg clk, rst_n, mem_write;
    reg [31:0] addr, write_data;
    wire [31:0] gpio_out;
    gpio_unit dut (
        .clk(clk), .rst_n(rst_n), .mem_write(mem_write),
        .addr(addr), .write_data(write_data), .gpio_out(gpio_out)
    );
    always #5 clk = ~clk;
    initial begin
        clk = 0; rst_n = 0; mem_write = 0; addr = 0; write_data = 0;
        #12 rst_n = 1;
        @(posedge clk);
        addr = 32'h80000000; write_data = 32'hA5A5A5A5; mem_write = 1;
        @(posedge clk);
        mem_write = 0; #1;
        if (gpio_out === 32'hA5A5A5A5)
            $display("[PASS] Memory-Mapped GPIO write verified: 0x%08h", gpio_out);
        else
            $display("[FAIL] GPIO write mismatch");
        $finish;
    end
endmodule
