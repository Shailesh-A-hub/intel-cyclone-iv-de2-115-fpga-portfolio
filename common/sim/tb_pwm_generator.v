//=============================================================================
// Testbench: tb_pwm_generator
// Description: Self-checking testbench for pwm_generator.
//=============================================================================

`timescale 1ns / 1ps

module tb_pwm_generator;

    reg clk;
    reg rst;
    reg enable;
    reg [15:0] prescaler;
    reg [15:0] period;
    reg [15:0] duty_cycle;
    wire pwm_out;
    wire cycle_end;

    pwm_generator #(.RESOLUTION_BITS(16)) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .prescaler(prescaler),
        .period(period),
        .duty_cycle(duty_cycle),
        .pwm_out(pwm_out),
        .cycle_end(cycle_end)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer high_count = 0;
    integer i;

    initial begin
        clk = 0;
        rst = 1;
        enable = 0;
        prescaler = 0; // 1:1 prescaler
        period = 16'd100;
        duty_cycle = 16'd25; // 25% duty cycle
        #40;
        @(posedge clk);
        rst = 0;
        enable = 1;

        // Synchronize: wait until the start of a fresh PWM period
        wait (cycle_end == 1'b1);
        @(posedge clk);

        // Measure duty cycle over exactly 100 clock cycles
        high_count = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) high_count = high_count + 1;
        end

        // Verify duty cycle
        if (high_count !== 25) begin
            $display("ERROR: Expected 25 high cycles for 25%% duty, got %0d", high_count);
            errors = errors + 1;
        end else begin
            $display("INFO: Verified 25%% duty cycle: exactly 25/100 high clock cycles");
        end

        // Test 0% duty cycle
        duty_cycle = 16'd0;
        wait (cycle_end == 1'b1);
        @(posedge clk);

        high_count = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) high_count = high_count + 1;
        end
        if (high_count !== 0) begin
            $display("ERROR: 0%% duty cycle produced high cycles: %0d", high_count);
            errors = errors + 1;
        end else begin
            $display("INFO: Verified 0%% duty cycle: exactly 0 high clock cycles");
        end

        // Test 100% duty cycle
        duty_cycle = 16'd100;
        wait (cycle_end == 1'b1);
        @(posedge clk);

        high_count = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) high_count = high_count + 1;
        end
        if (high_count !== 100) begin
            $display("ERROR: 100%% duty cycle produced non-100 high cycles: %0d", high_count);
            errors = errors + 1;
        end else begin
            $display("INFO: Verified 100%% duty cycle: exactly 100/100 high clock cycles");
        end

        #40;
        if (errors == 0) begin
            $display("=== TB_PWM_GENERATOR: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_PWM_GENERATOR: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
