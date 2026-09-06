//=============================================================================
// Module: menu_fsm
// Description: Hierarchical finite state machine for multi-tier gesture navigation.
//              Manages Main Menu (STATUS, SETTINGS, SENSORS, ABOUT) and submenus.
//              Provides user setting adjustment (LCD backlight, audio beeper,
//              inactivity timeout), cursor wrap-around, and auto-exit timeouts.
//              Formats real-time 16x2 ASCII string buffers for the LCD controller.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module menu_fsm #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer SIMULATION  = 0
)(
    input  wire        clk,
    input  wire        reset_n,

    // Gesture input events from gesture_decoder
    input  wire        gesture_valid,
    input  wire [2:0]  gesture_code,
    input  wire [31:0] last_gesture_ascii,

    // Live sensor values for SENSORS page
    input  wire [7:0]  raw_u,
    input  wire [7:0]  raw_d,
    input  wire [7:0]  raw_l,
    input  wire [7:0]  raw_r,
    input  wire [15:0] gesture_counter,

    // External timing ticks
    input  wire        tick_1sec,

    // Formatted 16-character ASCII LCD buffers
    output reg  [127:0] lcd_line1,
    output reg  [127:0] lcd_line2,

    // Menu state indicators
    output reg  [1:0]  current_menu,       // 0: STATUS, 1: SETTINGS, 2: SENSORS, 3: ABOUT
    output reg         in_submenu,         // 0: Main Menu, 1: Submenu
    output reg  [1:0]  submenu_page,
    output reg         menu_event_pulse,

    // User configurable system settings
    output reg  [1:0]  setting_backlight,  // 0: Low, 1: Med, 2: High
    output reg         setting_beep_en,    // 0: Mute, 1: Enabled
    output reg  [1:0]  setting_timeout_sel // 0: 10s, 1: 20s, 2: 30s
);

    // Gesture Encodings
    localparam [2:0]
        GESTURE_NONE    = 3'd0,
        GESTURE_UP      = 3'd1,
        GESTURE_DOWN    = 3'd2,
        GESTURE_LEFT    = 3'd3,
        GESTURE_RIGHT   = 3'd4,
        GESTURE_NEAR    = 3'd5,
        GESTURE_FAR     = 3'd6;

    // Menu IDs
    localparam [1:0]
        MENU_STATUS   = 2'd0,
        MENU_SETTINGS = 2'd1,
        MENU_SENSORS  = 2'd2,
        MENU_ABOUT    = 2'd3;

    // Inactivity timeout limit (seconds)
    reg [5:0] timeout_sec_limit;
    reg [5:0] inactivity_counter;

    // Live system uptime counter
    reg [15:0] uptime_seconds;

    always @(*) begin
        case (setting_timeout_sel)
            2'd0: timeout_sec_limit = 6'd10;
            2'd1: timeout_sec_limit = 6'd20;
            2'd2: timeout_sec_limit = 6'd30;
            default: timeout_sec_limit = 6'd10;
        endcase
    end

    // Hex to ASCII converter function
    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            if (nibble < 4'd10)
                hex_char = 8'h30 + nibble;
            else
                hex_char = 8'h41 + (nibble - 4'd10);
        end
    endfunction

    // Decimal to ASCII converter function
    function [7:0] dec_char;
        input [3:0] d;
        begin
            dec_char = 8'h30 + d;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Main Menu & Submenu Navigation FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset_n) begin
            current_menu        <= MENU_STATUS;
            in_submenu          <= 1'b0;
            submenu_page        <= 2'd0;
            menu_event_pulse    <= 1'b0;
            setting_backlight   <= 2'd2; // Default High
            setting_beep_en     <= 1'b1; // Default ON
            setting_timeout_sel <= 2'd0; // Default 10s
            inactivity_counter  <= 6'd0;
            uptime_seconds      <= 16'd0;
        end else begin
            menu_event_pulse <= 1'b0; // Default pulse

            if (tick_1sec) begin
                uptime_seconds <= uptime_seconds + 1'b1;
                if (in_submenu) begin
                    if (inactivity_counter >= timeout_sec_limit) begin
                        // Inactivity timeout triggered: auto-exit back to main menu
                        in_submenu         <= 1'b0;
                        submenu_page       <= 2'd0;
                        inactivity_counter <= 6'd0;
                        menu_event_pulse   <= 1'b1;
                    end else begin
                        inactivity_counter <= inactivity_counter + 1'b1;
                    end
                end
            end

            // Process Gesture Navigation
            if (gesture_valid) begin
                inactivity_counter <= 6'd0; // Reset inactivity timer on any user motion

                if (!in_submenu) begin
                    // ---------------------------------------------------------
                    // NAVIGATION IN MAIN MENU
                    // ---------------------------------------------------------
                    case (gesture_code)
                        GESTURE_UP: begin
                            current_menu     <= current_menu - 1'b1;
                            menu_event_pulse <= 1'b1;
                        end

                        GESTURE_DOWN: begin
                            current_menu     <= current_menu + 1'b1;
                            menu_event_pulse <= 1'b1;
                        end

                        GESTURE_RIGHT, GESTURE_NEAR: begin
                            in_submenu       <= 1'b1;
                            submenu_page     <= 2'd0;
                            menu_event_pulse <= 1'b1;
                        end

                        default: ; // Left and Far ignored at top level
                    endcase
                end else begin
                    // ---------------------------------------------------------
                    // NAVIGATION INSIDE SUBMENU
                    // ---------------------------------------------------------
                    case (gesture_code)
                        GESTURE_LEFT, GESTURE_FAR: begin
                            // Return to Main Menu
                            in_submenu       <= 1'b0;
                            submenu_page     <= 2'd0;
                            menu_event_pulse <= 1'b1;
                        end

                        GESTURE_UP: begin
                            // Page up within submenu
                            submenu_page     <= submenu_page - 1'b1;
                            menu_event_pulse <= 1'b1;
                        end

                        GESTURE_DOWN: begin
                            // Page down within submenu
                            submenu_page     <= submenu_page + 1'b1;
                            menu_event_pulse <= 1'b1;
                        end

                        GESTURE_RIGHT, GESTURE_NEAR: begin
                            // Inside submenu: Action / Parameter Toggle
                            menu_event_pulse <= 1'b1;
                            case (current_menu)
                                MENU_SETTINGS: begin
                                    case (submenu_page)
                                        2'd0: begin // Cycle Backlight
                                            setting_backlight <= (setting_backlight == 2'd2) ? 2'd0 : (setting_backlight + 1'b1);
                                        end
                                        2'd1: begin // Toggle Beep
                                            setting_beep_en <= !setting_beep_en;
                                        end
                                        2'd2: begin // Cycle Timeout
                                            setting_timeout_sel <= (setting_timeout_sel == 2'd2) ? 2'd0 : (setting_timeout_sel + 1'b1);
                                        end
                                        default: ;
                                    endcase
                                end
                                default: ; // In other menus, right acts as page forward
                            endcase
                        end

                        default: ;
                    endcase
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // LCD 16x2 Text Formatting Pipeline
    // -------------------------------------------------------------------------
    always @(*) begin
        if (!in_submenu) begin
            // ------------------ MAIN MENU SCREENS ------------------
            case (current_menu)
                MENU_STATUS: begin
                    lcd_line1 = ">MAIN: 1.STATUS ";
                    lcd_line2 = "[R/NEAR] ENTER  ";
                end
                MENU_SETTINGS: begin
                    lcd_line1 = ">MAIN: 2.SETTING";
                    lcd_line2 = "[R/NEAR] ENTER  ";
                end
                MENU_SENSORS: begin
                    lcd_line1 = ">MAIN: 3.SENSORS";
                    lcd_line2 = "[R/NEAR] ENTER  ";
                end
                MENU_ABOUT: begin
                    lcd_line1 = ">MAIN: 4.ABOUT  ";
                    lcd_line2 = "[R/NEAR] ENTER  ";
                end
                default: begin
                    lcd_line1 = "MAIN MENU       ";
                    lcd_line2 = "SELECT ITEM     ";
                end
            endcase
        end else begin
            // ------------------ SUBMENU SCREENS ------------------
            case (current_menu)
                // 1. STATUS SUBMENU
                MENU_STATUS: begin
                    case (submenu_page[0])
                        1'b0: begin
                            lcd_line1 = "STATUS: UPTIME  ";
                            lcd_line2 = {"SEC:", dec_char((uptime_seconds/10000)%10),
                                                dec_char((uptime_seconds/1000)%10),
                                                dec_char((uptime_seconds/100)%10),
                                                dec_char((uptime_seconds/10)%10),
                                                dec_char(uptime_seconds%10),
                                                "s [LEFT]BACK"};
                        end
                        1'b1: begin
                            lcd_line1 = "STATUS: SYSTEM  ";
                            lcd_line2 = "CLK:50MHz OK:YES";
                        end
                    endcase
                end

                // 2. SETTINGS SUBMENU
                MENU_SETTINGS: begin
                    case (submenu_page)
                        2'd0: begin
                            lcd_line1 = "SET: BACKLIGHT  ";
                            case (setting_backlight)
                                2'd0: lcd_line2 = "LEVEL: LOW  [R+]";
                                2'd1: lcd_line2 = "LEVEL: MED  [R+]";
                                2'd2: lcd_line2 = "LEVEL: HIGH [R+]";
                                default: lcd_line2 = "LEVEL: HIGH [R+]";
                            endcase
                        end
                        2'd1: begin
                            lcd_line1 = "SET: AUDIO BEEP ";
                            if (setting_beep_en)
                                lcd_line2 = "BEEP: ON    [R+]";
                            else
                                lcd_line2 = "BEEP: MUTED [R+]";
                        end
                        2'd2, 2'd3: begin
                            lcd_line1 = "SET: TIMEOUT    ";
                            case (setting_timeout_sel)
                                2'd0: lcd_line2 = "TIME: 10s   [R+]";
                                2'd1: lcd_line2 = "TIME: 20s   [R+]";
                                2'd2: lcd_line2 = "TIME: 30s   [R+]";
                                default: lcd_line2 = "TIME: 10s   [R+]";
                            endcase
                        end
                    endcase
                end

                // 3. SENSORS SUBMENU
                MENU_SENSORS: begin
                    case (submenu_page[0])
                        1'b0: begin
                            lcd_line1 = {"U:", hex_char(raw_u[7:4]), hex_char(raw_u[3:0]), " ",
                                         "D:", hex_char(raw_d[7:4]), hex_char(raw_d[3:0]), " ",
                                         "L:", hex_char(raw_l[7:4]), hex_char(raw_l[3:0]), " "};
                            lcd_line2 = {"R:", hex_char(raw_r[7:4]), hex_char(raw_r[3:0]), "  ",
                                         "[LEFT] TO EXIT "};
                        end
                        1'b1: begin
                            lcd_line1 = {"LAST:", last_gesture_ascii, "       "};
                            lcd_line2 = {"COUNT:", dec_char((gesture_counter/10000)%10),
                                                  dec_char((gesture_counter/1000)%10),
                                                  dec_char((gesture_counter/100)%10),
                                                  dec_char((gesture_counter/10)%10),
                                                  dec_char(gesture_counter%10),
                                                  "     "};
                        end
                    endcase
                end

                // 4. ABOUT SUBMENU
                MENU_ABOUT: begin
                    case (submenu_page[0])
                        1'b0: begin
                            lcd_line1 = "DE2-115 FPGA    ";
                            lcd_line2 = "PROJ4:GESTURE UI";
                        end
                        1'b1: begin
                            lcd_line1 = "CYCLONE IV E    ";
                            lcd_line2 = "EP4CE115F29C7   ";
                        end
                    endcase
                end
            endcase
        end
    end

endmodule
