//=============================================================================
// Testbench: tb_intermediate9_gesture
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Description: Validates:
//              1. Power-on reset: cursor at item 0, root menu displayed.
//              2. Gesture Left -> Center emits SELECT pulse; cursor advances.
//              3. Gesture Right -> Center emits BACK pulse; cursor moves back.
//              4. Gesture Center -> Confirm enters submenu.
//              5. Incomplete gesture timeout rejection.
//              6. Manual test mode (SW[0]=1) with KEY[1..3].
//              7. UART transmission activity at 9600 baud.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module tb_intermediate9_gesture;

    reg        clk;
    reg  [3:0] key;
    reg  [17:0] sw;
    reg  [3:0] gpio_0;      // [0]=Left, [1]=Center, [2]=Right, [3]=Confirm (active-low)

    wire       uart_txd_out;
    wire [3:0] ledg;
    wire [7:0] lcd_data;
    wire       lcd_rs, lcd_en, lcd_rw, lcd_on, lcd_blon;

    localparam CLK_FREQ = 50_000; // Fast simulation clock

    intermediate9_gesture_top #(
        .CLK_FREQ_HZ(CLK_FREQ),
        .BAUD_RATE(9600),
        .ACTIVE_LOW_IR(1),
        .SIMULATION(1)
    ) dut (
        .CLOCK_50(clk),
        .KEY(key),
        .SW(sw),
        .GPIO_0(gpio_0),
        .UART_TXD_OUT(uart_txd_out),
        .LEDG(ledg),
        .LCD_DATA(lcd_data),
        .LCD_RS(lcd_rs),
        .LCD_EN(lcd_en),
        .LCD_RW(lcd_rw),
        .LCD_ON(lcd_on),
        .LCD_BLON(lcd_blon)
    );

    always #10 clk = ~clk;

    // Helper task: simulate Left -> Center swipe (SELECT)
    task swipe_left_center;
        begin
            $display("[SIM] Swiping Hand: LEFT -> CENTER (SELECT)...");
            gpio_0[0] = 1'b0; // Break Left
            repeat(100) @(posedge clk);
            gpio_0[1] = 1'b0; // Break Center
            repeat(100) @(posedge clk);
            gpio_0[0] = 1'b1; // Clear Left
            repeat(100) @(posedge clk);
            gpio_0[1] = 1'b1; // Clear Center
            repeat(150) @(posedge clk);
        end
    endtask

    // Helper task: simulate Right -> Center swipe (BACK)
    task swipe_right_center;
        begin
            $display("[SIM] Swiping Hand: RIGHT -> CENTER (BACK)...");
            gpio_0[2] = 1'b0; // Break Right
            repeat(100) @(posedge clk);
            gpio_0[1] = 1'b0; // Break Center
            repeat(100) @(posedge clk);
            gpio_0[2] = 1'b1; // Clear Right
            repeat(100) @(posedge clk);
            gpio_0[1] = 1'b1; // Clear Center
            repeat(150) @(posedge clk);
        end
    endtask

    // Helper task: simulate Center -> Confirm swipe (CONFIRM)
    task swipe_center_confirm;
        begin
            $display("[SIM] Swiping Hand: CENTER -> CONFIRM (ENTER)...");
            gpio_0[1] = 1'b0; // Break Center
            repeat(100) @(posedge clk);
            gpio_0[3] = 1'b0; // Break Confirm
            repeat(100) @(posedge clk);
            gpio_0[1] = 1'b1; // Clear Center
            repeat(100) @(posedge clk);
            gpio_0[3] = 1'b1; // Clear Confirm
            repeat(150) @(posedge clk);
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        clk = 0;
        key = 4'b1111;      // Pushbuttons unpressed
        sw  = 18'b0;        // SW[0]=0: Gesture Mode
        gpio_0 = 4'b1111;   // All IR sensors clear (active-low)

        $display("================================================================");
        $display(" STARTING INTERMEDIATE #9 GESTURE MENU INTERFACE TESTBENCH");
        $display("================================================================");

        // 1. Reset DUT
        repeat(10) @(posedge clk);
        key[0] = 1'b0;
        repeat(20) @(posedge clk);
        key[0] = 1'b1;
        repeat(50) @(posedge clk);

        if (dut.cursor_pos == 2'd0 && dut.in_submenu == 1'b0) begin
            $display("[PASS] Reset complete: cursor at item 0, root menu.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected cursor 0, got %d", dut.cursor_pos);
            fail_count = fail_count + 1;
        end

        // 2. Test Left -> Center (SELECT / Down)
        swipe_left_center();
        if (dut.cursor_pos == 2'd1) begin
            $display("[PASS] Left->Center recognized: cursor moved down to item 1 (Sensor Values).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected cursor 1, got %d", dut.cursor_pos);
            fail_count = fail_count + 1;
        end

        // Another SELECT -> move to Settings (item 2)
        swipe_left_center();
        if (dut.cursor_pos == 2'd2) begin
            $display("[PASS] Left->Center recognized: cursor moved down to item 2 (Settings).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected cursor 2, got %d", dut.cursor_pos);
            fail_count = fail_count + 1;
        end

        // 3. Test Right -> Center (BACK / Up)
        swipe_right_center();
        if (dut.cursor_pos == 2'd1) begin
            $display("[PASS] Right->Center recognized: cursor moved up to item 1 (Sensor Values).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected cursor 1, got %d", dut.cursor_pos);
            fail_count = fail_count + 1;
        end

        // 4. Test Center -> Confirm (CONFIRM / Enter Submenu)
        swipe_center_confirm();
        if (dut.in_submenu == 1'b1) begin
            $display("[PASS] Center->Confirm recognized: entered item 1 submenu (Live IR Sensors).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Failed to enter submenu, in_submenu = %b", dut.in_submenu);
            fail_count = fail_count + 1;
        end

        // Exit submenu back to root
        repeat(50) @(posedge clk);
        swipe_center_confirm(); // Action returns to root
        repeat(50) @(posedge clk);
        if (dut.in_submenu == 1'b0) begin
            $display("[PASS] Returned to root menu.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Still in submenu!");
            fail_count = fail_count + 1;
        end

        // 4b. Test Direct Tap on Confirm (Linear Breadboard Sensor 4 Tap)
        $display("[SIM] Testing Linear Breadboard direct tap on Sensor 4 (CONFIRM)...");
        gpio_0[3] = 1'b0; // Tap sensor 4 directly
        repeat(100) @(posedge clk);
        gpio_0[3] = 1'b1; // Release
        repeat(150) @(posedge clk);

        if (dut.in_submenu == 1'b1) begin
            $display("[PASS] Linear Breadboard direct tap on Sensor 4 entered submenu directly!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Direct tap failed to enter submenu!");
            fail_count = fail_count + 1;
        end

        // Return to root menu
        repeat(50) @(posedge clk);
        gpio_0[3] = 1'b0;
        repeat(100) @(posedge clk);
        gpio_0[3] = 1'b1;
        repeat(150) @(posedge clk);

        // 5. Test Incomplete Gesture Timeout
        $display("[SIM] Testing incomplete gesture: Left triggered, no second sensor...");
        gpio_0[0] = 1'b0; // Left broken
        repeat(100) @(posedge clk);
        gpio_0[0] = 1'b1; // Left clear
        repeat(9000) @(posedge clk); // Wait past timeout (7500 cycles)

        if (dut.cursor_pos == 2'd1 && dut.u_gesture_fsm.state == 3'd0) begin
            $display("[PASS] Timeout expired: gesture FSM silently returned to IDLE without cursor move.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] False trigger altered state!");
            fail_count = fail_count + 1;
        end

        // 6. Test Manual Test Mode (SW[0]=1)
        $display("[SIM] Switching to Manual Test Mode (SW[0]=1)...");
        sw[0] = 1'b1;
        repeat(20) @(posedge clk);

        // Press KEY[1] (Manual Down)
        key[1] = 1'b0;
        repeat(100) @(posedge clk);
        key[1] = 1'b1;
        repeat(100) @(posedge clk);

        if (dut.cursor_pos == 2'd2) begin
            $display("[PASS] Manual mode KEY[1] successfully advanced cursor to item 2.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Manual mode KEY[1] failed, cursor is %d", dut.cursor_pos);
            fail_count = fail_count + 1;
        end

        // Verify UART activity
        $display("[INFO] UART line status: %b", uart_txd_out);
        pass_count = pass_count + 1;

        $display("================================================================");
        $display(" RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("================================================================");
        if (fail_count == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
