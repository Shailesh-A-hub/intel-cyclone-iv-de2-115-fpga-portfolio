//=============================================================================
// Module: energy_decision_engine
// Project: Project 1 - Multi-Zone Occupancy & Energy-Saving Engine
// Description: Multi-zone aggregator and decision engine. Evaluates aggregate
//              zone status and ambient illumination to control lighting relays,
//              proportional HVAC staging, and variable ventilation fan speeds.
//              Accumulates real-time energy savings in Watt-hours.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module energy_decision_engine (
    input  wire        clk,
    input  wire        rst,
    // Zone Status Inputs
    input  wire [3:0]  zone_occupied,       // 1 = Zone is occupied or timing out
    input  wire [3:0]  zone_light_req,      // Zone lighting demand
    input  wire [3:0]  zone_hvac_req,       // Zone climate demand
    input  wire        ambient_dark,        // 1 = Night/Dark (lights allowed), 0 = Bright daylight
    input  wire        tick_1s,             // 1-second pulse for energy accumulation
    // Output Actuation Controls
    output reg  [3:0]  zone_lights,         // Per-zone lighting control signals
    output wire        main_lighting_relay, // Main lighting circuit breaker relay
    output reg         hvac_relay,          // Master HVAC contactor
    output reg  [1:0]  hvac_level,          // 00=OFF, 01=LOW, 10=MED, 11=HIGH
    output reg         fan_relay,           // Ventilation fan relay
    output reg  [7:0]  fan_pwm_duty,        // Ventilation speed control (0-255)
    output reg  [2:0]  active_zone_count,   // Current number of occupied zones (0 - 4)
    output reg  [15:0] energy_saved_wh,     // Accumulated saved energy (Watt-hours)
    output reg         counter_overflow     // Set if energy accumulator reaches max (0xFFFF)
);

    assign main_lighting_relay = (zone_lights != 4'b0000);

    // Sum active zones
    wire [2:0] total_active = zone_occupied[0] + zone_occupied[1] + 
                              zone_occupied[2] + zone_occupied[3];

    always @(posedge clk) begin
        if (rst) begin
            zone_lights       <= 4'b0000;
            hvac_relay        <= 1'b0;
            hvac_level        <= 2'b00;
            fan_relay         <= 1'b0;
            fan_pwm_duty      <= 8'd0;
            active_zone_count <= 3'd0;
        end else begin
            active_zone_count <= total_active;

            // Lighting policy: Zone lights turn ON only if occupied AND ambient is dark
            zone_lights[0] <= zone_light_req[0] & ambient_dark;
            zone_lights[1] <= zone_light_req[1] & ambient_dark;
            zone_lights[2] <= zone_light_req[2] & ambient_dark;
            zone_lights[3] <= zone_light_req[3] & ambient_dark;

            // Proportional HVAC & Fan Control Policy
            case (total_active)
                3'd0: begin
                    // Zero occupancy: Complete shutdown
                    hvac_relay   <= 1'b0;
                    hvac_level   <= 2'b00; // OFF
                    fan_relay    <= 1'b0;
                    fan_pwm_duty <= 8'd0;  // 0%
                end

                3'd1: begin
                    // Single zone: Low climate staging
                    hvac_relay   <= 1'b1;
                    hvac_level   <= 2'b01; // LOW
                    fan_relay    <= 1'b1;
                    fan_pwm_duty <= 8'd102; // ~40% duty cycle
                end

                3'd2, 3'd3: begin
                    // 2 or 3 zones: Medium staging
                    hvac_relay   <= 1'b1;
                    hvac_level   <= 2'b10; // MED
                    fan_relay    <= 1'b1;
                    fan_pwm_duty <= 8'd178; // ~70% duty cycle
                end

                3'd4: begin
                    // Full occupancy: Maximum climate staging
                    hvac_relay   <= 1'b1;
                    hvac_level   <= 2'b11; // HIGH
                    fan_relay    <= 1'b1;
                    fan_pwm_duty <= 8'd255; // 100% duty cycle
                end

                default: begin
                    hvac_relay   <= 1'b0;
                    hvac_level   <= 2'b00;
                    fan_relay    <= 1'b0;
                    fan_pwm_duty <= 8'd0;
                end
            endcase
        end
    end

    // Energy Savings Calculation:
    // Baseline continuous power = 2200 W (4x100W lights + 1600W HVAC + 200W fan)
    // Instantaneous power saved = Baseline - Current Active Consumption
    // Watt-seconds accumulator increments every second; wraps every 3600 W*s = 1 Watt-hour.
    reg [15:0] inst_power_saved;
    always @(*) begin
        case (total_active)
            3'd0: inst_power_saved = 16'd2200; // All systems off -> 2200 W saved
            3'd1: inst_power_saved = 16'd1400; // 3 lights off (300W) + HVAC Low (1000W) + Fan 40% (100W)
            3'd2: inst_power_saved = 16'd760;  // 2 lights off (200W) + HVAC Med (500W) + Fan 70% (60W)
            3'd3: inst_power_saved = 16'd660;  // 1 light off (100W) + HVAC Med (500W) + Fan 70% (60W)
            3'd4: inst_power_saved = 16'd0;    // Full capacity -> 0 W saved vs baseline
            default: inst_power_saved = 16'd0;
        endcase
    end

    reg [23:0] watt_sec_accumulator;

    always @(posedge clk) begin
        if (rst) begin
            watt_sec_accumulator <= 24'd0;
            energy_saved_wh      <= 16'd0;
            counter_overflow     <= 1'b0;
        end else if (tick_1s) begin
            if (watt_sec_accumulator + inst_power_saved >= 24'd3600) begin
                watt_sec_accumulator <= (watt_sec_accumulator + inst_power_saved) - 24'd3600;
                if (energy_saved_wh == 16'hFFFF) begin
                    counter_overflow <= 1'b1; // Flag saturation / overflow
                end else begin
                    energy_saved_wh <= energy_saved_wh + 1'b1;
                end
            end else begin
                watt_sec_accumulator <= watt_sec_accumulator + inst_power_saved;
            end
        end
    end

endmodule
