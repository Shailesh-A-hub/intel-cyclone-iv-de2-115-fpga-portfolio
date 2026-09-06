// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   adaptive_threshold_engine.v
// Description: Dynamic soil moisture threshold calculation engine.
//              Adapts irrigation threshold based on ambient temperature and
//              humidity to compensate for plant evapotranspiration.
//              Provides dual-threshold hysteresis bounds (turn-on vs turn-off).
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module adaptive_threshold_engine (
    input  wire        clk,
    input  wire        rst_n,

    // Environmental Sensor Inputs
    input  wire [6:0]  temp_celsius,      // 0 to 99 °C
    input  wire [6:0]  humidity_percent,  // 0 to 99 % RH

    // User / System Configuration
    input  wire [6:0]  base_threshold,    // Default nominal threshold (e.g. 40%)
    input  wire [4:0]  hysteresis_band,   // Default nominal hysteresis (e.g. 5%)

    // Adaptive Threshold Outputs
    output reg  [6:0]  adaptive_threshold,// Clamped to [25%, 75%]
    output reg  [6:0]  turn_on_threshold, // Moisture < turn_on -> Start pump
    output reg  [6:0]  turn_off_threshold,// Moisture >= turn_off -> Stop pump
    output reg  [4:0]  temp_adjustment,
    output reg  [4:0]  hum_adjustment,
    output reg         boost_active
);

    // ------------------------------------------------------------------------
    // Combinational Adjustment Derivation
    // ------------------------------------------------------------------------
    // Temperature Adjustment:
    // If Temp > 25°C: Add (Temp - 25), capped at +15%
    wire [4:0] c_temp_adj = (temp_celsius > 7'd25) ?
                            ((temp_celsius - 7'd25 > 7'd15) ? 5'd15 : (temp_celsius[4:0] - 5'd25)) : 5'd0;

    // Humidity Adjustment:
    // If Humidity < 50%: Add (50 - Hum)/2, capped at +10%
    wire [6:0] hum_deficit = (humidity_percent < 7'd50) ? (7'd50 - humidity_percent) : 7'd0;
    wire [4:0] c_hum_adj  = (hum_deficit[5:1] > 5'd10) ? 5'd10 : hum_deficit[4:1];

    // Unclamped Composite Target
    wire [7:0] c_target = {1'b0, base_threshold} + {3'b000, c_temp_adj} + {3'b000, c_hum_adj};

    // Clamping to safe operational limits [25%, 75%]
    wire [6:0] c_clamped = (c_target < 8'd25) ? 7'd25 :
                           (c_target > 8'd75) ? 7'd75 : c_target[6:0];

    // Dual Threshold Hysteresis Bounds
    wire [6:0] c_turn_on  = (c_clamped <= {2'b00, hysteresis_band} + 7'd5) ? 7'd5 :
                            (c_clamped - {2'b00, hysteresis_band});
    wire [6:0] c_turn_off = (c_clamped + {2'b00, hysteresis_band} >= 7'd95) ? 7'd95 :
                            (c_clamped + {2'b00, hysteresis_band});

    // ------------------------------------------------------------------------
    // Registered Pipeline Output
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adaptive_threshold <= 7'd40;
            turn_on_threshold  <= 7'd35;
            turn_off_threshold <= 7'd45;
            temp_adjustment    <= 5'd0;
            hum_adjustment     <= 5'd0;
            boost_active       <= 1'b0;
        end else begin
            adaptive_threshold <= c_clamped;
            turn_on_threshold  <= c_turn_on;
            turn_off_threshold <= c_turn_off;
            temp_adjustment    <= c_temp_adj;
            hum_adjustment     <= c_hum_adj;
            boost_active       <= (c_temp_adj > 0 || c_hum_adj > 0);
        end
    end

endmodule
