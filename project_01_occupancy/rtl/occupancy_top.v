//=============================================================================
// Module: occupancy_top
// Project: Project 1 - Multi-Zone Occupancy & Energy-Saving Decision Engine
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Complete top-level integration. Instantiates 4 zone FSMs,
//              energy decision engine, debouncers, timebases, 7-segment drivers,
//              HD44780 LCD controller, PWM fan controller, and UART telemetry.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module occupancy_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    // Clocks and Resets
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0] = Reset (active low)
    // Slide Switches
    input  wire [17:0] SW,              // SW[3:0] = Motion stand-ins, SW[4] = Dark mode, SW[17:16] = Timeout preset
    // External GPIO JP5 inputs
    input  wire [3:0]  GPIO_PIR_IN,     // External PIR sensors (JP5 Pins 1..4)
    // Actuator Outputs
    output wire        RELAY_LIGHTS,    // JP5 Pin 6
    output wire        RELAY_HVAC,      // JP5 Pin 7
    output wire        RELAY_FANS,      // JP5 Pin 8
    // LEDs
    output wire [17:0] LEDR,            // LEDR[3:0] = Raw Motion, LEDR[17] = Fault
    output wire [8:0]  LEDG,            // LEDG[3:0] = Zone Occupied, LEDG[4]=Light, LEDG[5]=HVAC, LEDG[6]=Fan
    // 7-Segment Displays (Active-Low)
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    // 16x2 HD44780 LCD
    inout  wire [7:0]  LCD_DATA,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    // RS-232 UART
    output wire        UART_TXD
);

    // 1. Reset Synchronizer (KEY[0] is active-low master reset)
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

    // 2. Timebase Generators (1 ms and 1 sec)
    wire tick_1ms;
    timer_ms #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_timer_ms (
        .clk(CLOCK_50),
        .rst(rst),
        .tick_1ms(tick_1ms)
    );

    wire tick_1s;
    timer_sec #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_timer_sec (
        .clk(CLOCK_50),
        .rst(rst),
        .tick_1sec(tick_1s)
    );

    // 3. Debouncers on Motion Inputs (combines switches and GPIO PIRs)
    wire [3:0] raw_motion = SW[3:0] | GPIO_PIR_IN;
    wire [3:0] debounced_motion;

    genvar z;
    generate
        for (z = 0; z < 4; z = z + 1) begin : gen_debouncers
            button_debounce #(
                .CLK_FREQ_HZ(CLK_FREQ_HZ),
                .DEBOUNCE_MS(10),
                .ACTIVE_LOW_IN(0) // Active-high motion inputs
            ) u_deb (
                .clk(CLOCK_50),
                .rst(rst),
                .btn_in(raw_motion[z]),
                .debounced_state(debounced_motion[z]),
                .pressed_pulse(),
                .released_pulse()
            );
        end
    endgenerate

    // Timeout duration selection via SW[17:16]
    reg [15:0] timeout_preset;
    always @(*) begin
        case (SW[17:16])
            2'b00: timeout_preset = 16'd5;   // 5 seconds (fast demo / bench test)
            2'b01: timeout_preset = 16'd30;  // 30 seconds
            2'b10: timeout_preset = 16'd60;  // 60 seconds
            2'b11: timeout_preset = 16'd300; // 5 minutes
        endcase
    end

    // 4. Instantiate 4 Independent Zone FSMs
    wire [3:0] zone_occupied;
    wire [3:0] zone_light_req;
    wire [3:0] zone_hvac_req;
    wire [3:0] zone_fault;
    wire [3:0] zone_changed;
    wire [15:0] zone_timer [0:3];

    generate
        for (z = 0; z < 4; z = z + 1) begin : gen_zone_fsms
            zone_fsm #(.ZONE_ID(z + 1)) u_zone (
                .clk(CLOCK_50),
                .rst(rst),
                .motion_in(debounced_motion[z]),
                .tick_1s(tick_1s),
                .timeout_preset(timeout_preset),
                .fault_timeout(16'd600), // 10 minutes stuck-high fault threshold
                .state(),
                .occupied_out(zone_occupied[z]),
                .light_req(zone_light_req[z]),
                .hvac_req(zone_hvac_req[z]),
                .countdown_val(zone_timer[z]),
                .state_changed(zone_changed[z]),
                .sensor_fault(zone_fault[z])
            );
        end
    endgenerate

    // 5. Energy Decision Engine
    wire [3:0]  zone_lights;
    wire        main_lighting_relay;
    wire        hvac_relay;
    wire [1:0]  hvac_level;
    wire        fan_relay;
    wire [7:0]  fan_pwm_duty;
    wire [2:0]  active_zones;
    wire [15:0] energy_wh;
    wire        counter_overflow;

    energy_decision_engine u_decision (
        .clk(CLOCK_50),
        .rst(rst),
        .zone_occupied(zone_occupied),
        .zone_light_req(zone_light_req),
        .zone_hvac_req(zone_hvac_req),
        .ambient_dark(SW[4]), // SW[4] = 1 for dark/night mode
        .tick_1s(tick_1s),
        .zone_lights(zone_lights),
        .main_lighting_relay(main_lighting_relay),
        .hvac_relay(hvac_relay),
        .hvac_level(hvac_level),
        .fan_relay(fan_relay),
        .fan_pwm_duty(fan_pwm_duty),
        .active_zone_count(active_zones),
        .energy_saved_wh(energy_wh),
        .counter_overflow(counter_overflow)
    );

    // 6. Fan Speed PWM Generator
    wire fan_pwm_out;
    pwm_generator #(.RESOLUTION_BITS(8)) u_fan_pwm (
        .clk(CLOCK_50),
        .rst(rst),
        .enable(fan_relay),
        .prescaler(16'd195), // ~1 kHz PWM frequency
        .period(8'd255),
        .duty_cycle(fan_pwm_duty),
        .pwm_out(fan_pwm_out),
        .cycle_end()
    );

    // Physical Actuator Relay Assignments
    assign RELAY_LIGHTS = main_lighting_relay;
    assign RELAY_HVAC   = hvac_relay;
    assign RELAY_FANS   = fan_pwm_out;

    // LED Indicator Assignments
    assign LEDR[3:0]   = raw_motion;
    assign LEDR[16:4]  = 13'b0;
    assign LEDR[17]    = |zone_fault | counter_overflow; // Fault indicator

    assign LEDG[3:0]   = zone_occupied;
    assign LEDG[4]     = main_lighting_relay;
    assign LEDG[5]     = hvac_relay;
    assign LEDG[6]     = fan_relay;
    assign LEDG[8:7]   = 2'b00;

    // 7. 7-Segment Displays:
    // HEX3..HEX0: Energy saved in Watt-hours (4-digit decimal / hex)
    seven_seg_hex u_hex0 (.hex_digit(energy_wh[3:0]),   .blank(1'b0), .seg_out(HEX0));
    seven_seg_hex u_hex1 (.hex_digit(energy_wh[7:4]),   .blank(1'b0), .seg_out(HEX1));
    seven_seg_hex u_hex2 (.hex_digit(energy_wh[11:8]),  .blank(1'b0), .seg_out(HEX2));
    seven_seg_hex u_hex3 (.hex_digit(energy_wh[15:12]), .blank(1'b0), .seg_out(HEX3));

    // HEX5..HEX4: HVAC Stage ("H0", "H1", "H2", "H3")
    // 'H' pattern on HEX5 = 7'b000_1001 (active-low segments {g,f,e,d,c,b,a} for 'H' = 0x09)
    assign HEX5 = 7'b000_1001;
    seven_seg_dec u_hex4 (.dec_digit({2'b00, hvac_level}), .blank(1'b0), .show_dash(1'b0), .seg_out(HEX4));

    // HEX7..HEX6: Active zones count ("Z0" to "Z4")
    // 'Z' (looks like 2) on HEX7 = 7'b010_0100
    assign HEX7 = 7'b010_0100;
    seven_seg_dec u_hex6 (.dec_digit({1'b0, active_zones}), .blank(1'b0), .show_dash(1'b0), .seg_out(HEX6));

    // 8. 16x2 HD44780 LCD Display Controller
    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;
    wire [7:0] ascii_wh0 = (energy_wh[3:0] < 10) ? (8'h30 + energy_wh[3:0]) : (8'h41 + energy_wh[3:0] - 10);
    wire [7:0] ascii_wh1 = (energy_wh[7:4] < 10) ? (8'h30 + energy_wh[7:4]) : (8'h41 + energy_wh[7:4] - 10);

    always @(*) begin
        // Line 1: "ZONES: Z1 Z2 -- --"
        lcd_line1 = {
            "ZONES: ",
            zone_occupied[0] ? "Z1 " : "-- ",
            zone_occupied[1] ? "Z2 " : "-- ",
            zone_occupied[2] ? "Z3 " : "-- ",
            zone_occupied[3] ? "Z4"  : "--"
        };

        // Line 2: "SAVED: 0000 Wh  "
        lcd_line2 = {
            "SAVED: ",
            ascii_wh1,
            ascii_wh0,
            " Wh   H:",
            hvac_level == 2'b00 ? "0" :
            hvac_level == 2'b01 ? "1" :
            hvac_level == 2'b10 ? "2" : "3",
            " "
        };
    end

    lcd_hd44780_controller #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_lcd (
        .clk(CLOCK_50),
        .rst(rst),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .refresh_strobe(tick_1s), // Update screen once per second
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // 9. UART Telemetry Logger (115200 baud)
    wire send_uart = tick_1s | (|zone_changed);
    occupancy_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(115200)
    ) u_logger (
        .clk(CLOCK_50),
        .rst(rst),
        .send_trigger(send_uart),
        .zone_occupied(zone_occupied),
        .hvac_level(hvac_level),
        .energy_wh(energy_wh),
        .uart_txd(UART_TXD)
    );

endmodule
