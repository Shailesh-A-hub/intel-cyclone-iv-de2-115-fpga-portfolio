//=============================================================================
// Testbench: tb_clock_divider
// Description: Self-checking testbench for clock_divider.
//=============================================================================

`timescale 1ns / 1ps

module tb_clock_divider;

    reg clk;
    reg rst;
    wire clk_out;
    wire tick_out;

    localparam integer DIVISOR = 4;

    clock_divider #(
        .DIVISOR(DIVISOR)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clk_out(clk_out),
        .tick_out(tick_out)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer tick_count = 0;

    initial begin
        clk = 0;
        rst = 1;
        #40;
        @(posedge clk);
        rst = 0;

        // Synchronize: wait until a tick occurs and completes
        wait (tick_out == 1'b1);
        @(posedge clk);

        // In the next 40 consecutive clock cycles, exactly 10 ticks must occur
        repeat (40) begin
            @(posedge clk);
            if (tick_out) begin
                tick_count = tick_count + 1;
            end
        end

        if (tick_count !== 10) begin
            $display("ERROR: Expected 10 ticks in 40 cycles, observed %0d", tick_count);
            errors = errors + 1;
        end else begin
            $display("INFO: Verified exactly 10 division ticks in 40 clock cycles (period = 4)");
        end

        #20;
        if (errors == 0) begin
            $display("=== TB_CLOCK_DIVIDER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_CLOCK_DIVIDER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
