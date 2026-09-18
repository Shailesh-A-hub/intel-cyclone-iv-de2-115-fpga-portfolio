//=============================================================================
// Module: lcd_menu_renderer
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Manages a 3-item navigable menu on the 16x2 HD44780 character LCD:
//              Item 0: "System Status"
//              Item 1: "Sensor Values"
//              Item 2: "Settings"
//              - Displays '>' indicator on currently highlighted line.
//              - Select pulse advances cursor down (wraps 0 -> 1 -> 2 -> 0).
//              - Back pulse retreats cursor up (wraps 0 -> 2 -> 1 -> 0).
//              - Confirm pulse enters the selected item's sub-screen:
//                  Sub 0: "[System Status] / FPGA State: OK"
//                  Sub 1: "Live IR Sensors / L:x C:x R:x K:x"
//                  Sub 2: "Mode Setting    / Mode: Gesture/Manual"
//              - btn_reset_home (KEY[0]) exits back to Root Menu.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module lcd_menu_renderer (
    input  wire        clk,
    input  wire        rst,

    // Navigation triggers
    input  wire        select_pulse,       // Move cursor down
    input  wire        back_pulse,         // Move cursor up
    input  wire        confirm_pulse,      // Open submenu
    input  wire        reset_home_pulse,   // Return to root home menu

    // Live sensor and system inputs for submenus
    input  wire [3:0]  raw_ir_sensors,     // [3]=Confirm, [2]=Right, [1]=Center, [0]=Left
    input  wire        sw_manual_mode,     // Mode setting

    // Status outputs to LCD and UART
    output reg  [1:0]  cursor_pos,         // 0 to 2
    output reg         in_submenu,
    output reg  [127:0] line1_text,
    output reg  [127:0] line2_text,

    // Event notification for UART telemetry logger
    output reg         event_pulse,
    output reg  [2:0]  event_type          // 1: Cursor changed, 2: Confirmed, 3: Home returned
);

    // Menu Navigation Register
    always @(posedge clk) begin
        if (rst) begin
            cursor_pos  <= 2'd0;
            in_submenu  <= 1'b0;
            event_pulse <= 1'b0;
            event_type  <= 3'd0;
        end else begin
            event_pulse <= 1'b0;

            if (reset_home_pulse) begin
                in_submenu  <= 1'b0;
                cursor_pos  <= 2'd0;
                event_pulse <= 1'b1;
                event_type  <= 3'd3; // Return Home
            end else if (!in_submenu) begin
                // In Root Menu
                if (confirm_pulse) begin
                    in_submenu  <= 1'b1;
                    event_pulse <= 1'b1;
                    event_type  <= 3'd2; // Confirm / Enter Submenu
                end else if (select_pulse) begin
                    if (cursor_pos >= 2'd2) cursor_pos <= 2'd0;
                    else cursor_pos <= cursor_pos + 1'b1;
                    event_pulse <= 1'b1;
                    event_type  <= 3'd1; // Cursor Down
                end else if (back_pulse) begin
                    if (cursor_pos == 2'd0) cursor_pos <= 2'd2;
                    else cursor_pos <= cursor_pos - 1'b1;
                    event_pulse <= 1'b1;
                    event_type  <= 3'd1; // Cursor Up
                end
            end else begin
                // In Submenu: Confirm or select/back can return or cycle
                if (confirm_pulse || select_pulse || back_pulse) begin
                    in_submenu  <= 1'b0; // Any action returns to root
                    event_pulse <= 1'b1;
                    event_type  <= 3'd3;
                end
            end
        end
    end

    // Live ASCII representations of sensor bits
    wire [7:0] char_l = raw_ir_sensors[0] ? "1" : "0";
    wire [7:0] char_c = raw_ir_sensors[1] ? "1" : "0";
    wire [7:0] char_r = raw_ir_sensors[2] ? "1" : "0";
    wire [7:0] char_k = raw_ir_sensors[3] ? "1" : "0";

    // Text Renderer
    always @(*) begin
        if (!in_submenu) begin
            // Render Root Menu with dynamic '>' cursor
            case (cursor_pos)
                2'd0: begin
                    line1_text = "> System Status ";
                    line2_text = "  Sensor Values ";
                end

                2'd1: begin
                    line1_text = "  System Status ";
                    line2_text = "> Sensor Values ";
                end

                2'd2: begin
                    line1_text = "> Settings      ";
                    line2_text = " (Press K=Enter)";
                end

                default: begin
                    line1_text = "> System Status ";
                    line2_text = "  Sensor Values ";
                end
            endcase
        end else begin
            // Render Submenus
            case (cursor_pos)
                2'd0: begin
                    // Submenu 0: System Status
                    line1_text = "[System Status] ";
                    line2_text = "FPGA State: OK  ";
                end

                2'd1: begin
                    // Submenu 1: Sensor Values Readout
                    line1_text = "IR Sensor Live: ";
                    line2_text = {"L:", char_l, " C:", char_c, " R:", char_r, " K:", char_k, " "};
                end

                2'd2: begin
                    // Submenu 2: Settings / Mode
                    line1_text = "Settings / Mode:";
                    if (sw_manual_mode)
                        line2_text = "Mode: Manual KEY";
                    else
                        line2_text = "Mode: IR Gesture";
                end

                default: begin
                    line1_text = "Submenu View    ";
                    line2_text = "Ready           ";
                end
            endcase
        end
    end

endmodule
