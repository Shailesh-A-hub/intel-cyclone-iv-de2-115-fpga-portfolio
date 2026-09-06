//=============================================================================
// Testbench: tb_edge_detector
// Description: Self-checking testbench for edge_detector.
//=============================================================================

`timescale 1ns / 1ps

module tb_edge_detector;

    reg clk;
    reg rst;
    reg [1:0] sig_in;
    wire [1:0] rise;
    wire [1:0] fall;
    wire [1:0] both;

    edge_detector #(.WIDTH(2)) dut (
        .clk(clk),
        .rst(rst),
        .signal_in(sig_in),
        .rising_edge(rise),
        .falling_edge(fall),
        .both_edges(both)
    );

    always #10 clk = ~clk;

    integer errors = 0;

    initial begin
        clk = 0;
        rst = 1;
        sig_in = 2'b00;
        #35;
        rst = 0;
        @(posedge clk);
        #1;

        // Transition 0 -> 1 on bit 0
        sig_in[0] = 1;
        @(posedge clk); // Registered edge pulse emerges here
        #1;
        if (rise !== 2'b01 || fall !== 2'b00 || both !== 2'b01) begin
            $display("ERROR: Rising edge mismatch on bit 0 at %t. Got rise=%b, fall=%b, both=%b", $realtime, rise, fall, both);
            errors = errors + 1;
        end

        // Next cycle: edge pulse must clear
        @(posedge clk);
        #1;
        if (rise !== 2'b00 || fall !== 2'b00 || both !== 2'b00) begin
            $display("ERROR: Edge pulse did not clear after 1 cycle at %t", $realtime);
            errors = errors + 1;
        end

        // Transition 1 -> 0 on bit 0 and 0 -> 1 on bit 1
        sig_in = 2'b10;
        @(posedge clk);
        #1;
        if (rise !== 2'b10 || fall !== 2'b01 || both !== 2'b11) begin
            $display("ERROR: Edge detector mismatch on concurrent transition at %t. Got rise=%b, fall=%b, both=%b", $realtime, rise, fall, both);
            errors = errors + 1;
        end

        #40;
        if (errors == 0) begin
            $display("=== TB_EDGE_DETECTOR: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_EDGE_DETECTOR: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
