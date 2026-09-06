//=============================================================================
// Testbench: tb_button_debounce
// Description: Self-checking testbench for button_debounce with glitch rejection.
//=============================================================================

`timescale 1ns / 1ps

module tb_button_debounce;

    reg clk;
    reg rst;
    reg btn_in;
    wire debounced_state;
    wire pressed_pulse;
    wire released_pulse;

    // Use smaller frequency parameter for fast simulation (50 kHz, 1 ms debounce = 50 cycles)
    button_debounce #(
        .CLK_FREQ_HZ(50_000),
        .DEBOUNCE_MS(1),
        .ACTIVE_LOW_IN(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .btn_in(btn_in),
        .debounced_state(debounced_state),
        .pressed_pulse(pressed_pulse),
        .released_pulse(released_pulse)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer press_count = 0;

    always @(posedge clk) begin
        if (pressed_pulse) press_count = press_count + 1;
    end

    initial begin
        clk = 0;
        rst = 1;
        btn_in = 1; // Unpressed (active low)
        #45;
        rst = 0;
        #50;

        // Test 1: Rapid glitches (should be rejected)
        btn_in = 0; #100; // 5 cycles
        btn_in = 1; #200; // 10 cycles
        btn_in = 0; #80;  // 4 cycles
        btn_in = 1; #100;

        #2000;
        if (debounced_state !== 1'b0 || press_count !== 0) begin
            $display("ERROR: Glitch was incorrectly accepted as valid button press!");
            errors = errors + 1;
        end

        // Test 2: Sustained button press (exceeding 50 clock cycles)
        btn_in = 0; // Pressed
        #1500; // 75 cycles

        if (debounced_state !== 1'b1) begin
            $display("ERROR: debounced_state did not assert after sustained press!");
            errors = errors + 1;
        end
        if (press_count !== 1) begin
            $display("ERROR: Expected exactly 1 pressed_pulse, got %0d", press_count);
            errors = errors + 1;
        end

        // Test 3: Sustained button release
        btn_in = 1; // Released
        #1500;
        if (debounced_state !== 1'b0) begin
            $display("ERROR: debounced_state did not clear after release!");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=== TB_BUTTON_DEBOUNCE: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_BUTTON_DEBOUNCE: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
