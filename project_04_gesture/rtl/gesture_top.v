//=============================================================================
// Module: gesture_top
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Top-level integration module for Intermediate #9 on DE2-115:
//              - All 4 IR sensors (Left, Center, Right, Confirm) on JP5 GPIO[3:0]
//              - 20ms debounce filtering x4
//              - 2-step gesture recognition FSM (1.5s timeout):
//                  * Left -> Center    = SELECT / Cursor Down
//                  * Right -> Center   = BACK / Cursor Up
//                  * Center -> Confirm = CONFIRM Selection
//              - LEDG chase/progress driver:
//                  * LEDG[0] = Step 1 detected
//                  * LEDG[1] = Step 2 confirmed
//                  * LEDG[2] = Submenu Active
//                  * LEDG[3] = Manual Mode Active
//              - Hierarchical 3-item menu engine on 16x2 Character LCD:
//                  * Cursor '>' highlighting active row
//                  * Submenus on confirm
//                  * KEY[0] resets / returns home
//              - CP2101 USB-to-UART telemetry logger at 9600 baud 8N1:
//                  * Streams human-readable log lines to PC serial terminal
//              - Mode Select Mux via SW[0]:
//                  * SW[0]=0: Live IR gesture mode
//                  * SW[0]=1: Manual pushbutton test mode (KEY[1..3])
//              - 7-segment display of cursor position and submenu status
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gesture_top #(
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer BAUD_RATE     = 9600,
    parameter integer ACTIVE_LOW_IR = 1,
    parameter integer SIMULATION    = 0
)(
    // Clock & Asynchronous Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,               // KEY[0]: Reset/Home, KEY[1]: Down, KEY[2]: Up, KEY[3]: Confirm
    input  wire [17:0] SW,                // SW[0]: 0=Gesture Mode, 1=Manual Mode

    // 16x2 Character LCD Physical Interface
    output wire [7:0]  LCD_DATA,
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

    // Serial RS-232 / CP2101 UART
    output wire        UART_TXD,
    output wire        UART_TXD_OUT,

    // External GPIO Header JP5
    // GPIO[0]: Left, GPIO[1]: Center, GPIO[2]: Right, GPIO[3]: Confirm
    inout  wire [35:0] GPIO
);

    // -------------------------------------------------------------------------
    // 1. Reset Synchronizer (Active-High internal rst)
    // -------------------------------------------------------------------------
    wire rst;
    reset_synchronizer #(
        .STAGES(2),
        .ACTIVE_LOW_IN(1),
        .ACTIVE_LOW_OUT(0)
    ) u_rst_sync (
        .clk(CLOCK_50),
        .async_rst_in(KEY[0]),
        .sync_rst_out(rst)
    );

    // -------------------------------------------------------------------------
    // 2. Debouncers for all 4 IR Sensors (GPIO[0..3])
    // -------------------------------------------------------------------------
    wire [3:0] debounced_ir;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_ir_debouncers
            button_debounce #(
                .CLK_FREQ_HZ(CLK_FREQ_HZ),
                .DEBOUNCE_MS(SIMULATION ? 1 : 20),
                .ACTIVE_LOW_IN(ACTIVE_LOW_IR)
            ) u_db (
                .clk(CLOCK_50),
                .rst(rst),
                .btn_in(GPIO[i]),
                .debounced_state(debounced_ir[i]),
                .pressed_pulse(),
                .released_pulse()
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 3. Debouncers for Manual Pushbuttons (KEY[1..3])
    // -------------------------------------------------------------------------
    wire btn_select_p, btn_back_p, btn_confirm_p;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(1)
    ) u_db_btn1 (
        .clk(CLOCK_50), .rst(rst), .btn_in(KEY[1]),
        .debounced_state(), .pressed_pulse(btn_select_p), .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(1)
    ) u_db_btn2 (
        .clk(CLOCK_50), .rst(rst), .btn_in(KEY[2]),
        .debounced_state(), .pressed_pulse(btn_back_p), .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(1)
    ) u_db_btn3 (
        .clk(CLOCK_50), .rst(rst), .btn_in(KEY[3]),
        .debounced_state(), .pressed_pulse(btn_confirm_p), .released_pulse()
    );

    // -------------------------------------------------------------------------
    // 4. Gesture Sequence FSM (2-Step Recognition with Timeout)
    // -------------------------------------------------------------------------
    wire gesture_select_pulse;
    wire gesture_back_pulse;
    wire gesture_confirm_pulse;
    wire step1_active;
    wire step2_confirmed;

    ir_gesture_sequence_fsm #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .TIMEOUT_MS(1500),
        .SIMULATION(SIMULATION)
    ) u_gesture_fsm (
        .clk(CLOCK_50),
        .rst(rst),
        .ir_l(debounced_ir[0]),
        .ir_c(debounced_ir[1]),
        .ir_r(debounced_ir[2]),
        .ir_k(debounced_ir[3]),
        .sw_manual_mode(SW[0]),
        .btn_select_pulse(btn_select_p),
        .btn_back_pulse(btn_back_p),
        .btn_confirm_pulse(btn_confirm_p),
        .gesture_select_pulse(gesture_select_pulse),
        .gesture_back_pulse(gesture_back_pulse),
        .gesture_confirm_pulse(gesture_confirm_pulse),
        .step1_active(step1_active),
        .step2_confirmed(step2_confirmed)
    );

    // -------------------------------------------------------------------------
    // 5. LCD Menu Renderer (Hierarchical 3-item Navigable Menu)
    // -------------------------------------------------------------------------
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire [1:0]   cursor_pos;
    wire         in_submenu;
    wire         menu_event_pulse;
    wire [2:0]   menu_event_type;

    lcd_menu_renderer u_menu_renderer (
        .clk(CLOCK_50),
        .rst(rst),
        .select_pulse(gesture_select_pulse),
        .back_pulse(gesture_back_pulse),
        .confirm_pulse(gesture_confirm_pulse),
        .reset_home_pulse(rst),
        .raw_ir_sensors(debounced_ir),
        .sw_manual_mode(SW[0]),
        .cursor_pos(cursor_pos),
        .in_submenu(in_submenu),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .event_pulse(menu_event_pulse),
        .event_type(menu_event_type)
    );

    // -------------------------------------------------------------------------
    // 6. HD44780 16x2 Character LCD Driver
    // -------------------------------------------------------------------------
    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk(CLOCK_50),
        .rst(rst),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .refresh_strobe(1'b0),
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // -------------------------------------------------------------------------
    // 7. CP2101 UART Telemetry Logger (9600 Baud 8N1)
    // -------------------------------------------------------------------------
    inter9_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_log (
        .clk(CLOCK_50),
        .rst(rst),
        .gesture_select_pulse(gesture_select_pulse),
        .gesture_back_pulse(gesture_back_pulse),
        .gesture_confirm_pulse(gesture_confirm_pulse),
        .menu_event_pulse(menu_event_pulse),
        .menu_event_type(menu_event_type),
        .cursor_pos(cursor_pos),
        .uart_txd(UART_TXD)
    );

    assign UART_TXD_OUT = UART_TXD;

    // -------------------------------------------------------------------------
    // 8. Visual LED Feedback & Chase Effect
    // -------------------------------------------------------------------------
    assign LEDG[0]   = step1_active;
    assign LEDG[1]   = step2_confirmed;
    assign LEDG[2]   = in_submenu;
    assign LEDG[3]   = SW[0];           // Manual mode indicator
    assign LEDG[8:4] = 5'b0;

    assign LEDR[3:0]   = debounced_ir;  // Show live debounced IR triggers
    assign LEDR[16:4]  = 13'b0;
    assign LEDR[17]    = SW[0];

    // -------------------------------------------------------------------------
    // 9. Seven-Segment Displays (HEX0..7)
    // -------------------------------------------------------------------------
    // HEX0: Current Menu Cursor (0, 1, 2)
    seven_seg_dec u_hex0 (
        .dec_digit({2'b00, cursor_pos}),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX0)
    );

    // HEX1: Submenu Flag (1 if inside submenu, 0 if root menu)
    seven_seg_dec u_hex1 (
        .dec_digit({3'b000, in_submenu}),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX1)
    );

    // HEX2..HEX7: Blank
    assign HEX2 = 7'b111_1111;
    assign HEX3 = 7'b111_1111;
    assign HEX4 = 7'b111_1111;
    assign HEX5 = 7'b111_1111;
    assign HEX6 = 7'b111_1111;
    assign HEX7 = 7'b111_1111;

    // -------------------------------------------------------------------------
    // 10. VGA Interface Safe Tie-Off
    // -------------------------------------------------------------------------
    assign VGA_CLK     = 1'b0;
    assign VGA_HS      = 1'b1;
    assign VGA_VS      = 1'b1;
    assign VGA_BLANK_N = 1'b0;
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_R       = 8'h00;
    assign VGA_G       = 8'h00;
    assign VGA_B       = 8'h00;

endmodule
