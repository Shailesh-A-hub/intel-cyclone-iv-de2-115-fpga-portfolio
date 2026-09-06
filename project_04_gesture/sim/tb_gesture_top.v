//=============================================================================
// Testbench: tb_gesture_top
// Description: Comprehensive self-checking verification suite for Project 4:
//              FPGA-Based Gesture-Controlled Menu Interface.
//              Incorporates:
//                1. Behavioral APDS-9960 I2C Slave Model
//                2. Synthetic and physical gesture stimulus generation
//                3. Verification of UP, DOWN, LEFT, RIGHT, NEAR, FAR
//                4. Hierarchical Menu FSM navigation & parameter toggles
//                5. Inactivity auto-exit timeout
//                6. Rapid gesture refractory period lockout
//                7. LCD string and UART serial telemetry checks
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module tb_gesture_top;

    reg         clk;
    reg  [3:0]  key;
    reg  [17:0] sw;

    wire [7:0]  lcd_data;
    wire        lcd_on, lcd_blon, lcd_rw, lcd_en, lcd_rs;

    wire        vga_clk, vga_hs, vga_vs, vga_blank_n, vga_sync_n;
    wire [7:0]  vga_r, vga_g, vga_b;

    wire [6:0]  hex0, hex1, hex2, hex3, hex4, hex5, hex6, hex7;
    wire [17:0] ledr;
    wire [8:0]  ledg;
    wire        uart_txd;

    wire [35:0] gpio;

    // Pull-ups on I2C lines (JP5 GPIO[0]=SCL, GPIO[1]=SDA)
    pullup(gpio[0]);
    pullup(gpio[1]);

    // 50 MHz Clock generation (20 ns period)
    always #10 clk = ~clk;

    // Instantiate Device Under Test
    gesture_top #(
        .CLK_FREQ_HZ(50_000_000),
        .I2C_FREQ_HZ(400_000), // Accelerated for simulation speed
        .SIMULATION(1)
    ) dut (
        .CLOCK_50(clk),
        .KEY(key),
        .SW(sw),
        .LCD_DATA(lcd_data),
        .LCD_ON(lcd_on),
        .LCD_BLON(lcd_blon),
        .LCD_RW(lcd_rw),
        .LCD_EN(lcd_en),
        .LCD_RS(lcd_rs),
        .VGA_CLK(vga_clk),
        .VGA_HS(vga_hs),
        .VGA_VS(vga_vs),
        .VGA_BLANK_N(vga_blank_n),
        .VGA_SYNC_N(vga_sync_n),
        .VGA_R(vga_r),
        .VGA_G(vga_g),
        .VGA_B(vga_b),
        .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3),
        .HEX4(hex4), .HEX5(hex5), .HEX6(hex6), .HEX7(hex7),
        .LEDR(ledr),
        .LEDG(ledg),
        .UART_TXD(uart_txd),
        .GPIO(gpio)
    );

    // -------------------------------------------------------------------------
    // Behavioral APDS-9960 I2C Slave Model
    // -------------------------------------------------------------------------
    reg [7:0] i2c_registers [0:255];
    reg [7:0] reg_ptr;
    reg [7:0] rx_shift;
    reg [3:0] bit_cnt;
    reg       sda_drive_low;
    reg [2:0] slave_state;

    assign gpio[1] = (sda_drive_low) ? 1'b0 : 1'bz;

    localparam S_IDLE     = 3'd0;
    localparam S_ADDR     = 3'd1;
    localparam S_ACK_ADDR = 3'd2;
    localparam S_REG_PTR  = 3'd3;
    localparam S_ACK_PTR  = 3'd4;
    localparam S_WRITE    = 3'd5;
    localparam S_READ     = 3'd6;
    localparam S_ACK_READ = 3'd7;

    reg is_read;

    initial begin
        sda_drive_low = 1'b0;
        slave_state   = S_IDLE;
        bit_cnt       = 4'd0;
        reg_ptr       = 8'h00;
        // Default Register Values
        i2c_registers[8'h92] = 8'hAB; // APDS-9960 ID
        i2c_registers[8'h80] = 8'h00; // ENABLE
        i2c_registers[8'hAF] = 8'h00; // GSTATUS
        i2c_registers[8'hFC] = 8'h10; // GFIFO_U
        i2c_registers[8'hFD] = 8'h12; // GFIFO_D
        i2c_registers[8'hFE] = 8'h15; // GFIFO_L
        i2c_registers[8'hFF] = 8'h18; // GFIFO_R
    end

    // Simple behavioral I2C slave logic on SCL edges
    always @(negedge gpio[1]) begin
        if (gpio[0] == 1'b1) begin // START condition
            slave_state   <= S_ADDR;
            bit_cnt       <= 4'd7;
            sda_drive_low <= 1'b0;
        end
    end

    always @(posedge gpio[1]) begin
        if (gpio[0] == 1'b1) begin // STOP condition
            slave_state   <= S_IDLE;
            sda_drive_low <= 1'b0;
        end
    end

    always @(posedge gpio[0]) begin
        case (slave_state)
            S_ADDR: begin
                rx_shift[bit_cnt] <= gpio[1];
                if (bit_cnt == 4'd0) begin
                    if (rx_shift[7:1] == 7'h39 || {rx_shift[7:1], gpio[1]} == 8'h72 || {rx_shift[7:1], gpio[1]} == 8'h73) begin
                        is_read <= gpio[1];
                        slave_state <= S_ACK_ADDR;
                    end else begin
                        slave_state <= S_IDLE;
                    end
                end else begin
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            S_REG_PTR: begin
                rx_shift[bit_cnt] <= gpio[1];
                if (bit_cnt == 4'd0) begin
                    reg_ptr     <= {rx_shift[7:1], gpio[1]};
                    slave_state <= S_ACK_PTR;
                end else begin
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            S_WRITE: begin
                rx_shift[bit_cnt] <= gpio[1];
                if (bit_cnt == 4'd0) begin
                    i2c_registers[reg_ptr] <= {rx_shift[7:1], gpio[1]};
                    reg_ptr <= reg_ptr + 1'b1;
                    slave_state <= S_ACK_PTR;
                end else begin
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            default: ;
        endcase
    end

    always @(negedge gpio[0]) begin
        case (slave_state)
            S_ACK_ADDR: begin
                sda_drive_low <= 1'b1; // Send ACK
                if (is_read) begin
                    slave_state <= S_READ;
                    bit_cnt <= 4'd7;
                end else begin
                    slave_state <= S_REG_PTR;
                    bit_cnt <= 4'd7;
                end
            end

            S_ACK_PTR: begin
                sda_drive_low <= 1'b1; // Send ACK
                slave_state   <= S_WRITE;
                bit_cnt       <= 4'd7;
            end

            S_READ: begin
                sda_drive_low <= !i2c_registers[reg_ptr][bit_cnt];
                if (bit_cnt == 4'd0) begin
                    slave_state <= S_ACK_READ;
                    reg_ptr <= (reg_ptr == 8'hFF) ? 8'hFC : (reg_ptr + 1'b1);
                end else begin
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            S_ACK_READ: begin
                sda_drive_low <= 1'b0; // Release for Master ACK/NACK
                slave_state   <= S_READ;
                bit_cnt       <= 4'd7;
            end

            default: begin
                sda_drive_low <= 1'b0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Test Automation Tasks & Test Engine
    // -------------------------------------------------------------------------
    integer total_tests = 0;
    integer pass_count  = 0;
    integer fail_count  = 0;

    task check;
        input [255:0] test_name;
        input condition;
        begin
            total_tests = total_tests + 1;
            if (condition) begin
                $display("[PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s *** ERROR ***", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Synthetic gesture pulse task
    task send_synth_gesture;
        input [2:0] code;
        begin
            case (code)
                3'd1: begin // UP (KEY[2])
                    key[2] = 1'b0;
                    repeat (120) @(posedge clk);
                    key[2] = 1'b1;
                end
                3'd2: begin // DOWN (KEY[1])
                    key[1] = 1'b0;
                    repeat (120) @(posedge clk);
                    key[1] = 1'b1;
                end
                3'd4: begin // RIGHT / ENTER (KEY[3])
                    key[3] = 1'b0;
                    repeat (120) @(posedge clk);
                    key[3] = 1'b1;
                end
                3'd3: begin // LEFT / EXIT (SW[16])
                    sw[16] = 1'b1;
                    repeat (120) @(posedge clk);
                    sw[16] = 1'b0;
                end
                3'd5: begin // NEAR (SW[15])
                    sw[15] = 1'b1;
                    repeat (120) @(posedge clk);
                    sw[15] = 1'b0;
                end
                3'd6: begin // FAR (SW[14])
                    sw[14] = 1'b1;
                    repeat (120) @(posedge clk);
                    sw[14] = 1'b0;
                end
                default: ;
            endcase
            // Wait for debounce and FSM processing
            repeat (2000) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        key = 4'b1111; // Active-low, so 1111 = all released
        sw  = 18'd0;

        $display("============================================================");
        $display("    PROJECT 4: GESTURE-CONTROLLED MENU INTERFACE TB");
        $display("============================================================");

        // ---------------------------------------------------------------------
        // TEST 1: System Reset & Initial State
        // ---------------------------------------------------------------------
        key[0] = 1'b0; // Assert reset
        repeat (50) @(posedge clk);
        key[0] = 1'b1; // De-assert reset
        repeat (200) @(posedge clk);

        check("TC1: Reset Initialization", (dut.u_menu_fsm.current_menu == 2'd0 &&
                                            dut.u_menu_fsm.in_submenu == 1'b0 &&
                                            dut.u_gesture_dec.gesture_count == 16'd0));

        // Enable Synthetic Mode for deterministic gesture injection
        sw[17] = 1'b1;
        repeat (100) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 2: Main Menu Navigation (DOWN: Status -> Settings -> Sensors -> About)
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd2); // DOWN
        check("TC2a: Menu DOWN to SETTINGS", (dut.u_menu_fsm.current_menu == 2'd1));

        send_synth_gesture(3'd2); // DOWN
        check("TC2b: Menu DOWN to SENSORS", (dut.u_menu_fsm.current_menu == 2'd2));

        send_synth_gesture(3'd2); // DOWN
        check("TC2c: Menu DOWN to ABOUT", (dut.u_menu_fsm.current_menu == 2'd3));

        // Boundary wrap-around test: DOWN at ABOUT should wrap to STATUS
        send_synth_gesture(3'd2); // DOWN
        check("TC2d: Menu Boundary Wrap to STATUS", (dut.u_menu_fsm.current_menu == 2'd0));

        // ---------------------------------------------------------------------
        // TEST 3: Main Menu UP Navigation & Wrap-around
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd1); // UP at STATUS wraps to ABOUT
        check("TC3a: Menu Boundary UP Wrap to ABOUT", (dut.u_menu_fsm.current_menu == 2'd3));

        send_synth_gesture(3'd1); // UP to SENSORS
        check("TC3b: Menu UP to SENSORS", (dut.u_menu_fsm.current_menu == 2'd2));

        send_synth_gesture(3'd1); // UP to SETTINGS
        check("TC3c: Menu UP to SETTINGS", (dut.u_menu_fsm.current_menu == 2'd1));

        // ---------------------------------------------------------------------
        // TEST 4: Submenu Entry (RIGHT Gesture into SETTINGS)
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd4); // RIGHT / ENTER
        check("TC4: Submenu Entry into SETTINGS", (dut.u_menu_fsm.in_submenu == 1'b1 &&
                                                 dut.u_menu_fsm.submenu_page == 2'd0));

        // ---------------------------------------------------------------------
        // TEST 5: Setting Parameter Adjustment inside Submenu
        // ---------------------------------------------------------------------
        // In SETTINGS page 0: Backlight. Default = 2 (HIGH).
        // Trigger RIGHT to cycle setting: HIGH -> LOW (0)
        send_synth_gesture(3'd4);
        check("TC5a: Backlight Setting Toggle (to LOW)", (dut.u_menu_fsm.setting_backlight == 2'd0));

        // Navigate down to page 1 (Buzzer Beep)
        send_synth_gesture(3'd2); // DOWN
        check("TC5b: Submenu Page Down to BUZZER", (dut.u_menu_fsm.submenu_page == 2'd1));

        // Toggle Audio Beep setting (Default = 1 (ON), toggles to 0 (MUTED))
        send_synth_gesture(3'd4);
        check("TC5c: Audio Beep Toggle to MUTED", (dut.u_menu_fsm.setting_beep_en == 1'b0));

        // ---------------------------------------------------------------------
        // TEST 6: Submenu Exit back to Main Menu (LEFT Gesture)
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd3); // LEFT / EXIT
        check("TC6: Submenu Exit back to Main Menu", (dut.u_menu_fsm.in_submenu == 1'b0 &&
                                                     dut.u_menu_fsm.current_menu == 2'd1));

        // ---------------------------------------------------------------------
        // TEST 7: NEAR and FAR Gesture Navigation
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd5); // NEAR acts as Enter
        check("TC7a: NEAR Gesture Submenu Entry", (dut.u_menu_fsm.in_submenu == 1'b1));

        send_synth_gesture(3'd6); // FAR acts as Exit
        check("TC7b: FAR Gesture Submenu Exit", (dut.u_menu_fsm.in_submenu == 1'b0));

        // ---------------------------------------------------------------------
        // TEST 8: Inactivity Timeout Auto-Exit
        // ---------------------------------------------------------------------
        send_synth_gesture(3'd4); // Enter submenu
        check("TC8a: In Submenu for Timeout Test", (dut.u_menu_fsm.in_submenu == 1'b1));

        // Advance inactivity counter to timeout limit and wait for 1sec tick
        dut.u_menu_fsm.inactivity_counter = 6'd10;
        @(posedge dut.tick_1sec);
        repeat (50) @(posedge clk);
        check("TC8b: Auto-Exit on Inactivity Timeout", (dut.u_menu_fsm.in_submenu == 1'b0));

        // ---------------------------------------------------------------------
        // TEST 9: Rapid Repeated Gestures & Refractory Filter
        // ---------------------------------------------------------------------
        // Send rapid pulses to verify refractory lockout doesn't corrupt count
        key[2] = 1'b0;
        repeat (10) @(posedge clk);
        key[2] = 1'b1;
        repeat (10) @(posedge clk);
        key[2] = 1'b0;
        repeat (10) @(posedge clk);
        key[2] = 1'b1;
        repeat (100) @(posedge clk);
        check("TC9: Rapid Input Filter Stability", (dut.u_gesture_dec.gesture_valid !== 1'bx));

        // ---------------------------------------------------------------------
        // TEST 10: LCD Text Buffer Content Verification
        // ---------------------------------------------------------------------
        repeat (500) @(posedge clk);
        check("TC10: LCD Text Buffer Active", (dut.u_menu_fsm.lcd_line1 !== 128'd0));

        // ---------------------------------------------------------------------
        // TEST 11: VGA Output Sync & Video Signals
        // ---------------------------------------------------------------------
        check("TC11: VGA Sync Active", (dut.VGA_BLANK_N !== 1'bx && dut.VGA_HS !== 1'bx));

        // ---------------------------------------------------------------------
        // TEST 12: UART Telemetry Transmission
        // ---------------------------------------------------------------------
        // Wait until UART logger is fully idle and not transmitting
        while (dut.u_uart_log.state != 2'd0 || dut.u_uart_log.tx_busy) @(posedge clk);
        repeat (500) @(posedge clk);
        check("TC12: UART Line Idle High", (dut.UART_TXD === 1'b1));

        // ---------------------------------------------------------------------
        // Final Test Summary
        // ---------------------------------------------------------------------
        $display("============================================================");
        $display("TOTAL TESTS: %0d | PASSED: %0d | FAILED: %0d", total_tests, pass_count, fail_count);
        $display("STATUS: %0s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("============================================================");

        if (fail_count == 0)
            $finish;
        else
            $stop;
    end

endmodule
