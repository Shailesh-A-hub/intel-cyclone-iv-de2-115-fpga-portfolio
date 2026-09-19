//=============================================================================
// Module: gesture_top
// Project: Project 4 - FPGA Contactless Cross Gesture Recognition & Menu System
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Implements 4-direction optical IR gesture recognition:
//              - 4 TCRT5000 IR sensors in Cross / Diamond arrangement on JP5:
//                  * S1: Facing us (South / Near)      on JP5 Pin 3 (PIN_AB21)
//                  * S2: Left      (West)              on JP5 Pin 4 (PIN_Y17)
//                  * S3: Opposite  (North / Far)       on JP5 Pin 5 (PIN_AC21)
//                  * S4: Right     (East)              on JP5 Pin 6 (PIN_Y16)
//              - Direction Classification via ir_cross_gesture_decoder:
//                  * Swipe Left  -> Right : "RIGHT" [->]
//                  * Swipe Right -> Left  : "LEFT"  [<-]
//                  * Swipe S1    -> S3    : "UP"    [^ ]
//                  * Swipe S3    -> S1    : "DOWN"  [v ]
//                  * Direct point / tap on any sensor triggers that direction
//              - 16x2 Character LCD Display:
//                  * SW[1]=0: Live Direction Visualizer ("DIR: LEFT", "DIR: RIGHT", etc.)
//                             with 4-digit gesture count and live 4-sensor bitmask
//                  * SW[1]=1: Interactive 3-item Menu Navigation
//              - CP2101 USB-to-UART Bridge on JP5 Pin 1 (PIN_AB22) + DB9 (PIN_G9)
//              - 7-Segment Display (HEX0: U/d/L/r, HEX3..1: gesture counter)
//              - Status LEDs (LEDG[3:0] for direction, LEDR[3:0] for live sensors)
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gesture_top #(
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer BAUD_RATE     = 115200,
    parameter integer ACTIVE_LOW_IR = 1,
    parameter integer SIMULATION    = 0
)(
    // Clock & Asynchronous Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,               // KEY[0]: Reset/Home, KEY[1]: Down/Left, KEY[2]: Up/Right, KEY[3]: Confirm
    input  wire [17:0] SW,                // SW[0]: Manual Mode, SW[1]: Menu Mode, SW[3]: Invert Y-axis

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
    // GPIO[0]: S1 (facing us), GPIO[1]: S2 (Left), GPIO[2]: S3 (opposite), GPIO[3]: S4 (Right)
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
    // 2. Cross Sensor Mapping & Spatial Decoder (UP, DOWN, LEFT, RIGHT)
    // -------------------------------------------------------------------------
    // Physical arrangement on breadboard:
    // S1: Facing us (South), S2: Left (West), S3: Opposite (North), S4: Right (East)
    // SW[3] allows inverting Y-axis if desired
    wire ir_raw_north = (SW[3]) ? GPIO[0] : GPIO[2]; // S3 by default
    wire ir_raw_south = (SW[3]) ? GPIO[2] : GPIO[0]; // S1 by default
    wire ir_raw_west  = GPIO[1];                      // S2 Left
    wire ir_raw_east  = GPIO[3];                      // S4 Right

    wire        cross_gesture_valid;
    wire [2:0]  cross_gesture_code;
    wire [31:0] cross_gesture_ascii;
    wire [15:0] cross_gesture_count;
    wire [3:0]  cross_active_led; // [3]=East/S4, [2]=West/S2, [1]=South/S1, [0]=North/S3

    ir_cross_gesture_decoder #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 10),
        .SWIPE_WINDOW_MS(SIMULATION ? 5 : 400),
        .REFRACTORY_MS(SIMULATION ? 3 : 250),
        .ACTIVE_LOW(ACTIVE_LOW_IR),
        .SIMULATION(SIMULATION)
    ) u_cross_decoder (
        .clk(CLOCK_50),
        .reset_n(!rst),
        .ir_raw_u(ir_raw_north),
        .ir_raw_d(ir_raw_south),
        .ir_raw_l(ir_raw_west),
        .ir_raw_r(ir_raw_east),
        .gesture_valid(cross_gesture_valid),
        .gesture_code(cross_gesture_code),
        .gesture_ascii(cross_gesture_ascii),
        .gesture_count(cross_gesture_count),
        .sensor_active_led(cross_active_led)
    );

    // -------------------------------------------------------------------------
    // 3. Manual Pushbutton Debouncers (KEY[1..3])
    // -------------------------------------------------------------------------
    wire btn1_pulse, btn2_pulse, btn3_pulse;

    button_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .DEBOUNCE_MS(SIMULATION ? 1 : 20), .ACTIVE_LOW_IN(1))
    u_db_btn1 (.clk(CLOCK_50), .rst(rst), .btn_in(KEY[1]), .debounced_state(), .pressed_pulse(btn1_pulse), .released_pulse());

    button_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .DEBOUNCE_MS(SIMULATION ? 1 : 20), .ACTIVE_LOW_IN(1))
    u_db_btn2 (.clk(CLOCK_50), .rst(rst), .btn_in(KEY[2]), .debounced_state(), .pressed_pulse(btn2_pulse), .released_pulse());

    button_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .DEBOUNCE_MS(SIMULATION ? 1 : 20), .ACTIVE_LOW_IN(1))
    u_db_btn3 (.clk(CLOCK_50), .rst(rst), .btn_in(KEY[3]), .debounced_state(), .pressed_pulse(btn3_pulse), .released_pulse());

    // Unified Gesture Event Multiplexer (Live IR vs Manual Test Mode SW[0])
    wire       active_gesture_valid = (SW[0]) ? (btn1_pulse || btn2_pulse || btn3_pulse) : cross_gesture_valid;
    wire [2:0] active_gesture_code  = (SW[0]) ? (btn1_pulse ? 3'd2 : (btn2_pulse ? 3'd1 : 3'd4)) : cross_gesture_code;

    // -------------------------------------------------------------------------
    // 4. Direction Memory & LCD Display Generator
    // -------------------------------------------------------------------------
    reg [2:0]  last_gesture_code;
    reg [15:0] total_gesture_counter;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            last_gesture_code     <= 3'd0; // None / Ready
            total_gesture_counter <= 16'd0;
        end else if (active_gesture_valid) begin
            last_gesture_code     <= active_gesture_code;
            total_gesture_counter <= total_gesture_counter + 1'b1;
        end
    end

    // Line 1: Clear Direction Display with visual ASCII arrow
    reg [127:0] dir_line1;
    always @(*) begin
        case (last_gesture_code)
            3'd1: dir_line1 = "DIR: UP     [^ ]"; // UP
            3'd2: dir_line1 = "DIR: DOWN   [v ]"; // DOWN
            3'd3: dir_line1 = "DIR: LEFT   [<-]"; // LEFT
            3'd4: dir_line1 = "DIR: RIGHT  [->]"; // RIGHT
            default: dir_line1 = "GESTURE: READY  ";
        endcase
    end

    // Line 2: Decimal Counter & Live 4-Sensor Trigger Monitor
    wire [3:0] cnt_thousands = (total_gesture_counter / 1000) % 10;
    wire [3:0] cnt_hundreds  = (total_gesture_counter / 100) % 10;
    wire [3:0] cnt_tens      = (total_gesture_counter / 10) % 10;
    wire [3:0] cnt_units     = total_gesture_counter % 10;

    wire [7:0] char_c3 = "0" + cnt_thousands;
    wire [7:0] char_c2 = "0" + cnt_hundreds;
    wire [7:0] char_c1 = "0" + cnt_tens;
    wire [7:0] char_c0 = "0" + cnt_units;

    // Live debounced indicators: S4(Right), S3(opposite), S2(Left), S1(facing us)
    wire [7:0] char_s1 = cross_active_led[1] ? "1" : "0"; // S1 (South)
    wire [7:0] char_s2 = cross_active_led[2] ? "1" : "0"; // S2 (West)
    wire [7:0] char_s3 = cross_active_led[0] ? "1" : "0"; // S3 (North)
    wire [7:0] char_s4 = cross_active_led[3] ? "1" : "0"; // S4 (East)

    wire [127:0] dir_line2 = {"CNT:", char_c3, char_c2, char_c1, char_c0, " S:", char_s4, char_s3, char_s2, char_s1, " "};

    // -------------------------------------------------------------------------
    // 5. Interactive Menu Mode (Active when SW[1]=1)
    // -------------------------------------------------------------------------
    wire nav_up      = (active_gesture_valid && active_gesture_code == 3'd1);
    wire nav_down    = (active_gesture_valid && active_gesture_code == 3'd2);
    wire nav_confirm = (active_gesture_valid && active_gesture_code == 3'd4);
    wire nav_back    = (active_gesture_valid && active_gesture_code == 3'd3);

    wire [127:0] menu_line1;
    wire [127:0] menu_line2;
    wire [1:0]   cursor_pos;
    wire         in_submenu;
    wire         menu_event_pulse;
    wire [2:0]   menu_event_type;

    lcd_menu_renderer u_menu_renderer (
        .clk(CLOCK_50),
        .rst(rst),
        .select_pulse(nav_down),
        .back_pulse(nav_up),
        .confirm_pulse(nav_confirm),
        .reset_home_pulse(nav_back || rst),
        .raw_ir_sensors({cross_active_led[3], cross_active_led[0], cross_active_led[2], cross_active_led[1]}),
        .sw_manual_mode(SW[0]),
        .cursor_pos(cursor_pos),
        .in_submenu(in_submenu),
        .line1_text(menu_line1),
        .line2_text(menu_line2),
        .event_pulse(menu_event_pulse),
        .event_type(menu_event_type)
    );

    // Mux LCD output lines between Direction Visualizer (SW[1]=0) and Menu (SW[1]=1)
    wire [127:0] final_lcd_line1 = (SW[1]) ? menu_line1 : dir_line1;
    wire [127:0] final_lcd_line2 = (SW[1]) ? menu_line2 : dir_line2;

    // -------------------------------------------------------------------------
    // 6. HD44780 16x2 Character LCD Driver
    // 10 Hz periodic display refresh tick + instant update on any gesture trigger
    reg [22:0] lcd_refresh_cnt;
    wire lcd_refresh_strobe = (lcd_refresh_cnt >= 23'd5_000_000 - 1);
    always @(posedge CLOCK_50) begin
        if (rst || lcd_refresh_strobe) lcd_refresh_cnt <= 23'd0;
        else lcd_refresh_cnt <= lcd_refresh_cnt + 1'b1;
    end

    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk(CLOCK_50),
        .rst(rst),
        .line1_text(final_lcd_line1),
        .line2_text(final_lcd_line2),
        .refresh_strobe(lcd_refresh_strobe || active_gesture_valid),
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // -------------------------------------------------------------------------
    // 7. CP2101 USB-to-UART Telemetry Logger
    // -------------------------------------------------------------------------
    wire tick_1sec;
    periodic_timer #(
        .PERIOD(SIMULATION ? 10_000 : CLK_FREQ_HZ),
        .WIDTH(32)
    ) u_tick_1s (
        .clk(CLOCK_50),
        .rst(rst),
        .enable(1'b1),
        .tick_in(1'b1),
        .tick_out(tick_1sec),
        .count_val()
    );

    gesture_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_log (
        .clk(CLOCK_50),
        .reset_n(!rst),
        .gesture_valid(active_gesture_valid),
        .gesture_code(active_gesture_code),
        .gesture_ascii(cross_gesture_ascii),
        .gesture_counter(total_gesture_counter),
        .current_menu(cursor_pos),
        .in_submenu(in_submenu),
        .submenu_page(2'd0),
        .device_ready(1'b1),
        .i2c_error(1'b0),
        .tick_1sec(tick_1sec),
        .uart_txd(UART_TXD),
        .tx_active_led()
    );

    // Parallel broadcast to CP2101 USB module on JP5 Pin 1
    assign UART_TXD_OUT = UART_TXD;

    // -------------------------------------------------------------------------
    // 8. Visual Status LEDs
    // -------------------------------------------------------------------------
    // Green LEDs indicate active recognized direction
    assign LEDG[0]   = (last_gesture_code == 3'd1); // UP
    assign LEDG[1]   = (last_gesture_code == 3'd2); // DOWN
    assign LEDG[2]   = (last_gesture_code == 3'd3); // LEFT
    assign LEDG[3]   = (last_gesture_code == 3'd4); // RIGHT
    assign LEDG[4]   = in_submenu;
    assign LEDG[5]   = SW[1];                       // Menu Mode
    assign LEDG[6]   = SW[0];                       // Manual Mode
    assign LEDG[7]   = SW[3];                       // Y-Invert Flag
    assign LEDG[8]   = active_gesture_valid;        // Trigger strobe

    // Red LEDs show live raw debounced sensors [S4, S3, S2, S1]
    assign LEDR[0]   = cross_active_led[1]; // S1 (facing us)
    assign LEDR[1]   = cross_active_led[2]; // S2 (Left)
    assign LEDR[2]   = cross_active_led[0]; // S3 (opposite)
    assign LEDR[3]   = cross_active_led[3]; // S4 (Right)
    assign LEDR[15:4]= 12'b0;
    assign LEDR[16]  = SW[1];
    assign LEDR[17]  = SW[0];

    // -------------------------------------------------------------------------
    // 9. Seven-Segment Displays (HEX0..7)
    // -------------------------------------------------------------------------
    // HEX0: Direction Letter: U (UP), d (DOWN), L (LEFT), r (RIGHT), - (IDLE)
    reg [6:0] hex0_dir;
    always @(*) begin
        if (SW[1]) begin
            // Menu mode cursor
            case (cursor_pos)
                2'd0: hex0_dir = 7'b100_0000; // '0'
                2'd1: hex0_dir = 7'b111_1001; // '1'
                2'd2: hex0_dir = 7'b010_0100; // '2'
                default: hex0_dir = 7'b111_1111;
            endcase
        end else begin
            case (last_gesture_code)
                3'd1: hex0_dir = 7'b100_0001; // 'U'
                3'd2: hex0_dir = 7'b010_0001; // 'd'
                3'd3: hex0_dir = 7'b100_0111; // 'L'
                3'd4: hex0_dir = 7'b010_1111; // 'r'
                default: hex0_dir = 7'b011_1111; // '-'
            endcase
        end
    end
    assign HEX0 = hex0_dir;

    // HEX1..3: Gesture Counter (Units, Tens, Hundreds)
    seven_seg_dec u_hex1 (.dec_digit(cnt_units),    .blank(1'b0),                         .show_dash(1'b0), .seg_out(HEX1));
    seven_seg_dec u_hex2 (.dec_digit(cnt_tens),     .blank(total_gesture_counter < 10),   .show_dash(1'b0), .seg_out(HEX2));
    seven_seg_dec u_hex3 (.dec_digit(cnt_hundreds), .blank(total_gesture_counter < 100),  .show_dash(1'b0), .seg_out(HEX3));

    assign HEX4 = 7'b111_1111;
    assign HEX5 = 7'b111_1111;
    assign HEX6 = 7'b111_1111;
    assign HEX7 = 7'b111_1111;

    // -------------------------------------------------------------------------
    // 10. VGA Safe Tie-Off
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
