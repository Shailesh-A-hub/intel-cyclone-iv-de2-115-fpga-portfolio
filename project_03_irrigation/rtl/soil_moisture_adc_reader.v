// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   soil_moisture_adc_reader.v
// Description: Soil moisture sensor interface using external MCP3008 SPI ADC.
//              Converts 10-bit raw analog reading into a calibrated soil moisture
//              percentage (0 - 100%). Detects open/short sensor fault conditions.
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module soil_moisture_adc_reader #(
    parameter CLK_FREQ_HZ    = 50_000_000,
    parameter SPI_CLK_HZ     = 1_000_000,
    parameter SAMPLE_RATE_HZ = 10
)(
    input  wire        clk,
    input  wire        rst_n,

    // Synthetic Test Mode
    input  wire        synth_mode_en,
    input  wire [9:0]  synth_soil_adc,
    input  wire        synth_fault_inject,

    // Physical SPI Interface to MCP3008 ADC (Channel 0)
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Decoded Moisture Outputs
    output reg  [6:0]  moisture_percent,   // 0 to 100 %
    output reg  [9:0]  raw_adc_out,        // 0 to 1023
    output reg         moisture_valid,
    output reg         sensor_fault
);

    // ------------------------------------------------------------------------
    // Periodic Sample Interval Timer
    // ------------------------------------------------------------------------
    localparam SAMPLE_INTERVAL = CLK_FREQ_HZ / SAMPLE_RATE_HZ;
    reg [$clog2(SAMPLE_INTERVAL):0] timer_cnt;
    wire start_sample = (timer_cnt == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_cnt <= 0;
        end else begin
            if (timer_cnt >= SAMPLE_INTERVAL - 1)
                timer_cnt <= 0;
            else
                timer_cnt <= timer_cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // SPI Master Instance
    // ------------------------------------------------------------------------
    reg        spi_start;
    reg  [7:0] spi_tx_data;
    wire [7:0] spi_rx_data;
    wire       spi_busy;
    wire       spi_done;

    spi_master #(
        .DATA_WIDTH (8),
        .CPOL       (0),
        .CPHA       (0),
        .CLK_DIV    (CLK_FREQ_HZ / SPI_CLK_HZ)
    ) u_spi (
        .clk        (clk),
        .rst        (~rst_n),
        .start      (spi_start),
        .tx_data    (spi_tx_data),
        .rx_data    (spi_rx_data),
        .busy       (spi_busy),
        .done       (spi_done),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   ()            // Managed explicitly by FSM
    );

    reg cs_n_reg;
    assign spi_cs_n = cs_n_reg;

    // ------------------------------------------------------------------------
    // SPI Sequencer FSM
    // ------------------------------------------------------------------------
    localparam [2:0]
        ST_IDLE       = 3'd0,
        ST_CS_ASSERT  = 3'd1,
        ST_BYTE0_SEND = 3'd2,
        ST_BYTE0_WAIT = 3'd3,
        ST_BYTE1_SEND = 3'd4,
        ST_BYTE1_WAIT = 3'd5,
        ST_BYTE2_SEND = 3'd6,
        ST_BYTE2_WAIT = 3'd7;

    reg [2:0]  state;
    reg [7:0]  rx_byte1;
    reg [7:0]  rx_byte2;
    reg [9:0]  captured_raw;
    reg        conv_done_strobe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            cs_n_reg         <= 1'b1;
            spi_start        <= 1'b0;
            spi_tx_data      <= 8'h00;
            rx_byte1         <= 8'h00;
            rx_byte2         <= 8'h00;
            captured_raw     <= 10'd500;
            conv_done_strobe <= 1'b0;
        end else begin
            spi_start        <= 1'b0;
            conv_done_strobe <= 1'b0;

            if (synth_mode_en) begin
                cs_n_reg     <= 1'b1;
                captured_raw <= synth_soil_adc;
                if (start_sample) conv_done_strobe <= 1'b1;
                state        <= ST_IDLE;
            end else begin
                case (state)
                    ST_IDLE: begin
                        cs_n_reg <= 1'b1;
                        if (start_sample) begin
                            state <= ST_CS_ASSERT;
                        end
                    end

                    ST_CS_ASSERT: begin
                        cs_n_reg <= 1'b0;
                        state    <= ST_BYTE0_SEND;
                    end

                    // Byte 0: Start bit 0x01
                    ST_BYTE0_SEND: begin
                        spi_tx_data <= 8'h01;
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE0_WAIT;
                    end

                    ST_BYTE0_WAIT: begin
                        if (spi_done) state <= ST_BYTE1_SEND;
                    end

                    // Byte 1: Single-ended Mode (1) + CH0 (000) -> 8'b1000_0000 = 0x80
                    ST_BYTE1_SEND: begin
                        spi_tx_data <= 8'h80;
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE1_WAIT;
                    end

                    ST_BYTE1_WAIT: begin
                        if (spi_done) begin
                            rx_byte1 <= spi_rx_data; // bits [1:0] are B9, B8
                            state    <= ST_BYTE2_SEND;
                        end
                    end

                    // Byte 2: Clock out remaining 8 bits
                    ST_BYTE2_SEND: begin
                        spi_tx_data <= 8'h00;
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE2_WAIT;
                    end

                    ST_BYTE2_WAIT: begin
                        if (spi_done) begin
                            cs_n_reg         <= 1'b1;
                            captured_raw     <= {rx_byte1[1:0], spi_rx_data};
                            conv_done_strobe <= 1'b1;
                            state            <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Moisture Percentage Conversion & Fault Check
    // Capacitive moisture sensor:
    // Raw >= 1000: bone dry (0%)
    // Raw <= 250:  water immersed (100%)
    // Linear scaling: (1000 - raw) * 100 / 750
    // ------------------------------------------------------------------------
    wire [17:0] num_diff = (captured_raw >= 10'd1000) ? 18'd0 : (18'd1000 - {8'd0, captured_raw});
    wire [17:0] calc_pct = (num_diff * 18'd100 + 18'd375) / 18'd750;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            moisture_percent <= 7'd50;
            raw_adc_out      <= 10'd500;
            moisture_valid   <= 1'b0;
            sensor_fault     <= 1'b0;
        end else begin
            moisture_valid <= conv_done_strobe;

            if (conv_done_strobe) begin
                raw_adc_out <= captured_raw;

                // Fault: Open/short circuit or synthetic fault
                if (synth_fault_inject || captured_raw < 10'd10 || captured_raw >= 10'd1020) begin
                    sensor_fault <= 1'b1;
                end else begin
                    sensor_fault <= 1'b0;
                end

                // Clamping percentage to 0 - 100
                if (calc_pct > 18'd100)
                    moisture_percent <= 7'd100;
                else
                    moisture_percent <= calc_pct[6:0];
            end
        end
    end

endmodule
