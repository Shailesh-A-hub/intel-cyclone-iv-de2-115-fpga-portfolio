//=============================================================================
// Module: intermediate9_gesture_top
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Direct hardware implementation of Intermediate #9:
//              - All 4 IR sensors (Left, Center, Right, Confirm) on JP5 / GPIO_0[3:0]
//              - 20ms debounce filtering x4
//              - 2-step gesture recognition FSM (1.5s timeout):
//                  * Left -> Center   = SELECT / Cursor Down
//                  * Right -> Center  = BACK / Cursor Up
//                  * Center -> Confirm = CONFIRM Selection
//              - LEDG chase/progress driver:
//                  * LEDG[0] = Step 1 detected
//                  * LEDG[1] = Step 2 confirmed
//              - Hierarchical 3-item menu engine on 16x2 Character LCD:
//                  * Cursor '>' highlighting active row
//                  * Submenus on confirm
//                  * KEY[0] resets / returns home
//              - CP2101 USB-to-UART telemetry logger at 9600 baud 8N1:
//                  * Streams human-readable log lines to PC serial terminal
//              - Mode Select Mux via SW[0]:
//                  * SW[0]=0: Live IR gesture mode
//                  * SW[0]=1: Manual pushbutton test mode (KEY[1..3])
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module intermediate9_gesture_top #(
    parameter integer CLK_FREQ_HZ    = 50_000_000,
    parameter integer BAUD_RATE      = 9600,
    parameter integer ACTIVE_LOW_IR  = 1,
    parameter integer SIMULATION     = 0
)(
    // System Clock and Master Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0]=Home/Reset, KEY[1]=Down, KEY[2]=Up, KEY[3]=Confirm
    input  wire [17:0] SW,              // SW[0]=Mode Select (0=Gesture, 1=Manual)

    // External IR Sensors (JP5 / GPIO_0 Pins 1..4)
    input  wire [3:0]  GPIO_0,          // [0]=Left, [1]=Center, [2]=Right, [3]=Confirm

    // UART Output to CP2101 Module RX Pin (JP6 Pin 1)
    output wire        UART_TXD_OUT,

    // Green Status and Chase LEDs
    output wire [3:0]  LEDG,            // [0]=Step1, [1]=Step2, [2]=Spare, [3]=Spare

    // HD44780 16x2 Character LCD
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_EN,
    output wire        LCD_RW,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    // 1. Synchronized Active-High Reset
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

    // 2. Debouncers for all 4 IR Sensors
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
                .btn_in(GPIO_0[i]),
                .debounced_state(debounced_ir[i]),
                .pressed_pulse(),
                .released_pulse()
            );
        end
    endgenerate

    // 3. Debouncers for Manual Pushbuttons (KEY[1..3])
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

    // 4. Gesture Sequence FSM
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

    assign LEDG[0]   = step1_active;
    assign LEDG[1]   = step2_confirmed;
    assign LEDG[3:2] = 2'b00;

    // 5. LCD Menu Renderer
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

    // 6. HD44780 Character LCD Driver
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

    // 7. CP2101 UART Telemetry Logger (9600 Baud 8N1)
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
        .uart_txd(UART_TXD_OUT)
    );

endmodule
