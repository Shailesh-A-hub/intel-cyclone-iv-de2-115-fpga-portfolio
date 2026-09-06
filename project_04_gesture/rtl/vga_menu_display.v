//=============================================================================
// Module: vga_menu_display
// Description: 640x480 @ 60Hz graphical menu renderer for the Gesture Menu System.
//              Generates high-contrast color cards for Main Menu navigation,
//              interactive cursor highlight bounding boxes, live dynamic bar
//              graphs for optical photodiode signals (U, D, L, R), status badges,
//              and real-time gesture telemetry.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module vga_menu_display (
    input  wire        clk_50,             // 50 MHz input
    input  wire        reset_n,

    // Menu state from menu_fsm
    input  wire [1:0]  current_menu,       // 0: STATUS, 1: SETTINGS, 2: SENSORS, 3: ABOUT
    input  wire        in_submenu,
    input  wire [1:0]  submenu_page,
    input  wire [1:0]  setting_backlight,
    input  wire        setting_beep_en,
    input  wire [1:0]  setting_timeout_sel,

    // Live gesture telemetry
    input  wire [2:0]  last_gesture_code,
    input  wire [15:0] gesture_counter,
    input  wire [7:0]  raw_u,
    input  wire [7:0]  raw_d,
    input  wire [7:0]  raw_l,
    input  wire [7:0]  raw_r,

    // DE2-115 ADV7123 VGA DAC Interface
    output wire        vga_clk,            // 25.175 MHz pixel clock
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output reg  [7:0]  vga_r,
    output reg  [7:0]  vga_g,
    output reg  [7:0]  vga_b
);

    // Instantiate VGA Timing Controller
    wire [9:0] pixel_x, pixel_y;
    wire       active_video;

    vga_timing_controller u_vga_timing (
        .clk_50mhz(clk_50),
        .rst(!reset_n),
        .vga_clk(vga_clk),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_blank_n(vga_blank_n),
        .vga_sync_n(vga_sync_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .active_area(active_video),
        .pixel_tick()
    );

    // Color Palette Definitions (24-bit RGB)
    localparam [23:0]
        COLOR_BG        = 24'h0B0F19, // Deep space dark navy
        COLOR_HEADER    = 24'h162035, // Slate navy
        COLOR_BORDER    = 24'h334E68, // Border grey-blue
        COLOR_CARD_IDLE = 24'h102A43, // Inactive card background
        COLOR_CARD_ACT  = 24'h006494, // Active card background
        COLOR_HIGHLIGHT = 24'h00F0FF, // Cyan neon highlight
        COLOR_GOLD      = 24'hFFC72C, // Gold accent
        COLOR_TEXT_W    = 24'hF0F4F8, // Off-white
        COLOR_RED       = 24'hE63946, // Hazard / Red
        COLOR_GREEN     = 24'h06D6A0, // Success / Green
        COLOR_PURPLE    = 24'h7209B7, // Accent purple
        COLOR_ORANGE    = 24'hFB8500; // Orange

    // Scaled photodiode heights (0 to 128 pixels tall)
    wire [9:0] bar_h_u = {2'b00, raw_u[7:1]};
    wire [9:0] bar_h_d = {2'b00, raw_d[7:1]};
    wire [9:0] bar_h_l = {2'b00, raw_l[7:1]};
    wire [9:0] bar_h_r = {2'b00, raw_r[7:1]};

    // Card boundary flags
    wire in_card0 = (pixel_x >= 40 && pixel_x <= 210 && pixel_y >= 80  && pixel_y <= 140);
    wire in_card1 = (pixel_x >= 40 && pixel_x <= 210 && pixel_y >= 160 && pixel_y <= 220);
    wire in_card2 = (pixel_x >= 40 && pixel_x <= 210 && pixel_y >= 240 && pixel_y <= 300);
    wire in_card3 = (pixel_x >= 40 && pixel_x <= 210 && pixel_y >= 320 && pixel_y <= 380);

    // Frame bounding box flags
    wire is_card0_border = in_card0 && (pixel_x == 40 || pixel_x == 210 || pixel_y == 80  || pixel_y == 140);
    wire is_card1_border = in_card1 && (pixel_x == 40 || pixel_x == 210 || pixel_y == 160 || pixel_y == 220);
    wire is_card2_border = in_card2 && (pixel_x == 40 || pixel_x == 210 || pixel_y == 240 || pixel_y == 300);
    wire is_card3_border = in_card3 && (pixel_x == 40 || pixel_x == 210 || pixel_y == 320 || pixel_y == 380);

    // Details viewport on the right
    wire in_viewport = (pixel_x >= 240 && pixel_x <= 600 && pixel_y >= 80 && pixel_y <= 380);
    wire is_viewport_border = in_viewport && (pixel_x == 240 || pixel_x == 600 || pixel_y == 80 || pixel_y == 380);

    // Top Header & Bottom Footer
    wire in_header = (pixel_y <= 50);
    wire in_footer = (pixel_y >= 420 && pixel_y <= 470 && pixel_x >= 40 && pixel_x <= 600);

    // Color Generation Pipeline
    reg [23:0] rgb_next;

    always @(*) begin
        if (!active_video) begin
            rgb_next = 24'h000000;
        end else if (in_header) begin
            if (pixel_y == 50)
                rgb_next = COLOR_HIGHLIGHT;
            else if (pixel_x >= 50 && pixel_x <= 590 && pixel_y >= 15 && pixel_y <= 35)
                rgb_next = COLOR_CARD_ACT;
            else
                rgb_next = COLOR_HEADER;
        end else if (in_footer) begin
            // Footer status banner
            if (pixel_x == 40 || pixel_x == 600 || pixel_y == 420 || pixel_y == 470)
                rgb_next = COLOR_BORDER;
            else if (pixel_x >= 60 && pixel_x <= 160 && pixel_y >= 430 && pixel_y <= 460) begin
                // Last gesture indicator badge
                case (last_gesture_code)
                    3'd1: rgb_next = COLOR_GREEN;     // UP
                    3'd2: rgb_next = COLOR_HIGHLIGHT; // DOWN
                    3'd3: rgb_next = COLOR_GOLD;      // LEFT
                    3'd4: rgb_next = COLOR_ORANGE;    // RIGHT
                    3'd5: rgb_next = COLOR_PURPLE;    // NEAR
                    3'd6: rgb_next = COLOR_RED;       // FAR
                    default: rgb_next = COLOR_BORDER;
                endcase
            end else begin
                rgb_next = COLOR_HEADER;
            end
        end else if (is_card0_border || is_card1_border || is_card2_border || is_card3_border) begin
            // Highlight active card border with cyan neon, inactive with dark border
            if ((current_menu == 2'd0 && is_card0_border) ||
                (current_menu == 2'd1 && is_card1_border) ||
                (current_menu == 2'd2 && is_card2_border) ||
                (current_menu == 2'd3 && is_card3_border))
                rgb_next = COLOR_HIGHLIGHT;
            else
                rgb_next = COLOR_BORDER;
        end else if (in_card0) begin
            rgb_next = (current_menu == 2'd0) ? COLOR_CARD_ACT : COLOR_CARD_IDLE;
        end else if (in_card1) begin
            rgb_next = (current_menu == 2'd1) ? COLOR_CARD_ACT : COLOR_CARD_IDLE;
        end else if (in_card2) begin
            rgb_next = (current_menu == 2'd2) ? COLOR_CARD_ACT : COLOR_CARD_IDLE;
        end else if (in_card3) begin
            rgb_next = (current_menu == 2'd3) ? COLOR_CARD_ACT : COLOR_CARD_IDLE;
        end else if (is_viewport_border) begin
            rgb_next = in_submenu ? COLOR_GOLD : COLOR_BORDER;
        end else if (in_viewport) begin
            // Render viewport contents based on active menu
            case (current_menu)
                2'd2: begin // SENSORS MENU: Dynamic 4-Bar Graph
                    // Base line for bars at Y = 340
                    if (pixel_x >= 280 && pixel_x <= 330 && pixel_y <= 340 && pixel_y >= (340 - bar_h_u))
                        rgb_next = COLOR_GREEN;     // Up Bar
                    else if (pixel_x >= 360 && pixel_x <= 410 && pixel_y <= 340 && pixel_y >= (340 - bar_h_d))
                        rgb_next = COLOR_HIGHLIGHT; // Down Bar
                    else if (pixel_x >= 440 && pixel_x <= 490 && pixel_y <= 340 && pixel_y >= (340 - bar_h_l))
                        rgb_next = COLOR_GOLD;      // Left Bar
                    else if (pixel_x >= 520 && pixel_x <= 570 && pixel_y <= 340 && pixel_y >= (340 - bar_h_r))
                        rgb_next = COLOR_ORANGE;    // Right Bar
                    else if (pixel_y == 341 || pixel_y == 342)
                        rgb_next = COLOR_TEXT_W;    // Baseline axis
                    else
                        rgb_next = 24'h0E141B;      // Viewport dark background
                end

                2'd1: begin // SETTINGS MENU: Sliders / Toggles
                    // Backlight indicator block
                    if (pixel_y >= 120 && pixel_y <= 150 && pixel_x >= 280 && pixel_x <= (280 + {5'd0, setting_backlight, 6'd0}))
                        rgb_next = COLOR_HIGHLIGHT;
                    // Audio beep toggle box
                    else if (pixel_y >= 190 && pixel_y <= 220 && pixel_x >= 280 && pixel_x <= 380)
                        rgb_next = setting_beep_en ? COLOR_GREEN : COLOR_RED;
                    // Timeout indicator box
                    else if (pixel_y >= 260 && pixel_y <= 290 && pixel_x >= 280 && pixel_x <= (280 + {4'd0, setting_timeout_sel, 6'd0}))
                        rgb_next = COLOR_GOLD;
                    else
                        rgb_next = 24'h0E141B;
                end

                2'd0: begin // STATUS MENU
                    // Status heartbeat indicator badge
                    if (pixel_y >= 120 && pixel_y <= 160 && pixel_x >= 280 && pixel_x <= 420)
                        rgb_next = COLOR_CARD_ACT;
                    else if (pixel_y >= 200 && pixel_y <= 240 && pixel_x >= 280 && pixel_x <= 540)
                        rgb_next = COLOR_CARD_IDLE;
                    else
                        rgb_next = 24'h0E141B;
                end

                2'd3: begin // ABOUT MENU
                    // Decorative chip emblem
                    if (pixel_y >= 150 && pixel_y <= 270 && pixel_x >= 370 && pixel_x <= 490) begin
                        if (pixel_x == 370 || pixel_x == 490 || pixel_y == 150 || pixel_y == 270)
                            rgb_next = COLOR_GOLD;
                        else
                            rgb_next = COLOR_CARD_ACT;
                    end else
                        rgb_next = 24'h0E141B;
                end
            endcase
        end else begin
            rgb_next = COLOR_BG;
        end
    end

    // Registered DAC outputs clocked on pixel clock
    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else begin
            vga_r <= rgb_next[23:16];
            vga_g <= rgb_next[15:8];
            vga_b <= rgb_next[7:0];
        end
    end

endmodule
