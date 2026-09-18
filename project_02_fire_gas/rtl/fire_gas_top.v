// ============================================================================
// Module: fire_gas_top
// Project: Project 2 / Basic #1 — Gas & Fire Sensor Readout with Threshold Alert
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Direct hardware implementation of Basic #1:
//              - Reads MQ-2 and MQ-7 directly via digital comparator outputs (DO)
//              - NO EXTERNAL ADC REQUIRED
//              - Reads DHT11 temperature/humidity via 1-wire microsecond timing protocol
//              - Independent threshold evaluation:
//                  * MQ2_DO alert -> LEDG[0]
//                  * MQ7_DO alert -> LEDG[1]
//                  * DHT11 High Temp (>35°C) -> LEDG[2]
//              - KEY[0] resets / acknowledges alerts
//              - HD44780 16x2 Character LCD automatically cycles screens every 2.0s:
//                  Screen 0: MQ2 Gas Status
//                  Screen 1: MQ7 CO Status
//                  Screen 2: DHT11 Climate (Temp & Humidity)
//              - Real-time 7-segment displays for temperature and humidity readout
//              - Serial UART logging at 115200 baud
// Standard: IEEE 1364-2001 Verilog
// ============================================================================

`timescale 1ns / 1ps

module fire_gas_top #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter TEMP_THRESH_C = 35,
    parameter ACTIVE_LOW_DO = 1,
    parameter BAUD_RATE     = 115_200,
    parameter SIM_SPEEDUP   = 0
)(
    // Clocks and User Controls
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // KEY[0]=Reset/Acknowledge (Active Low)
    input  wire [17:0] SW,         // SW[0]=Synth Mode, SW[1]=Inject Alert Temp

    // External Sensor Interface on JP5 Header
    input  wire        GPIO_0,     // MQ-2 DO (JP5 Pin 1 / PIN_AB22)
    input  wire        GPIO_1,     // MQ-7 DO (JP5 Pin 3 / PIN_AC15)
    output wire        GPIO_3,     // Auxiliary / Buzzer / Indicator
    output wire        GPIO_5,     // Auxiliary / Indicator
    inout  wire        GPIO_7,     // DHT11 1-Wire Data (JP5 Pin 15 / PIN_AE16)

    // 7-Segment Displays
    output wire [6:0]  HEX0,       // Active Screen Index
    output wire [6:0]  HEX1,       // Dash
    output wire [6:0]  HEX2,       // Humidity Ones
    output wire [6:0]  HEX3,       // Humidity Tens
    output wire [6:0]  HEX4,       // Temp °C Ones
    output wire [6:0]  HEX5,       // Temp °C Tens
    output wire [6:0]  HEX6,       // Dash
    output wire [6:0]  HEX7,       // Alert Status Indicator

    // LED Status Indicators
    output wire [8:0]  LEDG,       // [0]=MQ2 Alert, [1]=MQ7 Alert, [2]=Temp Alert
    output wire [17:0] LEDR,       // Raw sensor states and system status

    // 16x2 HD44780 Character LCD
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
    // 1. Reset Synchronization
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 2. Debounce Modules for MQ2_DO and MQ7_DO
    // ------------------------------------------------------------------------
    wire mq2_debounced;
    wire mq7_debounced;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW_DO)
    ) u_db_mq2 (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(GPIO_0),
        .debounced_state(mq2_debounced),
        .pressed_pulse(),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIM_SPEEDUP ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW_DO)
    ) u_db_mq7 (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(GPIO_1),
        .debounced_state(mq7_debounced),
        .pressed_pulse(),
        .released_pulse()
    );

    // ------------------------------------------------------------------------
    // 3. Periodic Trigger for DHT11 Sampling (Every ~2.0 seconds)
    // ------------------------------------------------------------------------
    localparam integer DHT_READ_CYCLES = (SIM_SPEEDUP) ? 1_000 : (CLK_FREQ_HZ * 2);
    reg [$clog2(DHT_READ_CYCLES):0] dht_trig_cnt;
    reg dht_start_pulse;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            dht_trig_cnt    <= 0;
            dht_start_pulse <= 1'b0;
        end else begin
            if (dht_trig_cnt >= DHT_READ_CYCLES - 1) begin
                dht_trig_cnt    <= 0;
                dht_start_pulse <= 1'b1;
            end else begin
                dht_trig_cnt    <= dht_trig_cnt + 1'b1;
                dht_start_pulse <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 4. DHT11 1-Wire Controller
    // ------------------------------------------------------------------------
    wire [7:0] dht_hum_int;
    wire [7:0] dht_temp_int;
    wire       dht_valid;
    wire       dht_busy;

    dht11_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SIM_SPEEDUP(SIM_SPEEDUP)
    ) u_dht11 (
        .clk(CLOCK_50),
        .rst_n(!rst),
        .start_read_pulse(dht_start_pulse),
        .synth_mode_en(SW[0]),              // SW[0] activates synthetic bench mode
        .synth_temp(SW[1] ? 8'd42 : 8'd27), // SW[1] injects 42°C (alert) vs 27°C
        .synth_hum(8'd55),
        .synth_fault_inject(1'b0),
        .dht11_data_io(GPIO_7),
        .humidity_int(dht_hum_int),
        .temperature_int(dht_temp_int),
        .data_valid(dht_valid),
        .checksum_error(),
        .timeout_error(),
        .busy(dht_busy)
    );

    // Latched Temperature and Humidity Registers
    reg [7:0] live_temp, live_hum;
    always @(posedge CLOCK_50 or posedge rst) begin
        if (rst) begin
            live_temp <= 8'd25; // Default ambient room temp
            live_hum  <= 8'd50; // Default ambient humidity
        end else if (dht_valid) begin
            live_temp <= dht_temp_int;
            live_hum  <= dht_hum_int;
        end
    end

    // ------------------------------------------------------------------------
    // 5. Independent Threshold Alert Evaluation
    // ------------------------------------------------------------------------
    wire mq2_alert  = mq2_debounced;
    wire mq7_alert  = mq7_debounced;
    wire temp_alert = (live_temp > TEMP_THRESH_C);
    wire any_alert  = mq2_alert | mq7_alert | temp_alert;

    // Direct LED alerts per spec:
    assign LEDG[0] = mq2_alert;
    assign LEDG[1] = mq7_alert;
    assign LEDG[2] = temp_alert;
    assign LEDG[8:3] = 6'b0;

    // Red LEDs for visual debug feedback
    assign LEDR[0]  = GPIO_0;           // Raw MQ2 input pin
    assign LEDR[1]  = GPIO_1;           // Raw MQ7 input pin
    assign LEDR[2]  = mq2_debounced;
    assign LEDR[3]  = mq7_debounced;
    assign LEDR[4]  = temp_alert;
    assign LEDR[16:5] = 12'b0;
    assign LEDR[17] = SW[0];            // Synth mode indicator

    // Auxiliary outputs
    assign GPIO_3 = any_alert;          // Alarm/Buzzer line high when any alert is active
    assign GPIO_5 = 1'b0;

    // ------------------------------------------------------------------------
    // 6. LCD Display Cycling FSM (Cycles screens every 2.0s)
    // ------------------------------------------------------------------------
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire [1:0]   current_screen;

    gas_lcd_cycler #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .CYCLE_SEC(2),
        .SIMULATION(SIM_SPEEDUP)
    ) u_cycler (
        .clk(CLOCK_50),
        .rst(rst),
        .mq2_alert(mq2_alert),
        .mq7_alert(mq7_alert),
        .temp_alert(temp_alert),
        .temperature_val(live_temp),
        .humidity_val(live_hum),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .current_screen(current_screen)
    );

    // ------------------------------------------------------------------------
    // 7. HD44780 16x2 Character LCD Driver
    // ------------------------------------------------------------------------
    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk(CLOCK_50),
        .rst(rst),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .refresh_strobe(1'b0),
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // ------------------------------------------------------------------------
    // 8. Seven-Segment Displays
    // ------------------------------------------------------------------------
    // HEX0: Current Screen Index (0, 1, 2)
    seven_seg_dec u_hex0 (
        .dec_digit({2'b00, current_screen}),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX0)
    );

    // HEX1: Dash
    seven_seg_dec u_hex1 (
        .dec_digit(4'd0),
        .blank(1'b0),
        .show_dash(1'b1),
        .seg_out(HEX1)
    );

    // HEX2..3: Live Humidity (00-99%)
    seven_seg_dec u_hex2 (
        .dec_digit(live_hum % 10),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX2)
    );
    seven_seg_dec u_hex3 (
        .dec_digit(live_hum / 10),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX3)
    );

    // HEX4..5: Live Temperature (00-99°C)
    seven_seg_dec u_hex4 (
        .dec_digit(live_temp % 10),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX4)
    );
    seven_seg_dec u_hex5 (
        .dec_digit(live_temp / 10),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX5)
    );

    // HEX6: Dash
    seven_seg_dec u_hex6 (
        .dec_digit(4'd0),
        .blank(1'b0),
        .show_dash(1'b1),
        .seg_out(HEX6)
    );

    // HEX7: Alert status indicator (8 if any alert, blank if normal)
    seven_seg_dec u_hex7 (
        .dec_digit(4'd8),
        .blank(!any_alert),
        .show_dash(1'b0),
        .seg_out(HEX7)
    );

    // ------------------------------------------------------------------------
    // 9. UART Telemetry Logger (115200 baud)
    // ------------------------------------------------------------------------
    fire_gas_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_log (
        .clk(CLOCK_50),
        .rst_n(!rst),
        .trigger_tx(dht_valid),
        .gas_pct(mq2_alert ? 7'd99 : 7'd12),
        .temp_c(live_temp[6:0]),
        .flame_pct(mq7_alert ? 7'd99 : 7'd8),
        .hum_pct(live_hum[6:0]),
        .risk_score(any_alert ? 7'd85 : 7'd10),
        .risk_level(any_alert ? 2'b10 : 2'b00),
        .fault_code(5'b00000),
        .uart_txd(UART_TXD),
        .tx_busy()
    );

endmodule
