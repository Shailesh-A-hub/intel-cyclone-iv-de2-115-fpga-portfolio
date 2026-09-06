// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   fire_gas_top.v
// Description: Top-level integration module for Project 2 on Altera DE2-115.
//              Integrates:
//                - MCP3008 10-bit SPI ADC Multi-Channel Controller
//                - Pipelined Multi-Sensor Normalization Engine
//                - Fixed-Point Q0.8 Weighted Risk Scoring Engine
//                - Multi-Tone Alarm Buzzer PWM Controller with Mute
//                - HD44780 16x2 Character LCD Driver
//                - 8x 7-Segment Decimal Displays (Risk, Gas, Temp, Flame)
//                - Multi-Color LED Risk and Fault Indicators
//                - 115200 Baud ASCII Telemetry UART Logger
//                - Synthetic Simulation & Fault Injection Mode
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// Target:      Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// ============================================================================

`timescale 1ns / 1ps

module fire_gas_top #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter SPI_CLK_HZ  = 1_000_000,
    parameter BAUD_RATE   = 115_200,
    parameter SIM_SPEEDUP = 0
)(
    // Clocks and User Controls
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // KEY[0]=Reset_n, KEY[1]=Mute, KEY[2]=Profile, KEY[3]=Mode
    input  wire [17:0] SW,         // SW[17]=SynthEn, SW[16:15]=FaultInj, SW[14:13]=SensorSel, SW[9:0]=Value

    // External SPI ADC Interface (JP5 Header)
    output wire        GPIO_1,     // ADC CS_N
    output wire        GPIO_3,     // ADC SCLK
    output wire        GPIO_5,     // ADC MOSI
    input  wire        GPIO_7,     // ADC MISO

    // Alarm Buzzer (Piezo on JP5 Header)
    output wire        GPIO_0,     // Buzzer PWM Out

    // 7-Segment Displays
    output wire [6:0]  HEX0,       // Risk Score Ones
    output wire [6:0]  HEX1,       // Risk Score Tens
    output wire [6:0]  HEX2,       // Gas % Ones
    output wire [6:0]  HEX3,       // Gas % Tens
    output wire [6:0]  HEX4,       // Temp °C Ones
    output wire [6:0]  HEX5,       // Temp °C Tens
    output wire [6:0]  HEX6,       // Flame % Ones
    output wire [6:0]  HEX7,       // Flame % Tens

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
    // Pushbutton Debounce & Edge Detectors
    // ------------------------------------------------------------------------
    wire btn_mute_pressed;
    wire btn_profile_pressed;
    wire btn_mode_pressed;

    button_debounce #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .DEBOUNCE_MS   (SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN (1)
    ) u_deb1 (
        .clk             (CLOCK_50),
        .rst             (rst_sync),
        .btn_in          (KEY[1]),
        .debounced_state (),
        .pressed_pulse   (btn_mute_pressed),
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
        .pressed_pulse   (btn_profile_pressed),
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
        .pressed_pulse   (btn_mode_pressed),
        .released_pulse  ()
    );

    // ------------------------------------------------------------------------
    // Synthetic Test Generator & Fault Injection Registers
    // ------------------------------------------------------------------------
    reg [9:0] synth_reg_gas;
    reg [9:0] synth_reg_temp;
    reg [9:0] synth_reg_flame;
    reg [9:0] synth_reg_hum;
    reg       synth_mode_latched;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            synth_reg_gas      <= 10'd120;  // Baseline clean air (~120)
            synth_reg_temp     <= 10'd80;   // Baseline ~25°C (~80)
            synth_reg_flame    <= 10'd950;  // Baseline no flame (~950)
            synth_reg_hum      <= 10'd700;  // Baseline normal humidity (~700)
            synth_mode_latched <= 1'b0;
        end else begin
            if (btn_mode_pressed)
                synth_mode_latched <= ~synth_mode_latched;

            // In synthetic mode, user can update the selected sensor using SW[9:0]
            if (SW[17] || synth_mode_latched) begin
                case (SW[14:13])
                    2'b00: synth_reg_gas   <= SW[9:0];
                    2'b01: synth_reg_temp  <= SW[9:0];
                    2'b10: synth_reg_flame <= SW[9:0];
                    2'b11: synth_reg_hum   <= SW[9:0];
                endcase
            end
        end
    end

    // Fault Injection routing
    wire active_synth_mode = SW[17] | synth_mode_latched;
    wire synth_comm_fault  = (active_synth_mode && SW[16:15] == 2'b11);

    wire [9:0] eff_synth_gas   = (active_synth_mode && SW[16:15] == 2'b01) ? 10'd0 : synth_reg_gas;
    wire [9:0] eff_synth_temp  = (active_synth_mode && SW[16:15] == 2'b10) ? 10'd1023 : synth_reg_temp;
    wire [9:0] eff_synth_flame = synth_reg_flame;
    wire [9:0] eff_synth_hum   = synth_reg_hum;

    // ------------------------------------------------------------------------
    // Weight Profiles (Configurable via KEY[2])
    // Profile 0: Balanced (Flame=40%, Gas=30%, Temp=20%, Hum=10%)
    // Profile 1: Flame-Centric (Flame=60%, Gas=20%, Temp=15%, Hum=5%)
    // Profile 2: Gas-Centric (Flame=20%, Gas=55%, Temp=15%, Hum=10%)
    // ------------------------------------------------------------------------
    reg [1:0] weight_profile;
    reg [7:0] w_gas, w_temp, w_flame, w_hum;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            weight_profile <= 2'd0;
        end else if (btn_profile_pressed) begin
            if (weight_profile == 2'd2)
                weight_profile <= 2'd0;
            else
                weight_profile <= weight_profile + 1'b1;
        end
    end

    always @(*) begin
        case (weight_profile)
            2'd0: begin // Balanced (102 + 77 + 51 + 26 = 256)
                w_flame = 8'd102;
                w_gas   = 8'd77;
                w_temp  = 8'd51;
                w_hum   = 8'd26;
            end
            2'd1: begin // Flame-Dominant (154 + 51 + 38 + 13 = 256)
                w_flame = 8'd154;
                w_gas   = 8'd51;
                w_temp  = 8'd38;
                w_hum   = 8'd13;
            end
            2'd2: begin // Gas-Dominant (51 + 141 + 38 + 26 = 256)
                w_flame = 8'd51;
                w_gas   = 8'd141;
                w_temp  = 8'd38;
                w_hum   = 8'd26;
            end
            default: begin
                w_flame = 8'd102;
                w_gas   = 8'd77;
                w_temp  = 8'd51;
                w_hum   = 8'd26;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Module 1: MCP3008 ADC Controller
    // ------------------------------------------------------------------------
    wire [9:0] raw_adc_gas;
    wire [9:0] raw_adc_temp;
    wire [9:0] raw_adc_flame;
    wire [9:0] raw_adc_hum;
    wire       adc_valid;
    wire       adc_comm_fault;

    mcp3008_adc_controller #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .SPI_CLK_HZ    (SPI_CLK_HZ),
        .SAMPLE_RATE_HZ(SIM_SPEEDUP ? 1000 : 10)
    ) u_adc_ctrl (
        .clk              (CLOCK_50),
        .rst_n            (rst_n),
        .synth_mode_en    (active_synth_mode),
        .synth_gas_adc    (eff_synth_gas),
        .synth_temp_adc   (eff_synth_temp),
        .synth_flame_adc  (eff_synth_flame),
        .synth_hum_adc    (eff_synth_hum),
        .synth_comm_fault (synth_comm_fault),
        .spi_cs_n         (GPIO_1),
        .spi_sclk         (GPIO_3),
        .spi_mosi         (GPIO_5),
        .spi_miso         (GPIO_7),
        .adc_ch0_gas      (raw_adc_gas),
        .adc_ch1_temp     (raw_adc_temp),
        .adc_ch2_flame    (raw_adc_flame),
        .adc_ch3_hum      (raw_adc_hum),
        .adc_data_valid   (adc_valid),
        .adc_comm_fault   (adc_comm_fault)
    );

    // ------------------------------------------------------------------------
    // Module 2: Sensor Normalizer & Hardware Fault Detector
    // ------------------------------------------------------------------------
    wire [7:0] norm_gas;
    wire [7:0] norm_temp;
    wire [7:0] norm_flame;
    wire [7:0] norm_hum;
    wire [6:0] temp_celsius;
    wire [6:0] gas_percent;
    wire [6:0] flame_percent;
    wire [6:0] hum_percent;
    wire [4:0] sensor_fault_mask;
    wire       norm_valid;

    sensor_normalizer u_normalizer (
        .clk               (CLOCK_50),
        .rst_n             (rst_n),
        .adc_valid_in      (adc_valid),
        .raw_gas           (raw_adc_gas),
        .raw_temp          (raw_adc_temp),
        .raw_flame         (raw_adc_flame),
        .raw_hum           (raw_adc_hum),
        .adc_comm_fault_in (adc_comm_fault),
        .norm_gas          (norm_gas),
        .norm_temp         (norm_temp),
        .norm_flame        (norm_flame),
        .norm_hum          (norm_hum),
        .temp_celsius      (temp_celsius),
        .gas_percent       (gas_percent),
        .flame_percent     (flame_percent),
        .hum_percent       (hum_percent),
        .sensor_fault_mask (sensor_fault_mask),
        .norm_valid_out    (norm_valid)
    );

    // ------------------------------------------------------------------------
    // Module 3: Fixed-Point Q0.8 Weighted Risk Engine
    // ------------------------------------------------------------------------
    wire [6:0] risk_score;
    wire [7:0] risk_intermediate;
    wire [1:0] risk_level;
    wire [1:0] dominant_hazard;
    wire [4:0] fault_code;
    wire       risk_valid;

    risk_engine_q8_8 #(
        .THRESH_SAFE_MAX   (7'd34),
        .THRESH_CAUTION_MAX(7'd69)
    ) u_risk_engine (
        .clk                 (CLOCK_50),
        .rst_n               (rst_n),
        .norm_valid_in       (norm_valid),
        .norm_gas            (norm_gas),
        .norm_temp           (norm_temp),
        .norm_flame          (norm_flame),
        .norm_hum            (norm_hum),
        .sensor_fault_mask_in(sensor_fault_mask),
        .weight_gas          (w_gas),
        .weight_temp         (w_temp),
        .weight_flame        (w_flame),
        .weight_hum          (w_hum),
        .risk_score          (risk_score),
        .risk_intermediate   (risk_intermediate),
        .risk_level          (risk_level),
        .dominant_hazard     (dominant_hazard),
        .fault_code          (fault_code),
        .risk_valid_out      (risk_valid)
    );

    // ------------------------------------------------------------------------
    // Module 4: Multi-Cadence Alarm Buzzer Controller
    // ------------------------------------------------------------------------
    wire alarm_active;
    wire alarm_muted;

    alarm_buzzer_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_buzzer (
        .clk             (CLOCK_50),
        .rst_n           (rst_n),
        .risk_level      (risk_level),
        .alarm_mute_press(btn_mute_pressed),
        .buzzer_pwm_out  (GPIO_0),
        .alarm_active    (alarm_active),
        .alarm_muted     (alarm_muted)
    );

    // ------------------------------------------------------------------------
    // Module 5: 16x2 Character LCD Driver (HD44780)
    // ------------------------------------------------------------------------
    // Screen Layout:
    // Line 1: "G:xx% T:xxC F:xx%"  (16 ASCII chars)
    // Line 2: "RISK:xxx [SAFE  ]" (16 ASCII chars)
    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;
    wire        lcd_refresh;

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

    function [7:0] f_ascii_digit;
        input [3:0] d;
        begin
            f_ascii_digit = 8'd48 + {4'd0, d};
        end
    endfunction

    always @(*) begin
        // Line 1: "G:xx% T:xxC F:xx%"
        lcd_line1 = {
            "G", ":", f_ascii_digit((gas_percent/10)%10), f_ascii_digit(gas_percent%10), "%", " ",
            "T", ":", f_ascii_digit((temp_celsius/10)%10), f_ascii_digit(temp_celsius%10), "C", " ",
            "F", ":", f_ascii_digit((flame_percent/10)%10), f_ascii_digit(flame_percent%10), "%"
        };

        // Line 2: "RISK:xxx [SAFE  ]" or "FAULT: ERR [x]"
        if (risk_level == 2'b11) begin
            lcd_line2 = {
                "F", "A", "U", "L", "T", ":", " ", "E", "R", "R", " ", "0", "x",
                f_ascii_digit({3'b0, fault_code[4]}),
                (fault_code[3:0] < 10) ? f_ascii_digit(fault_code[3:0]) : (8'd55 + {4'd0, fault_code[3:0]}),
                " "
            };
        end else begin
            lcd_line2 = {
                "R", "I", "S", "K", ":",
                (risk_score >= 100) ? "1" : "0",
                f_ascii_digit((risk_score/10)%10),
                f_ascii_digit(risk_score%10),
                " ", "[",
                (risk_level == 2'b00) ? "S" : (risk_level == 2'b01) ? "C" : "D",
                (risk_level == 2'b00) ? "A" : (risk_level == 2'b01) ? "A" : "A",
                (risk_level == 2'b00) ? "F" : (risk_level == 2'b01) ? "U" : "N",
                (risk_level == 2'b00) ? "E" : (risk_level == 2'b01) ? "T" : "G",
                (risk_level == 2'b10) ? "E" : " ",
                (risk_level == 2'b10) ? "R" : " ",
                "]"
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
    // HEX0, HEX1: Risk Score (00 - 99 or Dash on Fault)
    // HEX2, HEX3: Gas % (00 - 99)
    // HEX4, HEX5: Temp °C (00 - 99)
    // HEX6, HEX7: Flame % (00 - 99)

    wire is_fault = (risk_level == 2'b11);

    wire [3:0] d_risk_ones = (risk_score >= 100) ? 4'd0 : (risk_score % 7'd10);
    wire [3:0] d_risk_tens = (risk_score >= 100) ? 4'd0 : ((risk_score / 7'd10) % 7'd10);
    wire [3:0] d_gas_ones  = gas_percent % 7'd10;
    wire [3:0] d_gas_tens  = (gas_percent / 7'd10) % 7'd10;
    wire [3:0] d_tmp_ones  = temp_celsius % 7'd10;
    wire [3:0] d_tmp_tens  = (temp_celsius / 7'd10) % 7'd10;
    wire [3:0] d_flm_ones  = flame_percent % 7'd10;
    wire [3:0] d_flm_tens  = (flame_percent / 7'd10) % 7'd10;

    seven_seg_dec u_hex0 (
        .dec_digit (d_risk_ones),
        .blank     (1'b0),
        .show_dash (is_fault),
        .seg_out   (HEX0)
    );

    seven_seg_dec u_hex1 (
        .dec_digit (d_risk_tens),
        .blank     (1'b0),
        .show_dash (is_fault),
        .seg_out   (HEX1)
    );

    seven_seg_dec u_hex2 (
        .dec_digit (d_gas_ones),
        .blank     (1'b0),
        .show_dash (fault_code[0]),
        .seg_out   (HEX2)
    );

    seven_seg_dec u_hex3 (
        .dec_digit (d_gas_tens),
        .blank     (1'b0),
        .show_dash (fault_code[0]),
        .seg_out   (HEX3)
    );

    seven_seg_dec u_hex4 (
        .dec_digit (d_tmp_ones),
        .blank     (1'b0),
        .show_dash (fault_code[1]),
        .seg_out   (HEX4)
    );

    seven_seg_dec u_hex5 (
        .dec_digit (d_tmp_tens),
        .blank     (1'b0),
        .show_dash (fault_code[1]),
        .seg_out   (HEX5)
    );

    seven_seg_dec u_hex6 (
        .dec_digit (d_flm_ones),
        .blank     (1'b0),
        .show_dash (fault_code[2]),
        .seg_out   (HEX6)
    );

    seven_seg_dec u_hex7 (
        .dec_digit (d_flm_tens),
        .blank     (1'b0),
        .show_dash (fault_code[2]),
        .seg_out   (HEX7)
    );

    // ------------------------------------------------------------------------
    // Module 7: LED Status Indicators
    // ------------------------------------------------------------------------
    // 4 Hz and 1 Hz flash clocks for alarm status
    reg [23:0] flash_timer;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) flash_timer <= 24'd0;
        else flash_timer <= flash_timer + 1'b1;
    end
    wire flash_4hz = flash_timer[21]; // ~6 Hz at 50 MHz
    wire flash_1hz = flash_timer[23]; // ~1.5 Hz

    // Green LEDs: Normal / Safe operation
    assign LEDG[3:0] = (risk_level == 2'b00) ? 4'b1111 : 4'b0000;
    assign LEDG[5:4] = weight_profile;
    assign LEDG[7:6] = dominant_hazard;
    assign LEDG[8]   = active_synth_mode;

    // Red LEDs: Danger / Caution / Fault
    wire danger_flash  = (risk_level == 2'b10) && flash_4hz;
    wire caution_pulse = (risk_level == 2'b01);
    wire fault_flash   = (risk_level == 2'b11) && flash_1hz;

    assign LEDR[17:15] = {3{danger_flash}};
    assign LEDR[14:12] = {3{caution_pulse}};
    assign LEDR[11]    = alarm_muted;
    assign LEDR[10]    = alarm_active;
    assign LEDR[9:5]   = 5'b00000;
    assign LEDR[4:0]   = fault_flash ? fault_code : 5'b00000;

    // ------------------------------------------------------------------------
    // Module 8: Real-Time Telemetry UART Logger
    // ------------------------------------------------------------------------
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

    fire_gas_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_logger (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .trigger_tx (uart_tx_trigger),
        .gas_pct    (gas_percent),
        .temp_c     (temp_celsius),
        .flame_pct  (flame_percent),
        .hum_pct    (hum_percent),
        .risk_score (risk_score),
        .risk_level (risk_level),
        .fault_code (fault_code),
        .uart_txd   (UART_TXD),
        .tx_busy    ()
    );

endmodule
