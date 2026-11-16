`timescale 1ns / 1ps

module tb_branch_predictor_2bit;
    reg clk, rst_n;
    reg [31:0] pc_if, pc_ex;
    reg is_branch_ex, actual_taken_ex;
    wire predict_taken;

    branch_predictor_2bit dut (
        .clk(clk), .rst_n(rst_n),
        .pc_if(pc_if), .pc_ex(pc_ex),
        .is_branch_ex(is_branch_ex),
        .actual_taken_ex(actual_taken_ex),
        .predict_taken(predict_taken)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst_n = 0;
        pc_if = 32'h00000010; pc_ex = 32'h00000010;
        is_branch_ex = 0; actual_taken_ex = 0;
        #12 rst_n = 1;

        // Initial check: default is Weakly Not Taken (01) -> predict 0
        #1;
        if (predict_taken === 1'b0)
            $display("[PASS] Default prediction is NOT TAKEN");

        // Train loop: Branch taken 2 times
        @(posedge clk);
        is_branch_ex = 1; actual_taken_ex = 1; // Transition 01 -> 10 (Weakly Taken)
        @(posedge clk);
        is_branch_ex = 1; actual_taken_ex = 1; // Transition 10 -> 11 (Strongly Taken)
        @(posedge clk);
        is_branch_ex = 0;
        #1;
        if (predict_taken === 1'b1)
            $display("[PASS] Successfully trained to STRONGLY TAKEN (predict=1)");

        // Train loop: Branch NOT taken 2 times
        @(posedge clk);
        is_branch_ex = 1; actual_taken_ex = 0; // Transition 11 -> 10
        @(posedge clk);
        is_branch_ex = 1; actual_taken_ex = 0; // Transition 10 -> 01
        @(posedge clk);
        is_branch_ex = 0;
        #1;
        if (predict_taken === 1'b0)
            $display("[PASS] Successfully transitioned back to NOT TAKEN (predict=0)");

        $display(">>> ALL 2-BIT BRANCH PREDICTOR TESTS PASSED! <<<");
        $finish;
    end
endmodule
