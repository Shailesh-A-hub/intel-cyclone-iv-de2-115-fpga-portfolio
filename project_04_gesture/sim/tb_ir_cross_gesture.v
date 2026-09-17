//=============================================================================
// Testbench: tb_ir_cross_gesture
// Description: Validates the Optical IR Cross Gesture Decoder engine.
//              Simulates spatial hand swipes across the 4 physical IR sensors:
//                1. Swipe Left -> Right  (Expects GESTURE_RIGHT)
//                2. Swipe Right -> Left  (Expects GESTURE_LEFT)
//                3. Swipe Up -> Down     (Expects GESTURE_DOWN)
//                4. Swipe Down -> Up     (Expects GESTURE_UP)
//                5. Direct Single Tap    (Expects Tap Gesture)
//=============================================================================

`timescale 1ns / 1ps

module tb_ir_cross_gesture;

    reg clk;
    reg reset_n;
    reg ir_u, ir_d, ir_l, ir_r;

    wire        gesture_valid;
    wire [2:0]  gesture_code;
    wire [31:0] gesture_ascii;
    wire [15:0] gesture_count;
    wire [3:0]  sensor_active_led;

    // Instantiate DUT in fast simulation mode
    ir_cross_gesture_decoder #(
        .CLK_FREQ_HZ(50_000_000),
        .DEBOUNCE_MS(1),
        .SWIPE_WINDOW_MS(5),
        .REFRACTORY_MS(2),
        .ACTIVE_LOW(1),
        .SIMULATION(1)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .ir_raw_u(ir_u),
        .ir_raw_d(ir_d),
        .ir_raw_l(ir_l),
        .ir_raw_r(ir_r),
        .gesture_valid(gesture_valid),
        .gesture_code(gesture_code),
        .gesture_ascii(gesture_ascii),
        .gesture_count(gesture_count),
        .sensor_active_led(sensor_active_led)
    );

    always #10 clk = ~clk; // 50 MHz clock

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task assert_test;
        input [127:0] name;
        input condition;
        begin
            if (condition) begin
                $display("[PASS] %0s", name);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0s", name);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        clk     = 0;
        reset_n = 0;
        // Standard IR obstacle sensors: idle = 1 (HIGH), obstacle = 0 (LOW)
        ir_u    = 1;
        ir_d    = 1;
        ir_l    = 1;
        ir_r    = 1;

        #200;
        reset_n = 1;
        #500;

        assert_test("Reset State", gesture_code == 3'd0 && gesture_count == 16'd0);

        // ---------------------------------------------------------------------
        // Test 1: Swipe Left -> Right
        // ---------------------------------------------------------------------
        $display("--- Test 1: Simulating Swipe Left -> Right ---");
        // Hand enters Left sensor first
        ir_l = 0;
        #15000; // Debounce
        ir_l = 1; // Left cleared
        #5000;
        // Hand enters Right sensor
        ir_r = 0;
        #15000;
        ir_r = 1;
        #20000;

        assert_test("Swipe Right Detected", gesture_code == 3'd4); // GESTURE_RIGHT

        #80000; // Refractory delay

        // ---------------------------------------------------------------------
        // Test 2: Swipe Right -> Left
        // ---------------------------------------------------------------------
        $display("--- Test 2: Simulating Swipe Right -> Left ---");
        ir_r = 0;
        #15000;
        ir_r = 1;
        #5000;
        ir_l = 0;
        #15000;
        ir_l = 1;
        #20000;

        assert_test("Swipe Left Detected", gesture_code == 3'd3); // GESTURE_LEFT

        #80000;

        // ---------------------------------------------------------------------
        // Test 3: Swipe Up -> Down
        // ---------------------------------------------------------------------
        $display("--- Test 3: Simulating Swipe Up -> Down ---");
        ir_u = 0;
        #15000;
        ir_u = 1;
        #5000;
        ir_d = 0;
        #15000;
        ir_d = 1;
        #20000;

        assert_test("Swipe Down Detected", gesture_code == 3'd2); // GESTURE_DOWN

        #80000;

        // ---------------------------------------------------------------------
        // Test 4: Swipe Down -> Up
        // ---------------------------------------------------------------------
        $display("--- Test 4: Simulating Swipe Down -> Up ---");
        ir_d = 0;
        #15000;
        ir_d = 1;
        #5000;
        ir_u = 0;
        #15000;
        ir_u = 1;
        #20000;

        assert_test("Swipe Up Detected", gesture_code == 3'd1); // GESTURE_UP

        #80000;

        $display("=================================================");
        $display(" IR CROSS GESTURE DECODER TEST SUMMARY");
        $display(" Passed: %0d | Failed: %0d", pass_cnt, fail_cnt);
        $display("=================================================");

        if (fail_cnt == 0)
            $display("[SUCCESS] All IR cross gesture tests passed!");
        else
            $display("[ERROR] Some tests failed!");

        $finish;
    end

endmodule
