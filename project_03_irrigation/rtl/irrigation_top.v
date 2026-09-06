// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   irrigation_top.v
// Description: Top-level integration module for Project 3 on Altera DE2-115.
//              Integrates:
//                - MCP3008 SPI ADC reader for Soil Moisture
//                - Dedicated 1-Wire State Machine for DHT11 Temp/Humidity
//                - Adaptive Threshold Engine (climate trend compensation)
//                - Safety-Critical Pump Controller FSM with Hysteresis,
//                  Minimum Run/Off Timers, Rain Lockout, and Manual Override
//                - 16x2 HD44780 Character LCD Display
//                - 8x 7-Segment Decimal Displays
//                - LED Status Indicators
//                - 115200 Baud ASCII Telemetry UART Logger
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// Target:      Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// ============================================================================

`timescale 1ns / 1ps

module irrigation_top #(
    parameter CLK_FREQ_HZ     = 50_000_000,
    parameter SPI_CLK_HZ      = 1_000_000,
    parameter BAUD_RATE       = 115_200,
    parameter MIN_ON_SECONDS  = 5,
    parameter MIN_OFF_SECONDS = 10,
    parameter SIM_SPEEDUP     = 0
)(
    // Clocks and User Controls
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // KEY[0]=Reset_n, KEY[1]=ManualOvr, KEY[2]=BaseThresh, KEY[3]=Mode
    input  wire [17:0] SW,         // SW[17]=SynthEn, SW[16]=RainSim, SW[15]=ManOvrSim, SW[14:13]=Sel, SW[9:0]=Val

    // External Interface on JP5 Header
    output wire        GPIO_0,     // Relay Pump Control Output (PIN_AB22)
    output wire        GPIO_1,     // MCP3008 ADC CS_N (PIN_AC15)
    output wire        GPIO_3,     // MCP3008 ADC SCLK (PIN_Y17)
    output wire        GPIO_5,     // MCP3008 ADC MOSI (PIN_Y16)
    input  wire        GPIO_7,     // MCP3008 ADC MISO (PIN_AE16)
    inout  wire        GPIO_9,     // DHT11 1-Wire Bidirectional (PIN_AF16)
    input  wire        GPIO_11,    // Rain Sensor Digital Input (PIN_AE15)

    // 7-Segment Displays
    output wire [6:0]  HEX0,       // Soil Moisture % Ones
    output wire [6:0]  HEX1,       // Soil Moisture % Tens
    output wire [6:0]  HEX2,       // Adaptive Threshold % Ones
    output wire [6:0]  HEX3,       // Adaptive Threshold % Tens
    output wire [6:0]  HEX4,       // Temp °C Ones
    output wire [6:0]  HEX5,       // Temp °C Tens
    output wire [6:0]  HEX6,       // Humidity % Ones
    output wire [6:0]  HEX7,       // Humidity % Tens

    // LED Status Indicators
    output wire [8:0]  LEDG,       // Green LEDs
    output wire [17:0] LEDR,       // Red LEDs

    // 16x2 HD44780 LCD
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_ON,
    output wire        LCD_BLON,

    // Serial Communication
    output wire        UART_TXD
);

    // ------------------------------------------------------------------------
    // Reset Synchronization
    // ------------------------------------------------------------------------
    wire rst_n;
    wire rst_sync;

    reset_synchronizer #(
        .STAGES         (2),
        .ACTIVE_LOW_IN  (1),
        .ACTIVE_LOW_OUT (1)
    ) u_rst_sync_n (
        .clk            (CLOCK_50),
        .async_rst_in   (KEY[0]),
        .sync_rst_out   (rst_n)
    );

    assign rst_sync = ~rst_n;

    // ------------------------------------------------------------------------
    // Pushbutton Debounce
    // ------------------------------------------------------------------------
    wire btn_manual_ovr_pulse;
    wire btn_thresh_adj_pulse;
    wire btn_mode_toggle_pulse;

    button_debounce #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .DEBOUNCE_MS   (SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN (1)
    ) u_deb1 (
        .clk             (CLOCK_50),
        .rst             (rst_sync),
        .btn_in          (KEY[1]),
        .debounced_state (),
        .pressed_pulse   (btn_manual_ovr_pulse),
        .released_pulse  ()
    );

    button_debounce #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .DEBOUNCE_MS   (SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN (1)
    ) u_deb2 (
        .clk             (CLOCK_50),
        .rst             (rst_sync),
        .btn_in          (KEY[2]),
        .debounced_state (),
        .pressed_pulse   (btn_thresh_adj_pulse),
        .released_pulse  ()
    );

    button_debounce #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .DEBOUNCE_MS   (SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN (1)
    ) u_deb3 (
        .clk             (CLOCK_50),
        .rst             (rst_sync),
        .btn_in          (KEY[3]),
        .debounced_state (),
        .pressed_pulse   (btn_mode_toggle_pulse),
        .released_pulse  ()
    );

    // ------------------------------------------------------------------------
    // Synthetic Simulation & Control Latches
    // ------------------------------------------------------------------------
    reg        synth_mode_latched;
    reg        manual_ovr_latched;
    reg [6:0]  base_threshold_reg;
    reg [9:0]  synth_soil_reg;
    reg [6:0]  synth_temp_reg;
    reg [6:0]  synth_hum_reg;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            synth_mode_latched <= 1'b0;
            manual_ovr_latched <= 1'b0;
            base_threshold_reg <= 7'd40; // Default nominal 40%
            synth_soil_reg     <= 10'd600; // Moderate moisture (~53%)
            synth_temp_reg     <= 7'd24;   // 24°C
            synth_hum_reg      <= 7'd55;   // 55% RH
        end else begin
            if (btn_mode_toggle_pulse)
                synth_mode_latched <= ~synth_mode_latched;

            if (btn_manual_ovr_pulse)
                manual_ovr_latched <= ~manual_ovr_latched;

            if (btn_thresh_adj_pulse) begin
                if (base_threshold_reg == 7'd40) base_threshold_reg <= 7'd50;
                else if (base_threshold_reg == 7'd50) base_threshold_reg <= 7'd30;
                else base_threshold_reg <= 7'd40;
            end

            // Update synthetic registers in synthetic mode
            if (SW[17] || synth_mode_latched) begin
                case (SW[14:13])
                    2'b00: synth_soil_reg <= SW[9:0];
                    2'b01: synth_temp_reg <= SW[6:0];
                    2'b10: synth_hum_reg  <= SW[6:0];
                    2'b11: begin /* Reserved for fault injection */ end
                endcase
            end
        end
    end

    wire active_synth_mode = SW[17] | synth_mode_latched;
    wire eff_rain_detected = GPIO_11 | SW[16];
    wire eff_manual_ovr    = SW[15] | manual_ovr_latched;
    wire synth_dht_fault   = (active_synth_mode && SW[14:13] == 2'b11 && SW[0]);
    wire synth_adc_fault   = (active_synth_mode && SW[14:13] == 2'b11 && SW[1]);

    // ------------------------------------------------------------------------
    // Periodic Timers: 1 Hz Second Tick & 2 Hz LCD Refresh
    // ------------------------------------------------------------------------
    wire sec_tick;
    periodic_timer #(
        .PERIOD(CLK_FREQ_HZ / (SIM_SPEEDUP ? 100 : 1)),
        .WIDTH (32)
    ) u_sec_timer (
        .clk      (CLOCK_50),
        .rst      (rst_sync),
        .enable   (1'b1),
        .tick_in  (1'b1),
        .tick_out (sec_tick),
        .count_val()
    );

    wire lcd_refresh;
    periodic_timer #(
        .PERIOD(CLK_FREQ_HZ / (SIM_SPEEDUP ? 50 : 2)),
        .WIDTH (32)
    ) u_lcd_timer (
        .clk      (CLOCK_50),
        .rst      (rst_sync),
        .enable   (1'b1),
        .tick_in  (1'b1),
        .tick_out (lcd_refresh),
        .count_val()
    );

    wire uart_tx_trigger;
    periodic_timer #(
        .PERIOD(CLK_FREQ_HZ / (SIM_SPEEDUP ? 100 : 1)),
        .WIDTH (32)
    ) u_uart_timer (
        .clk      (CLOCK_50),
        .rst      (rst_sync),
        .enable   (1'b1),
        .tick_in  (1'b1),
        .tick_out (uart_tx_trigger),
        .count_val()
    );

    // ------------------------------------------------------------------------
    // Module 1: DHT11 Temperature & Humidity Controller
    // ------------------------------------------------------------------------
    wire [7:0] dht_hum_raw;
    wire [7:0] dht_temp_raw;
    wire       dht_valid;
    wire       dht_chk_err;
    wire       dht_timeout_err;

    dht11_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SIM_SPEEDUP(SIM_SPEEDUP)
    ) u_dht11 (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .start_read_pulse  (sec_tick),
        .synth_mode_en     (active_synth_mode),
        .synth_temp        ({1'b0, synth_temp_reg}),
        .synth_hum         ({1'b0, synth_hum_reg}),
        .synth_fault_inject(synth_dht_fault),
        .dht11_data_io     (GPIO_9),
        .humidity_int      (dht_hum_raw),
        .temperature_int   (dht_temp_raw),
        .data_valid        (dht_valid),
        .checksum_error    (dht_chk_err),
        .timeout_error     (dht_timeout_err),
        .busy              ()
    );

    wire [6:0] cur_temp = (dht_temp_raw > 8'd99) ? 7'd99 : dht_temp_raw[6:0];
    wire [6:0] cur_hum  = (dht_hum_raw  > 8'd99) ? 7'd99 : dht_hum_raw[6:0];

    // ------------------------------------------------------------------------
    // Module 2: Soil Moisture ADC Reader
    // ------------------------------------------------------------------------
    wire [6:0] soil_moisture_pct;
    wire [9:0] raw_soil_adc;
    wire       moisture_valid;
    wire       soil_adc_fault;

    soil_moisture_adc_reader #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SPI_CLK_HZ     (SPI_CLK_HZ),
        .SAMPLE_RATE_HZ (SIM_SPEEDUP ? 100 : 10)
    ) u_soil_adc (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .synth_mode_en     (active_synth_mode),
        .synth_soil_adc    (synth_soil_reg),
        .synth_fault_inject(synth_adc_fault),
        .spi_cs_n          (GPIO_1),
        .spi_sclk          (GPIO_3),
        .spi_mosi          (GPIO_5),
        .spi_miso          (GPIO_7),
        .moisture_percent  (soil_moisture_pct),
        .raw_adc_out       (raw_soil_adc),
        .moisture_valid    (moisture_valid),
        .sensor_fault      (soil_adc_fault)
    );

    // ------------------------------------------------------------------------
    // Module 3: Adaptive Threshold Engine
    // ------------------------------------------------------------------------
    wire [6:0] adaptive_th;
    wire [6:0] turn_on_th;
    wire [6:0] turn_off_th;
    wire [4:0] temp_adj;
    wire [4:0] hum_adj;
    wire       boost_active;

    adaptive_threshold_engine u_th_engine (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .temp_celsius      (cur_temp),
        .humidity_percent  (cur_hum),
        .base_threshold    (base_threshold_reg),
        .hysteresis_band   (5'd5), // 5% hysteresis
        .adaptive_threshold(adaptive_th),
        .turn_on_threshold (turn_on_th),
        .turn_off_threshold(turn_off_th),
        .temp_adjustment   (temp_adj),
        .hum_adjustment    (hum_adj),
        .boost_active      (boost_active)
    );

    // ------------------------------------------------------------------------
    // Module 4: Pump Controller FSM
    // ------------------------------------------------------------------------
    wire        relay_pump_ctrl;
    wire        pump_running;
    wire        rain_lockout;
    wire        manual_ovr_active;
    wire [2:0]  pump_fsm_state;
    wire [15:0] watering_cycles;
    wire [31:0] total_watering_sec;

    pump_controller_fsm #(
        .MIN_ON_SECONDS (MIN_ON_SECONDS),
        .MIN_OFF_SECONDS(MIN_OFF_SECONDS)
    ) u_pump_fsm (
        .clk                   (CLOCK_50),
        .rst_n                 (rst_n),
        .moisture_percent      (soil_moisture_pct),
        .turn_on_threshold     (turn_on_th),
        .turn_off_threshold    (turn_off_th),
        .rain_detected         (eff_rain_detected),
        .manual_override       (eff_manual_ovr),
        .sensor_fault          (soil_adc_fault || dht_timeout_err),
        .sec_tick              (sec_tick),
        .relay_pump_ctrl       (relay_pump_ctrl),
        .pump_is_running       (pump_running),
        .rain_lockout_active   (rain_lockout),
        .manual_override_active(manual_ovr_active),
        .fsm_state_id          (pump_fsm_state),
        .watering_cycles_count (watering_cycles),
        .total_watering_seconds(total_watering_sec)
    );

    assign GPIO_0 = relay_pump_ctrl; // Drive external relay pin

    // ------------------------------------------------------------------------
    // Module 5: 16x2 Character LCD Driver (HD44780)
    // ------------------------------------------------------------------------
    // Line 1: "S:xx% T:xxC H:xx%"
    // Line 2: "PUMP:ON  [TH:xx%]" or "RAIN LOCKOUT   " or "MANUAL FORCE    "
    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;

    function [7:0] f_digit;
        input [3:0] d;
        begin
            f_digit = 8'd48 + {4'd0, d};
        end
    endfunction

    always @(*) begin
        // Line 1: "S:xx% T:xxC H:xx%"
        lcd_line1 = {
            "S", ":", f_digit((soil_moisture_pct/10)%10), f_digit(soil_moisture_pct%10), "%", " ",
            "T", ":", f_digit((cur_temp/10)%10), f_digit(cur_temp%10), "C", " ",
            "H", ":", f_digit((cur_hum/10)%10), f_digit(cur_hum%10), "%"
        };

        // Line 2
        if (rain_lockout) begin
            lcd_line2 = {"R", "A", "I", "N", " ", "L", "O", "C", "K", "O", "U", "T", " ", " ", " ", " "};
        end else if (manual_ovr_active) begin
            lcd_line2 = {"M", "A", "N", "U", "A", "L", " ", "F", "O", "R", "C", "E", " ", "O", "N", " "};
        end else begin
            lcd_line2 = {
                "P", "U", "M", "P", ":",
                (pump_running) ? "O" : "O",
                (pump_running) ? "N" : "F",
                (pump_running) ? " " : "F",
                " ", "[", "T", "H", ":",
                f_digit((adaptive_th/10)%10),
                f_digit(adaptive_th%10),
                "%", "]"
            };
        end
    end

    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk           (CLOCK_50),
        .rst           (rst_sync),
        .line1_text    (lcd_line1),
        .line2_text    (lcd_line2),
        .refresh_strobe(lcd_refresh),
        .busy          (),
        .lcd_data      (LCD_DATA),
        .lcd_rw        (LCD_RW),
        .lcd_en        (LCD_EN),
        .lcd_rs        (LCD_RS),
        .lcd_on        (LCD_ON),
        .lcd_blon      (LCD_BLON)
    );

    // ------------------------------------------------------------------------
    // Module 6: 7-Segment Displays
    // ------------------------------------------------------------------------
    // HEX1-0: Soil Moisture % (00 - 99)
    // HEX3-2: Adaptive Threshold % (00 - 99)
    // HEX5-4: Temperature °C (00 - 99)
    // HEX7-6: Humidity % (00 - 99)

    wire [3:0] d_soil_ones = soil_moisture_pct % 7'd10;
    wire [3:0] d_soil_tens = (soil_moisture_pct / 7'd10) % 7'd10;
    wire [3:0] d_th_ones   = adaptive_th % 7'd10;
    wire [3:0] d_th_tens   = (adaptive_th / 7'd10) % 7'd10;
    wire [3:0] d_temp_ones = cur_temp % 7'd10;
    wire [3:0] d_temp_tens = (cur_temp / 7'd10) % 7'd10;
    wire [3:0] d_hum_ones  = cur_hum % 7'd10;
    wire [3:0] d_hum_tens  = (cur_hum / 7'd10) % 7'd10;

    seven_seg_dec u_hex0 (
        .dec_digit (d_soil_ones),
        .blank     (1'b0),
        .show_dash (soil_adc_fault),
        .seg_out   (HEX0)
    );

    seven_seg_dec u_hex1 (
        .dec_digit (d_soil_tens),
        .blank     (1'b0),
        .show_dash (soil_adc_fault),
        .seg_out   (HEX1)
    );

    seven_seg_dec u_hex2 (
        .dec_digit (d_th_ones),
        .blank     (1'b0),
        .show_dash (1'b0),
        .seg_out   (HEX2)
    );

    seven_seg_dec u_hex3 (
        .dec_digit (d_th_tens),
        .blank     (1'b0),
        .show_dash (1'b0),
        .seg_out   (HEX3)
    );

    seven_seg_dec u_hex4 (
        .dec_digit (d_temp_ones),
        .blank     (1'b0),
        .show_dash (dht_timeout_err),
        .seg_out   (HEX4)
    );

    seven_seg_dec u_hex5 (
        .dec_digit (d_temp_tens),
        .blank     (1'b0),
        .show_dash (dht_timeout_err),
        .seg_out   (HEX5)
    );

    seven_seg_dec u_hex6 (
        .dec_digit (d_hum_ones),
        .blank     (1'b0),
        .show_dash (dht_chk_err),
        .seg_out   (HEX6)
    );

    seven_seg_dec u_hex7 (
        .dec_digit (d_hum_tens),
        .blank     (1'b0),
        .show_dash (dht_chk_err),
        .seg_out   (HEX7)
    );

    // ------------------------------------------------------------------------
    // Module 7: LED Status Indicators
    // ------------------------------------------------------------------------
    assign LEDG[0]   = pump_running;
    assign LEDG[1]   = (soil_moisture_pct >= 7'd25);
    assign LEDG[2]   = (soil_moisture_pct >= 7'd50);
    assign LEDG[3]   = (soil_moisture_pct >= 7'd75);
    assign LEDG[5:4] = pump_fsm_state[1:0];
    assign LEDG[6]   = boost_active;
    assign LEDG[7]   = 1'b0;
    assign LEDG[8]   = active_synth_mode;

    assign LEDR[0]   = rain_lockout;
    assign LEDR[1]   = manual_ovr_active;
    assign LEDR[2]   = dht_chk_err;
    assign LEDR[3]   = dht_timeout_err;
    assign LEDR[4]   = soil_adc_fault;
    assign LEDR[17:5]= 13'd0;

    // ------------------------------------------------------------------------
    // Module 8: UART Telemetry Logger
    // ------------------------------------------------------------------------
    irrigation_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_log (
        .clk            (CLOCK_50),
        .rst_n          (rst_n),
        .trigger_tx     (uart_tx_trigger),
        .soil_moist_pct (soil_moisture_pct),
        .adaptive_th_pct(adaptive_th),
        .temp_c         (cur_temp),
        .hum_pct        (cur_hum),
        .pump_on        (pump_running),
        .rain_active    (eff_rain_detected),
        .cycle_count    (watering_cycles),
        .uart_txd       (UART_TXD),
        .tx_busy        ()
    );

endmodule
