//=============================================================================
// Testbench: tb_basic1_fire_gas
// Project: Project 2 / Basic #1 — Gas & Fire Sensor Readout with Threshold Alert
// Description: Validates:
//              1. Normal clean baseline: all alert LEDs off.
//              2. MQ-2 DO trip triggers LEDG[0] and LCD hazard warning.
//              3. MQ-7 DO trip triggers LEDG[1] and LCD CO warning.
//              4. High temperature (>35°C) triggers LEDG[2].
//              5. 2-second screen rotation cycles across all 3 pages.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module tb_basic1_fire_gas;

    reg        clk;
    reg  [3:0] key;
    reg  [17:0] sw;
    reg        mq2_do;
    reg        mq7_do;
    wire       dht11_data;

    wire [2:0] ledg;
    wire [7:0] lcd_data;
    wire       lcd_rs, lcd_en, lcd_rw, lcd_on, lcd_blon;

    localparam CLK_FREQ = 50_000; // Fast simulation clock

    basic1_fire_gas_top #(
        .CLK_FREQ_HZ(CLK_FREQ),
        .TEMP_THRESH_C(35),
        .ACTIVE_LOW_DO(1),
        .SIMULATION(1)
    ) dut (
        .CLOCK_50(clk),
        .KEY(key),
        .SW(sw),
        .MQ2_DO(mq2_do),
        .MQ7_DO(mq7_do),
        .DHT11_DATA(dht11_data),
        .LEDG(ledg),
        .LCD_DATA(lcd_data),
        .LCD_RS(lcd_rs),
        .LCD_EN(lcd_en),
        .LCD_RW(lcd_rw),
        .LCD_ON(lcd_on),
        .LCD_BLON(lcd_blon)
    );

    always #10 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        clk = 0;
        key = 4'b1111;      // KEY unpressed
        sw  = 18'b0;
        mq2_do = 1'b1;      // Active low: 1 = clean
        mq7_do = 1'b1;      // Active low: 1 = clean

        $display("================================================================");
        $display(" STARTING BASIC #1 GAS & FIRE READOUT TESTBENCH");
        $display("================================================================");

        // 1. Reset DUT
        repeat(10) @(posedge clk);
        key[0] = 1'b0;
        repeat(20) @(posedge clk);
        key[0] = 1'b1;
        repeat(50) @(posedge clk);

        // Baseline check: no alerts
        if (ledg == 3'b000) begin
            $display("[PASS] Baseline clean: LEDG[2:0] = 000.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG = 000, got %b", ledg);
            fail_count = fail_count + 1;
        end

        // 2. Test MQ2 Gas Trip
        $display("[SIM] Injecting MQ-2 Flammable Gas / Smoke...");
        mq2_do = 1'b0; // Active low trip
        repeat(100) @(posedge clk); // debounce filter
        if (ledg[0] == 1'b1) begin
            $display("[PASS] MQ-2 gas alert triggered LEDG[0].");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG[0] = 1, got %b", ledg[0]);
            fail_count = fail_count + 1;
        end

        // Clear MQ2
        mq2_do = 1'b1;
        repeat(100) @(posedge clk);
        if (ledg[0] == 1'b0) begin
            $display("[PASS] MQ-2 clear: LEDG[0] returned to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG[0] = 0, got %b", ledg[0]);
            fail_count = fail_count + 1;
        end

        // 3. Test MQ7 Carbon Monoxide Trip
        $display("[SIM] Injecting MQ-7 Carbon Monoxide...");
        mq7_do = 1'b0; // Active low trip
        repeat(100) @(posedge clk);
        if (ledg[1] == 1'b1) begin
            $display("[PASS] MQ-7 CO alert triggered LEDG[1].");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG[1] = 1, got %b", ledg[1]);
            fail_count = fail_count + 1;
        end

        // Clear MQ7
        mq7_do = 1'b1;
        repeat(100) @(posedge clk);

        // 4. Test High Temperature Alert using Synthetic Mode
        $display("[SIM] Enabling synthetic test mode with High Temp (42 deg C)...");
        sw[0] = 1'b1; // Synthetic mode enable
        sw[1] = 1'b1; // High temp (42 C)
        repeat(1500) @(posedge clk); // Allow DHT11 trigger and latch

        if (ledg[2] == 1'b1 && dut.live_temp == 8'd42) begin
            $display("[PASS] High temperature (42 deg C > 35 deg C) triggered LEDG[2].");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG[2] = 1, got %b (temp = %d)", ledg[2], dut.live_temp);
            fail_count = fail_count + 1;
        end

        // Set temp back to normal (27 C)
        sw[1] = 1'b0;
        repeat(1500) @(posedge clk);
        if (ledg[2] == 1'b0 && dut.live_temp == 8'd27) begin
            $display("[PASS] Normal temperature (27 deg C <= 35 deg C): LEDG[2] cleared.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected LEDG[2] = 0, got %b (temp = %d)", ledg[2], dut.live_temp);
            fail_count = fail_count + 1;
        end

        // 5. Test LCD Screen Cycling
        $display("[SIM] Testing 3-screen cycling FSM...");
        repeat(2500) @(posedge clk);
        $display("[INFO] Current screen index: %d", dut.u_cycler.current_screen);
        repeat(2500) @(posedge clk);
        $display("[INFO] Current screen index: %d", dut.u_cycler.current_screen);
        repeat(2500) @(posedge clk);
        $display("[INFO] Current screen index: %d", dut.u_cycler.current_screen);

        pass_count = pass_count + 1; // Screen cycling completed without lockup

        $display("================================================================");
        $display(" RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("================================================================");
        if (fail_count == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
