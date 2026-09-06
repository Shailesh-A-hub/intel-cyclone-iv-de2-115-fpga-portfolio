//=============================================================================
// Testbench: tb_reset_synchronizer
// Description: Self-checking testbench for reset_synchronizer.
//=============================================================================

`timescale 1ns / 1ps

module tb_reset_synchronizer;

    reg clk;
    reg async_rst_n;
    wire sync_rst;

    // Instantiate DUT (Active-low async input, active-high sync output)
    reset_synchronizer #(
        .STAGES(2),
        .ACTIVE_LOW_IN(1),
        .ACTIVE_LOW_OUT(0)
    ) dut (
        .clk(clk),
        .async_rst_in(async_rst_n),
        .sync_rst_out(sync_rst)
    );

    // 50 MHz clock generation (20 ns period)
    always #10 clk = ~clk;

    integer errors = 0;

    initial begin
        clk = 0;
        async_rst_n = 1; // Not reset
        #5;

        // Test 1: Immediate asynchronous assertion
        #25;
        async_rst_n = 0; // Assert reset asynchronously between clock edges
        #1;
        if (sync_rst !== 1'b1) begin
            $display("ERROR: sync_rst did not assert immediately asynchronously at %t", $realtime);
            errors = errors + 1;
        end

        // Hold reset for 3 clock cycles
        #60;
        if (sync_rst !== 1'b1) begin
            $display("ERROR: sync_rst did not stay asserted at %t", $realtime);
            errors = errors + 1;
        end

        // Test 2: Synchronous de-assertion
        @(posedge clk);
        #2;
        async_rst_n = 1; // Release reset asynchronously
        if (sync_rst !== 1'b1) begin
            $display("ERROR: sync_rst de-asserted too early at %t", $realtime);
            errors = errors + 1;
        end

        // Stage 1 clock edge
        @(posedge clk);
        #2;
        // Still asserted after 1 clock edge
        if (sync_rst !== 1'b1) begin
            $display("ERROR: sync_rst should still be asserted after 1 stage at %t", $realtime);
            errors = errors + 1;
        end

        // Stage 2 clock edge: now de-asserted synchronously
        @(posedge clk);
        #2;
        if (sync_rst !== 1'b0) begin
            $display("ERROR: sync_rst failed to de-assert synchronously after 2 stages at %t", $realtime);
            errors = errors + 1;
        end

        #40;
        if (errors == 0) begin
            $display("=== TB_RESET_SYNCHRONIZER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_RESET_SYNCHRONIZER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
