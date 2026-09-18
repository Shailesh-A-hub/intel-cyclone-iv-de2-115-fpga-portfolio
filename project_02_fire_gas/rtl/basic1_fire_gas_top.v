//=============================================================================
// Module: basic1_fire_gas_top
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
//              - HD44780 16x2 Character LCD automatically cycles screens every 2.0s
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module basic1_fire_gas_top #(
    parameter integer CLK_FREQ_HZ    = 50_000_000,
    parameter integer TEMP_THRESH_C  = 35,          // High temperature threshold in °C
    parameter integer ACTIVE_LOW_DO  = 1,           // Most comparator DO pins pull LOW on alert
    parameter integer SIMULATION     = 0
)(
    // System Clock and Master Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0] = Reset / Acknowledge (active low)
    input  wire [17:0] SW,              // SW[0] = Synthetic test mode enable

    // Sensor Inputs (GPIO Header JP5 / GPIO_0)
    input  wire        MQ2_DO,          // JP5 Pin 5 (or GPIO_0[4] / GPIO_0[0])
    input  wire        MQ7_DO,          // JP5 Pin 6 (or GPIO_0[5] / GPIO_0[1])
    inout  wire        DHT11_DATA,      // JP5 Pin 15 (GPIO_0[14])

    // Green LEDs
    output wire [2:0]  LEDG,            // [0]=MQ2 Alert, [1]=MQ7 Alert, [2]=Temp Alert

    // HD44780 16x2 Character LCD
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_EN,
    output wire        LCD_RW,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    // 1. Synchronized Active-High Reset (rst = 1 when KEY[0] is pressed)
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

    // 2. Debounce Modules for MQ2_DO and MQ7_DO
    wire mq2_debounced;
    wire mq7_debounced;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW_DO)
    ) u_db_mq2 (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(MQ2_DO),
        .debounced_state(mq2_debounced),
        .pressed_pulse(),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW_DO)
    ) u_db_mq7 (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(MQ7_DO),
        .debounced_state(mq7_debounced),
        .pressed_pulse(),
        .released_pulse()
    );

    // 3. Periodic Trigger for DHT11 Sampling (Every 1.5 - 2.0 seconds)
    localparam integer DHT_READ_CYCLES = (SIMULATION) ? 1_000 : (CLK_FREQ_HZ * 2);
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

    // 4. DHT11 1-Wire Controller
    wire [7:0] dht_hum_int;
    wire [7:0] dht_temp_int;
    wire       dht_valid;
    wire       dht_busy;

    dht11_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SIM_SPEEDUP(SIMULATION)
    ) u_dht11 (
        .clk(CLOCK_50),
        .rst_n(!rst),
        .start_read_pulse(dht_start_pulse),
        .synth_mode_en(SW[0]),          // SW[0] activates synthetic test values
        .synth_temp(SW[1] ? 8'd42 : 8'd27), // SW[1]=1 injects 42°C (alert), SW[1]=0 27°C
        .synth_hum(8'd55),
        .synth_fault_inject(1'b0),
        .dht11_data_io(DHT11_DATA),
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

    // 5. Independent Threshold Alert Evaluation
    wire mq2_alert  = mq2_debounced;
    wire mq7_alert  = mq7_debounced;
    wire temp_alert = (live_temp > TEMP_THRESH_C);

    assign LEDG[0] = mq2_alert;
    assign LEDG[1] = mq7_alert;
    assign LEDG[2] = temp_alert;

    // 6. LCD Display Cycling FSM (Cycles screens every 2 seconds)
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;

    gas_lcd_cycler #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .CYCLE_SEC(2),
        .SIMULATION(SIMULATION)
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
        .current_screen()
    );

    // 7. HD44780 16x2 Character LCD Driver
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

endmodule
