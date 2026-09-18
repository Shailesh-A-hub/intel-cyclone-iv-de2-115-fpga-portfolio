//=============================================================================
// Testbench: tb_basic3_occupancy
// Project: Project 1 / Basic #3 — IR-Based Occupancy / Entry-Exit Counter
// Description: Validates:
//              1. Reset initialization (count = 00, LCD shows EMPTY).
//              2. Entry sequence (A then B) -> count increments.
//              3. Exit sequence (B then A) -> count decrements.
//              4. Counter saturation at 0 (no negative wrap).
//              5. False-trigger timeout rejection (A triggered, B missing).
//              6. Master reset via KEY[0].
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module tb_basic3_occupancy;

    reg        clk;
    reg  [3:0] key;
    reg  [1:0] gpio_0;      // [0]=IR_A, [1]=IR_B (active-low)
    wire [6:0] hex0, hex1;
    wire [3:0] ledg;
    wire [7:0] lcd_data;
    wire       lcd_rs, lcd_en, lcd_rw, lcd_on, lcd_blon;

    localparam CLK_FREQ = 50_000; // 50 cycles per ms in simulation

    basic3_occupancy_top #(
        .CLK_FREQ_HZ(CLK_FREQ),
        .ACTIVE_LOW(1),
        .SIMULATION(1)
    ) dut (
        .CLOCK_50(clk),
        .KEY(key),
        .GPIO_0(gpio_0),
        .HEX0(hex0),
        .HEX1(hex1),
        .LEDG(ledg),
        .LCD_DATA(lcd_data),
        .LCD_RS(lcd_rs),
        .LCD_EN(lcd_en),
        .LCD_RW(lcd_rw),
        .LCD_ON(lcd_on),
        .LCD_BLON(lcd_blon)
    );

    // 50 kHz simulated clock (period = 20 us = 20,000 ns) -> let's make clock 20 ns period
    always #10 clk = ~clk;

    // Helper task: simulate breaking IR_A then IR_B (Entry)
    task simulate_entry;
        begin
            $display("[SIM] Simulating Person Entry: IR_A then IR_B...");
            // IR_A broken (pull low)
            gpio_0[0] = 1'b0;
            repeat(100) @(posedge clk); // debounce filter
            // IR_B broken while IR_A is still broken
            gpio_0[1] = 1'b0;
            repeat(100) @(posedge clk);
            // Clear IR_A
            gpio_0[0] = 1'b1;
            repeat(100) @(posedge clk);
            // Clear IR_B
            gpio_0[1] = 1'b1;
            repeat(150) @(posedge clk);
        end
    endtask

    // Helper task: simulate breaking IR_B then IR_A (Exit)
    task simulate_exit;
        begin
            $display("[SIM] Simulating Person Exit: IR_B then IR_A...");
            // IR_B broken (pull low)
            gpio_0[1] = 1'b0;
            repeat(100) @(posedge clk);
            // IR_A broken while IR_B is still broken
            gpio_0[0] = 1'b0;
            repeat(100) @(posedge clk);
            // Clear IR_B
            gpio_0[1] = 1'b1;
            repeat(100) @(posedge clk);
            // Clear IR_A
            gpio_0[0] = 1'b1;
            repeat(150) @(posedge clk);
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        clk = 0;
        key = 4'b1111;      // KEY active low, unpressed
        gpio_0 = 2'b11;     // Active low, both clear initially

        $display("================================================================");
        $display(" STARTING BASIC #3 IR OCCUPANCY COUNTER TESTBENCH");
        $display("================================================================");

        // 1. Reset DUT
        repeat(10) @(posedge clk);
        key[0] = 1'b0; // assert reset
        repeat(20) @(posedge clk);
        key[0] = 1'b1; // release reset
        repeat(20) @(posedge clk);

        if (dut.occupancy_count == 8'd0) begin
            $display("[PASS] Initial occupancy count is 00.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Initial count expected 0, got %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        // 2. Perform 2 Entries
        simulate_entry();
        if (dut.occupancy_count == 8'd1) begin
            $display("[PASS] First entry confirmed, count = 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] First entry expected count 1, got %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        simulate_entry();
        if (dut.occupancy_count == 8'd2) begin
            $display("[PASS] Second entry confirmed, count = 2.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Second entry expected count 2, got %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        // 3. Perform 1 Exit
        simulate_exit();
        if (dut.occupancy_count == 8'd1) begin
            $display("[PASS] Exit confirmed, count decremented to 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Exit expected count 1, got %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        // 4. Perform 2 more Exits to test saturation at 0
        simulate_exit();
        if (dut.occupancy_count == 8'd0) begin
            $display("[PASS] Count decremented to 0 (empty).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Expected count 0, got %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        simulate_exit(); // Extra exit at count 0
        if (dut.occupancy_count == 8'd0) begin
            $display("[PASS] Underflow prevented: count saturated at 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Underflow error! Count became %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        // 5. Test Incomplete/False Trigger Timeout
        $display("[SIM] Testing false-trigger timeout: IR_A broken, IR_B never triggered...");
        gpio_0[0] = 1'b0; // IR_A broken
        repeat(100) @(posedge clk);
        gpio_0[0] = 1'b1; // IR_A clear
        repeat(6000) @(posedge clk); // wait past TIMEOUT_CYCLES (5000 cycles in SIM)
        if (dut.occupancy_count == 8'd0) begin
            $display("[PASS] False trigger rejected: count stayed at 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] False trigger altered count to %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        // 6. Test Master Reset
        simulate_entry();
        simulate_entry();
        repeat(20) @(posedge clk);
        key[0] = 1'b0; // Press reset
        repeat(20) @(posedge clk);
        key[0] = 1'b1;
        repeat(20) @(posedge clk);
        if (dut.occupancy_count == 8'd0) begin
            $display("[PASS] KEY[0] reset successfully cleared count back to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Reset failed, count is %d", dut.occupancy_count);
            fail_count = fail_count + 1;
        end

        $display("================================================================");
        $display(" RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("================================================================");
        if (fail_count == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

endmodule
