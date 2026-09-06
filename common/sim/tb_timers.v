//=============================================================================
// Testbench: tb_timers
// Description: Self-checking testbench for timer_ms, periodic_timer, and timeout_timer.
//=============================================================================

`timescale 1ns / 1ps

module tb_timers;

    reg clk;
    reg rst;

    // Timer ms (100 clock cycles per ms for testbench speed)
    wire tick_1ms;
    timer_ms #(.CLK_FREQ_HZ(100_000)) u_ms (
        .clk(clk),
        .rst(rst),
        .tick_1ms(tick_1ms)
    );

    // Periodic timer (period = 5 ms ticks)
    wire tick_5ms;
    wire [15:0] periodic_count;
    periodic_timer #(.PERIOD(5), .WIDTH(16)) u_periodic (
        .clk(clk),
        .rst(rst),
        .enable(1'b1),
        .tick_in(tick_1ms),
        .tick_out(tick_5ms),
        .count_val(periodic_count)
    );

    // Timeout timer
    reg         t_start;
    reg         t_retrigger;
    reg         t_cancel;
    wire        t_active;
    wire        t_expired;
    wire [15:0] t_remaining;

    timeout_timer #(.WIDTH(16)) u_timeout (
        .clk(clk),
        .rst(rst),
        .start(t_start),
        .retrigger(t_retrigger),
        .cancel(t_cancel),
        .tick_enable(tick_1ms),
        .duration(16'd10),
        .active(t_active),
        .expired(t_expired),
        .remaining_time(t_remaining)
    );

    always #10 clk = ~clk;

    integer errors = 0;

    initial begin
        clk = 0;
        rst = 1;
        t_start = 0;
        t_retrigger = 0;
        t_cancel = 0;
        #40;
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Test 1: Start timeout timer (10 ticks)
        @(posedge clk);
        t_start = 1;
        @(posedge clk);
        t_start = 0;
        #1;

        if (t_active !== 1'b1) begin
            $display("ERROR: Timeout timer failed to activate on start!");
            errors = errors + 1;
        end

        // Wait until timeout expires (after 10 ms ticks)
        wait (t_expired == 1'b1);
        @(posedge clk);
        #1;
        if (t_active !== 1'b0) begin
            $display("ERROR: Timeout timer still active after expiration!");
            errors = errors + 1;
        end

        // Test 2: Retrigger before expiration
        @(posedge clk);
        t_start = 1;
        @(posedge clk);
        t_start = 0;
        #1;

        // Count 4 ticks of 1ms
        repeat (4) begin
            wait (tick_1ms == 1'b1);
            @(posedge clk);
        end
        #1;

        // Assert retrigger
        @(posedge clk);
        t_retrigger = 1;
        @(posedge clk);
        t_retrigger = 0;
        #1;

        if (t_remaining !== 16'd10) begin
            $display("ERROR: Timeout timer failed to reload duration on retrigger! Got %0d", t_remaining);
            errors = errors + 1;
        end else begin
            $display("INFO: Retrigger verified: remaining time reloaded to %0d", t_remaining);
        end

        // Test 3: Cancel while active
        @(posedge clk);
        t_cancel = 1;
        @(posedge clk);
        t_cancel = 0;
        #1;

        if (t_active !== 1'b0) begin
            $display("ERROR: Timeout timer failed to cancel! active=%b", t_active);
            errors = errors + 1;
        end else begin
            $display("INFO: Cancel verified: timer deactivated immediately");
        end

        #200;
        if (errors == 0) begin
            $display("=== TB_TIMERS: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_TIMERS: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
