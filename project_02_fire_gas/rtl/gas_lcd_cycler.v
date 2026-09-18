//=============================================================================
// Module: gas_lcd_cycler
// Project: Project 2 / Basic #1 — Gas & Fire Sensor Readout with Threshold Alert
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Cycles through 3 status screens every 2.0 seconds:
//              Screen 0: MQ-2 Flammable Gas / Smoke Status
//              Screen 1: MQ-7 Carbon Monoxide (CO) Status
//              Screen 2: DHT11 Climate (Temperature and Humidity)
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gas_lcd_cycler #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer CYCLE_SEC   = 2,          // 2 seconds per screen
    parameter integer SIMULATION  = 0
)(
    input  wire         clk,
    input  wire         rst,

    // Status inputs
    input  wire         mq2_alert,
    input  wire         mq7_alert,
    input  wire         temp_alert,
    input  wire [7:0]   temperature_val,        // 0 to 99 °C
    input  wire [7:0]   humidity_val,           // 0 to 99 % RH

    // Formatted text lines for HD44780 controller (16 chars each)
    output reg  [127:0] line1_text,
    output reg  [127:0] line2_text,
    output reg  [1:0]   current_screen
);

    // Timing cycles for screen rotation
    localparam integer SCREEN_CYCLES = (SIMULATION) ? 2_000 : (CLK_FREQ_HZ * CYCLE_SEC);

    reg [$clog2(SCREEN_CYCLES):0] screen_timer;
    reg [1:0] screen_idx;

    always @(posedge clk) begin
        if (rst) begin
            screen_timer   <= 0;
            screen_idx     <= 2'd0;
            current_screen <= 2'd0;
        end else begin
            if (screen_timer >= SCREEN_CYCLES - 1) begin
                screen_timer <= 0;
                if (screen_idx >= 2'd2)
                    screen_idx <= 2'd0;
                else
                    screen_idx <= screen_idx + 1'b1;
            end else begin
                screen_timer <= screen_timer + 1'b1;
            end
            current_screen <= screen_idx;
        end
    end

    // ASCII Conversion for Temperature and Humidity
    wire [3:0] temp_tens = temperature_val / 10;
    wire [3:0] temp_ones = temperature_val % 10;
    wire [3:0] hum_tens  = humidity_val / 10;
    wire [3:0] hum_ones  = humidity_val % 10;

    wire [7:0] ascii_temp_tens = 8'h30 + temp_tens;
    wire [7:0] ascii_temp_ones = 8'h30 + temp_ones;
    wire [7:0] ascii_hum_tens  = 8'h30 + hum_tens;
    wire [7:0] ascii_hum_ones  = 8'h30 + hum_ones;

    always @(*) begin
        case (screen_idx)
            2'd0: begin
                // Screen 0: MQ2 Flammable Gas
                line1_text = "MQ2 Gas Status: ";
                if (mq2_alert)
                    line2_text = "ALERT! HAZARD   ";
                else
                    line2_text = "Normal (Clean)  ";
            end

            2'd1: begin
                // Screen 1: MQ7 Carbon Monoxide
                line1_text = "MQ7 CO Status:  ";
                if (mq7_alert)
                    line2_text = "ALERT! HIGH CO  ";
                else
                    line2_text = "Normal (Clean)  ";
            end

            2'd2: begin
                // Screen 2: DHT11 Climate Readout
                if (temp_alert)
                    line1_text = "CLIMATE: HIGH T!";
                else
                    line1_text = "DHT11 Climate:  ";

                line2_text = {
                    "Temp:", ascii_temp_tens, ascii_temp_ones, "C H:",
                    ascii_hum_tens, ascii_hum_ones, "%   "
                };
            end

            default: begin
                line1_text = "System Monitor  ";
                line2_text = "Ready           ";
            end
        endcase
    end

endmodule
