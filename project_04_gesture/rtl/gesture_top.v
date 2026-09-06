//=============================================================================
// Module: gesture_top
// Description: Top-Level Integration of the FPGA Gesture-Controlled Menu Interface
//              for the Altera/Intel DE2-115 Development Board.
//              Integrates:
//                1. APDS-9960 I2C Master Driver with initialization sequence
//                2. Spatial Gesture Classifier (UP, DOWN, LEFT, RIGHT, NEAR, FAR)
//                3. Hierarchical Menu FSM with Submenu Navigation & Inactivity Timers
//                4. HD44780 16x2 Character LCD Controller
//                5. 640x480 @ 60Hz VGA Graphical Dashboard Controller
//                6. 115200 Baud ASCII Serial Telemetry Logger
//                7. 8x 7-Segment Displays, Status LEDs, and Synthetic Bench Modes
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gesture_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000,
    parameter integer SIMULATION  = 0
)(
    // Clock & Asynchronous Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,               // KEY[0]: Reset_n, KEY[1]: Down, KEY[2]: Up, KEY[3]: Enter
    input  wire [17:0] SW,                // SW[17]: Synthetic Mode, SW[16:14]: Gestures

    // 16x2 Character LCD Physical Interface
    inout  wire [7:0]  LCD_DATA,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_RS,

    // ADV7123 24-bit VGA DAC Physical Interface
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,

    // 7-Segment Displays
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3,
    output wire [6:0]  HEX4, HEX5, HEX6, HEX7,

    // Status LEDs
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // Serial RS-232 UART
    output wire        UART_TXD,

    // External GPIO Header JP5 (APDS-9960 Breakout Board)
    // GPIO[0]: SCL, GPIO[1]: SDA, GPIO[2]: INT_N
    inout  wire [35:0] GPIO
);

    // -------------------------------------------------------------------------
    // Reset Synchronizer
    // -------------------------------------------------------------------------
    wire sys_reset_n;
    reset_synchronizer #(
        .STAGES(2),
        .ACTIVE_LOW_IN(1),
        .ACTIVE_LOW_OUT(1)
    ) u_reset_sync (
        .clk(CLOCK_50),
        .async_rst_in(KEY[0]),
        .sync_rst_out(sys_reset_n)
    );

    // -------------------------------------------------------------------------
    // Pushbutton Debounce with Simulation Acceleration
    // -------------------------------------------------------------------------
    localparam integer DB_CLK_FREQ = (SIMULATION) ? 10_000 : CLK_FREQ_HZ;
    localparam integer DB_MS       = (SIMULATION) ? 1      : 20;

    wire btn_enter_pulse, btn_up_pulse, btn_down_pulse;

    button_debounce #(
        .CLK_FREQ_HZ(DB_CLK_FREQ),
        .DEBOUNCE_MS(DB_MS),
        .ACTIVE_LOW_IN(1)
    ) u_db_enter (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .btn_in(KEY[3]),
        .debounced_state(),
        .pressed_pulse(btn_enter_pulse),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(DB_CLK_FREQ),
        .DEBOUNCE_MS(DB_MS),
        .ACTIVE_LOW_IN(1)
    ) u_db_up (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .btn_in(KEY[2]),
        .debounced_state(),
        .pressed_pulse(btn_up_pulse),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(DB_CLK_FREQ),
        .DEBOUNCE_MS(DB_MS),
        .ACTIVE_LOW_IN(1)
    ) u_db_down (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .btn_in(KEY[1]),
        .debounced_state(),
        .pressed_pulse(btn_down_pulse),
        .released_pulse()
    );

    // -------------------------------------------------------------------------
    // Periodic Timers (1-Second Tick and 100ms Tick)
    // -------------------------------------------------------------------------
    wire tick_1sec, tick_100ms;
    periodic_timer #(
        .PERIOD(SIMULATION ? 50_000 : CLK_FREQ_HZ),
        .WIDTH(32)
    ) u_timer_1s (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .enable(1'b1),
        .tick_in(1'b1),
        .tick_out(tick_1sec),
        .count_val()
    );

    periodic_timer #(
        .PERIOD(SIMULATION ? 5_000 : (CLK_FREQ_HZ / 10)),
        .WIDTH(32)
    ) u_timer_100ms (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .enable(1'b1),
        .tick_in(1'b1),
        .tick_out(tick_100ms),
        .count_val()
    );

    // -------------------------------------------------------------------------
    // Synthetic Mode Selection & Input Multiplexing
    // -------------------------------------------------------------------------
    wire synth_mode_en = SW[17];
    reg        synth_trigger;
    reg  [2:0] synth_code;

    // Edge detectors for switches SW[16:14] in synthetic mode
    reg [2:0] sw_gesture_d;
    always @(posedge CLOCK_50 or negedge sys_reset_n) begin
        if (!sys_reset_n)
            sw_gesture_d <= 3'b000;
        else
            sw_gesture_d <= SW[16:14];
    end
    wire sw_left_pulse = SW[16] & ~sw_gesture_d[2];
    wire sw_near_pulse = SW[15] & ~sw_gesture_d[1];
    wire sw_far_pulse  = SW[14] & ~sw_gesture_d[0];

    always @(*) begin
        if (btn_enter_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd4; // RIGHT / ENTER
        end else if (btn_up_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd1; // UP
        end else if (btn_down_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd2; // DOWN
        end else if (sw_left_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd3; // LEFT / EXIT
        end else if (sw_near_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd5; // NEAR
        end else if (sw_far_pulse) begin
            synth_trigger = 1'b1;
            synth_code    = 3'd6; // FAR
        end else begin
            synth_trigger = 1'b0;
            synth_code    = 3'd0;
        end
    end

    // -------------------------------------------------------------------------
    // APDS-9960 I2C Driver
    // -------------------------------------------------------------------------
    wire        apds_init_done;
    wire        apds_ready;
    wire [7:0]  apds_id;
    wire        apds_i2c_err;
    wire [3:0]  apds_state_dbg;
    wire [7:0]  apds_raw_u, apds_raw_d, apds_raw_l, apds_raw_r;
    wire        apds_sample_valid;

    // Physical I2C open-drain lines on JP5
    wire apds_scl, apds_sda;
    assign GPIO[0] = apds_scl;
    assign GPIO[1] = apds_sda;
    wire apds_int_n = GPIO[2];

    apds9960_i2c_driver #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(I2C_FREQ_HZ),
        .SIMULATION(SIMULATION)
    ) u_apds_driver (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .init_done(apds_init_done),
        .device_ready(apds_ready),
        .device_id(apds_id),
        .i2c_error(apds_i2c_err),
        .state_dbg(apds_state_dbg),
        .raw_u(apds_raw_u),
        .raw_d(apds_raw_d),
        .raw_l(apds_raw_l),
        .raw_r(apds_raw_r),
        .sample_valid(apds_sample_valid),
        .apds_int_n(apds_int_n),
        .scl(apds_scl),
        .sda(apds_sda)
    );

    // -------------------------------------------------------------------------
    // Gesture Decoder Engine
    // -------------------------------------------------------------------------
    wire        gesture_valid;
    wire [2:0]  gesture_code;
    wire [31:0] gesture_ascii;
    wire [15:0] gesture_counter;
    wire        gesture_active;

    gesture_decoder #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .REFRACTORY_MS(SIMULATION ? 1 : 250),
        .SIMULATION(SIMULATION)
    ) u_gesture_dec (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .raw_u(synth_mode_en ? {4'd0, SW[11:8]} : apds_raw_u),
        .raw_d(synth_mode_en ? {4'd0, SW[7:4]}  : apds_raw_d),
        .raw_l(synth_mode_en ? {4'd0, SW[3:0]}  : apds_raw_l),
        .raw_r(synth_mode_en ? {4'd0, SW[3:0]}  : apds_raw_r),
        .sample_valid(apds_sample_valid),
        .synth_mode(synth_mode_en),
        .synth_trigger(synth_trigger),
        .synth_gesture(synth_code),
        .gesture_valid(gesture_valid),
        .gesture_code(gesture_code),
        .gesture_ascii(gesture_ascii),
        .gesture_count(gesture_counter),
        .gesture_active(gesture_active),
        .fsm_state_dbg()
    );

    // -------------------------------------------------------------------------
    // Hierarchical Menu FSM
    // -------------------------------------------------------------------------
    wire [127:0] lcd_line1, lcd_line2;
    wire [1:0]   current_menu;
    wire         in_submenu;
    wire [1:0]   submenu_page;
    wire         menu_event_pulse;
    wire [1:0]   setting_backlight;
    wire         setting_beep_en;
    wire [1:0]   setting_timeout_sel;

    menu_fsm #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SIMULATION(SIMULATION)
    ) u_menu_fsm (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .gesture_valid(gesture_valid),
        .gesture_code(gesture_code),
        .last_gesture_ascii(gesture_ascii),
        .raw_u(apds_raw_u),
        .raw_d(apds_raw_d),
        .raw_l(apds_raw_l),
        .raw_r(apds_raw_r),
        .gesture_counter(gesture_counter),
        .tick_1sec(tick_1sec),
        .lcd_line1(lcd_line1),
        .lcd_line2(lcd_line2),
        .current_menu(current_menu),
        .in_submenu(in_submenu),
        .submenu_page(submenu_page),
        .menu_event_pulse(menu_event_pulse),
        .setting_backlight(setting_backlight),
        .setting_beep_en(setting_beep_en),
        .setting_timeout_sel(setting_timeout_sel)
    );

    // -------------------------------------------------------------------------
    // HD44780 16x2 Character LCD Controller
    // -------------------------------------------------------------------------
    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk           (CLOCK_50),
        .rst           (!sys_reset_n),
        .line1_text    (lcd_line1),
        .line2_text    (lcd_line2),
        .refresh_strobe(tick_100ms),
        .busy          (),
        .lcd_data      (LCD_DATA),
        .lcd_rw        (LCD_RW),
        .lcd_en        (LCD_EN),
        .lcd_rs        (LCD_RS),
        .lcd_on        (LCD_ON),
        .lcd_blon      (LCD_BLON)
    );

    // -------------------------------------------------------------------------
    // 640x480 @ 60Hz VGA Graphical Dashboard Controller
    // -------------------------------------------------------------------------
    vga_menu_display u_vga_menu (
        .clk_50(CLOCK_50),
        .reset_n(sys_reset_n),
        .current_menu(current_menu),
        .in_submenu(in_submenu),
        .submenu_page(submenu_page),
        .setting_backlight(setting_backlight),
        .setting_beep_en(setting_beep_en),
        .setting_timeout_sel(setting_timeout_sel),
        .last_gesture_code(gesture_code),
        .gesture_counter(gesture_counter),
        .raw_u(apds_raw_u),
        .raw_d(apds_raw_d),
        .raw_l(apds_raw_l),
        .raw_r(apds_raw_r),
        .vga_clk(VGA_CLK),
        .vga_hs(VGA_HS),
        .vga_vs(VGA_VS),
        .vga_blank_n(VGA_BLANK_N),
        .vga_sync_n(VGA_SYNC_N),
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B)
    );

    // -------------------------------------------------------------------------
    // 115200 Baud ASCII Telemetry Logger
    // -------------------------------------------------------------------------
    wire tx_active;
    gesture_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(115200)
    ) u_uart_log (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .gesture_valid(gesture_valid),
        .gesture_code(gesture_code),
        .gesture_ascii(gesture_ascii),
        .gesture_counter(gesture_counter),
        .current_menu(current_menu),
        .in_submenu(in_submenu),
        .submenu_page(submenu_page),
        .device_ready(apds_ready),
        .i2c_error(apds_i2c_err),
        .tick_1sec(tick_1sec),
        .uart_txd(UART_TXD),
        .tx_active_led(tx_active)
    );

    // -------------------------------------------------------------------------
    // 8x 7-Segment Displays
    // -------------------------------------------------------------------------
    // HEX7: Current Menu (0:STATUS, 1:SETTINGS, 2:SENSORS, 3:ABOUT)
    seven_seg_hex u_hex7 (.hex_digit({2'b00, current_menu}), .blank(1'b0), .seg_out(HEX7));
    // HEX6: Submenu active indicator ('S' or blank)
    seven_seg_hex u_hex6 (.hex_digit({3'b000, in_submenu}), .blank(1'b0), .seg_out(HEX6));
    // HEX5: Submenu Page (0, 1, 2)
    seven_seg_hex u_hex5 (.hex_digit({2'b00, submenu_page}), .blank(1'b0), .seg_out(HEX5));
    // HEX4: Last gesture code (1..6)
    seven_seg_hex u_hex4 (.hex_digit({1'b0, gesture_code}), .blank(1'b0), .seg_out(HEX4));
    // HEX3-0: Gesture Counter
    seven_seg_dec u_hex3 (.dec_digit(gesture_counter[15:12]), .blank(1'b0), .show_dash(1'b0), .seg_out(HEX3));
    seven_seg_dec u_hex2 (.dec_digit(gesture_counter[11:8]),  .blank(1'b0), .show_dash(1'b0), .seg_out(HEX2));
    seven_seg_dec u_hex1 (.dec_digit(gesture_counter[7:4]),   .blank(1'b0), .show_dash(1'b0), .seg_out(HEX1));
    seven_seg_dec u_hex0 (.dec_digit(gesture_counter[3:0]),   .blank(1'b0), .show_dash(1'b0), .seg_out(HEX0));

    // -------------------------------------------------------------------------
    // Status LEDs
    // -------------------------------------------------------------------------
    // LEDG:
    // [0]: Sensor Ready, [1]: Init Done, [2]: Submenu Active, [3]: Beep Enabled
    // [7:4]: Active Menu One-Hot, [8]: UART TX active
    assign LEDG[0]   = apds_ready;
    assign LEDG[1]   = apds_init_done;
    assign LEDG[2]   = in_submenu;
    assign LEDG[3]   = setting_beep_en;
    assign LEDG[4]   = (current_menu == 2'd0);
    assign LEDG[5]   = (current_menu == 2'd1);
    assign LEDG[6]   = (current_menu == 2'd2);
    assign LEDG[7]   = (current_menu == 2'd3);
    assign LEDG[8]   = tx_active;

    // LEDR:
    // [0]: UP, [1]: DOWN, [2]: LEFT, [3]: RIGHT, [4]: NEAR, [5]: FAR
    // [11:8]: Raw photodiode activity meter
    // [16]: I2C Error, [17]: Synthetic mode active
    assign LEDR[0]    = (gesture_code == 3'd1);
    assign LEDR[1]    = (gesture_code == 3'd2);
    assign LEDR[2]    = (gesture_code == 3'd3);
    assign LEDR[3]    = (gesture_code == 3'd4);
    assign LEDR[4]    = (gesture_code == 3'd5);
    assign LEDR[5]    = (gesture_code == 3'd6);
    assign LEDR[7:6]  = 2'b00;
    assign LEDR[8]    = (apds_raw_u > 8'd20);
    assign LEDR[9]    = (apds_raw_d > 8'd20);
    assign LEDR[10]   = (apds_raw_l > 8'd20);
    assign LEDR[11]   = (apds_raw_r > 8'd20);
    assign LEDR[15:12]= 4'b0000;
    assign LEDR[16]   = apds_i2c_err;
    assign LEDR[17]   = synth_mode_en;

endmodule
