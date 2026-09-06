// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   sensor_normalizer.v
// Description: Pipelined sensor normalization and hardware fault detector.
//              Converts raw 10-bit ADC values (0 - 1023) into normalized
//              8-bit dynamic range values (0 - 255) for:
//                - Combustible gas (MQ series)
//                - Ambient temperature
//                - Optical flame intensity
//                - Relative humidity
//              Identifies open-circuit, short-circuit, and rail-saturation faults.
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module sensor_normalizer (
    input  wire        clk,
    input  wire        rst_n,

    // Raw ADC Data Inputs
    input  wire        adc_valid_in,
    input  wire [9:0]  raw_gas,
    input  wire [9:0]  raw_temp,
    input  wire [9:0]  raw_flame,
    input  wire [9:0]  raw_hum,
    input  wire        adc_comm_fault_in,

    // Normalized Sensor Outputs (0 - 255 dynamic range)
    output reg  [7:0]  norm_gas,
    output reg  [7:0]  norm_temp,
    output reg  [7:0]  norm_flame,
    output reg  [7:0]  norm_hum,

    // Engineering Units for Display / Telemetry
    output reg  [6:0]  temp_celsius,      // 0 to 99 °C
    output reg  [6:0]  gas_percent,       // 0 to 99 %
    output reg  [6:0]  flame_percent,     // 0 to 99 %
    output reg  [6:0]  hum_percent,       // 0 to 99 %

    // Fault Status Vector
    // Bit 0: Gas Sensor Fault (Open/Short)
    // Bit 1: Temp Sensor Fault (Disconnected/Shorted)
    // Bit 2: Flame Sensor Fault (Stuck at Rail)
    // Bit 3: Humidity Sensor Fault (Stuck at Rail)
    // Bit 4: ADC SPI Communication Fault
    output reg  [4:0]  sensor_fault_mask,
    output reg         norm_valid_out
);

    // ------------------------------------------------------------------------
    // Fault Detection (Combinational pre-check)
    // ------------------------------------------------------------------------
    wire fault_gas   = (raw_gas   < 10'd5)  || (raw_gas   >= 10'd1020);
    wire fault_temp  = (raw_temp  < 10'd10) || (raw_temp  >= 10'd1010);
    wire fault_flame = (raw_flame < 10'd5)  || (raw_flame >= 10'd1020);
    wire fault_hum   = (raw_hum   < 10'd5)  || (raw_hum   >= 10'd1020);

    // ------------------------------------------------------------------------
    // Pipeline Stage 1: Difference & Baseline Clamping
    // ------------------------------------------------------------------------
    reg        stage1_valid;
    reg [4:0]  stage1_fault;
    reg [9:0]  diff_gas;
    reg [9:0]  diff_temp;
    reg [9:0]  diff_flame;
    reg [9:0]  diff_hum;

    // Engineering unit raw holders
    reg [9:0]  st1_raw_temp;
    reg [9:0]  st1_raw_gas;
    reg [9:0]  st1_raw_flame;
    reg [9:0]  st1_raw_hum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid  <= 1'b0;
            stage1_fault  <= 5'd0;
            diff_gas      <= 10'd0;
            diff_temp     <= 10'd0;
            diff_flame    <= 10'd0;
            diff_hum      <= 10'd0;
            st1_raw_temp  <= 10'd0;
            st1_raw_gas   <= 10'd0;
            st1_raw_flame <= 10'd0;
            st1_raw_hum   <= 10'd0;
        end else begin
            stage1_valid <= adc_valid_in;
            stage1_fault <= {adc_comm_fault_in, fault_hum, fault_flame, fault_temp, fault_gas};

            st1_raw_temp  <= raw_temp;
            st1_raw_gas   <= raw_gas;
            st1_raw_flame <= raw_flame;
            st1_raw_hum   <= raw_hum;

            // Gas: baseline = 100
            if (raw_gas <= 10'd100)
                diff_gas <= 10'd0;
            else
                diff_gas <= raw_gas - 10'd100;

            // Temp: baseline = 78 (~25°C)
            if (raw_temp <= 10'd78)
                diff_temp <= 10'd0;
            else
                diff_temp <= raw_temp - 10'd78;

            // Flame: inverted (1000 = dark/safe, low = fire)
            if (raw_flame >= 10'd1000)
                diff_flame <= 10'd0;
            else
                diff_flame <= 10'd1000 - raw_flame;

            // Humidity: dry air = risk (800 = humid/safe, low = dry)
            if (raw_hum >= 10'd800)
                diff_hum <= 10'd0;
            else
                diff_hum <= 10'd800 - raw_hum;
        end
    end

    // ------------------------------------------------------------------------
    // Pipeline Stage 2: Scaling and Clamping to [0, 255] and Engineering Units
    // ------------------------------------------------------------------------
    // Calculations:
    // Gas:   (diff_gas * 255 + 350) / 700
    // Temp:  (diff_temp * 255 + 77) / 155
    // Flame: (diff_flame * 255 + 425) / 850
    // Hum:   (diff_hum * 255 + 300) / 600

    wire [18:0] calc_gas   = (diff_gas   * 18'd255 + 18'd350) / 18'd700;
    wire [18:0] calc_temp  = (diff_temp  * 18'd255 + 18'd77)  / 18'd155;
    wire [18:0] calc_flame = (diff_flame * 18'd255 + 18'd425) / 18'd850;
    wire [18:0] calc_hum   = (diff_hum   * 18'd255 + 18'd300) / 18'd600;

    // Engineering units:
    // Temp in °C: raw_temp * 330 / 1024 -> raw_temp * 165 / 512
    wire [18:0] calc_temp_c = (st1_raw_temp * 18'd165) / 18'd512;
    wire [18:0] calc_gas_pct = (calc_gas * 18'd100) / 18'd255;
    wire [18:0] calc_flm_pct = (calc_flame * 18'd100) / 18'd255;
    wire [18:0] calc_hum_pct = (calc_hum * 18'd100) / 18'd255;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            norm_valid_out    <= 1'b0;
            norm_gas          <= 8'd0;
            norm_temp         <= 8'd0;
            norm_flame        <= 8'd0;
            norm_hum          <= 8'd0;
            temp_celsius      <= 7'd0;
            gas_percent       <= 7'd0;
            flame_percent     <= 7'd0;
            hum_percent       <= 7'd0;
            sensor_fault_mask <= 5'd0;
        end else begin
            norm_valid_out    <= stage1_valid;
            sensor_fault_mask <= stage1_fault;

            // Clamping normalized outputs
            norm_gas   <= (calc_gas   > 18'd255) ? 8'd255 : calc_gas[7:0];
            norm_temp  <= (calc_temp  > 18'd255) ? 8'd255 : calc_temp[7:0];
            norm_flame <= (calc_flame > 18'd255) ? 8'd255 : calc_flame[7:0];
            norm_hum   <= (calc_hum   > 18'd255) ? 8'd255 : calc_hum[7:0];

            // Clamping engineering units
            temp_celsius  <= (calc_temp_c > 18'd99) ? 7'd99 : calc_temp_c[6:0];
            gas_percent   <= (calc_gas_pct > 18'd99) ? 7'd99 : calc_gas_pct[6:0];
            flame_percent <= (calc_flm_pct > 18'd99) ? 7'd99 : calc_flm_pct[6:0];
            hum_percent   <= (calc_hum_pct > 18'd99) ? 7'd99 : calc_hum_pct[6:0];
        end
    end

endmodule
