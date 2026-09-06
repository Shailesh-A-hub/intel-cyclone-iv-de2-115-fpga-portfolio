// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   mcp3008_adc_controller.v
// Description: Periodic multi-channel SPI ADC controller for MCP3008 (10-bit).
//              Sequentially reads 4 analog channels:
//                Channel 0: Combustible Gas Sensor (MQ-2 / MQ-5 / MQ-7)
//                Channel 1: Ambient Temperature Sensor (LM35 / TMP36)
//                Channel 2: Optical IR Flame Sensor
//                Channel 3: Relative Humidity Sensor
//              Includes synthetic override mode for hardware testing without
//              physical analog daughterboard attached.
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module mcp3008_adc_controller #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter SPI_CLK_HZ    = 1_000_000,   // 1 MHz SPI Clock (MCP3008 max ~3.6 MHz at 5V, 1.35 MHz at 2.7V)
    parameter SAMPLE_RATE_HZ= 10           // 10 Hz round-robin scan rate
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control & Synthetic Mode
    input  wire        synth_mode_en,       // 1 = Override with synthetic inputs
    input  wire [9:0]  synth_gas_adc,
    input  wire [9:0]  synth_temp_adc,
    input  wire [9:0]  synth_flame_adc,
    input  wire [9:0]  synth_hum_adc,
    input  wire        synth_comm_fault,    // 1 = Inject SPI disconnection fault

    // Physical SPI Interface to MCP3008
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // Captured ADC Channel Outputs (10-bit Unsigned, 0 - 1023)
    output reg  [9:0]  adc_ch0_gas,
    output reg  [9:0]  adc_ch1_temp,
    output reg  [9:0]  adc_ch2_flame,
    output reg  [9:0]  adc_ch3_hum,
    output reg         adc_data_valid,
    output reg         adc_comm_fault
);

    // ------------------------------------------------------------------------
    // Timing & Trigger Generator
    // ------------------------------------------------------------------------
    localparam SAMPLE_INTERVAL = CLK_FREQ_HZ / SAMPLE_RATE_HZ;
    reg [$clog2(SAMPLE_INTERVAL):0] sample_timer;
    wire start_scan = (sample_timer == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_timer <= 0;
        end else begin
            if (sample_timer >= SAMPLE_INTERVAL - 1)
                sample_timer <= 0;
            else
                sample_timer <= sample_timer + 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // SPI Master Instantiation
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
        .spi_cs_n   ()            // Managed explicitly by FSM for 3-byte burst
    );

    // Explicit CS_N control
    reg cs_n_reg;
    assign spi_cs_n = cs_n_reg;

    // ------------------------------------------------------------------------
    // State Machine Definitions
    // ------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_CS_ASSERT  = 4'd1,
        ST_BYTE0_SEND = 4'd2,
        ST_BYTE0_WAIT = 4'd3,
        ST_BYTE1_SEND = 4'd4,
        ST_BYTE1_WAIT = 4'd5,
        ST_BYTE2_SEND = 4'd6,
        ST_BYTE2_WAIT = 4'd7,
        ST_CS_DEASSERT= 4'd8,
        ST_NEXT_CH    = 4'd9,
        ST_FINISH     = 4'd10;

    reg [3:0] state;
    reg [1:0] curr_ch;
    reg [7:0] rx_byte1;
    reg [7:0] rx_byte2;
    reg [15:0] timeout_cnt;

    localparam TIMEOUT_LIMIT = (CLK_FREQ_HZ / 1_000) * 10; // 10 ms communication watchdog

    // Temporary registers for captured channels during multi-channel burst
    reg [9:0] temp_ch0;
    reg [9:0] temp_ch1;
    reg [9:0] temp_ch2;
    reg [9:0] temp_ch3;

    // ------------------------------------------------------------------------
    // State Machine
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            curr_ch        <= 2'd0;
            cs_n_reg       <= 1'b1;
            spi_start      <= 1'b0;
            spi_tx_data    <= 8'h00;
            rx_byte1       <= 8'h00;
            rx_byte2       <= 8'h00;
            temp_ch0       <= 10'd0;
            temp_ch1       <= 10'd0;
            temp_ch2       <= 10'd0;
            temp_ch3       <= 10'd0;
            adc_ch0_gas    <= 10'd0;
            adc_ch1_temp   <= 10'd0;
            adc_ch2_flame  <= 10'd0;
            adc_ch3_hum    <= 10'd0;
            adc_data_valid <= 1'b0;
            adc_comm_fault <= 1'b0;
            timeout_cnt    <= 16'd0;
        end else begin
            spi_start      <= 1'b0;
            adc_data_valid <= 1'b0;

            if (synth_mode_en) begin
                // In synthetic mode, route synthetic signals directly
                adc_ch0_gas    <= synth_gas_adc;
                adc_ch1_temp   <= synth_temp_adc;
                adc_ch2_flame  <= synth_flame_adc;
                adc_ch3_hum    <= synth_hum_adc;
                adc_comm_fault <= synth_comm_fault;
                if (start_scan) begin
                    adc_data_valid <= 1'b1;
                end
                cs_n_reg       <= 1'b1;
                state          <= ST_IDLE;
            end else begin
                // Physical SPI scanning mode
                case (state)
                    ST_IDLE: begin
                        cs_n_reg    <= 1'b1;
                        timeout_cnt <= 16'd0;
                        if (start_scan) begin
                            curr_ch  <= 2'd0;
                            state    <= ST_CS_ASSERT;
                        end
                    end

                    ST_CS_ASSERT: begin
                        cs_n_reg    <= 1'b0; // Assert CS#
                        state       <= ST_BYTE0_SEND;
                    end

                    // Byte 0: Start Bit = 0x01
                    ST_BYTE0_SEND: begin
                        spi_tx_data <= 8'h01;
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE0_WAIT;
                        timeout_cnt <= 16'd0;
                    end

                    ST_BYTE0_WAIT: begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                        if (timeout_cnt > TIMEOUT_LIMIT) begin
                            adc_comm_fault <= 1'b1;
                            cs_n_reg       <= 1'b1;
                            state          <= ST_IDLE;
                        end else if (spi_done) begin
                            state <= ST_BYTE1_SEND;
                        end
                    end

                    // Byte 1: Single-Ended bit (1) + Channel (curr_ch[1:0]) in bits [6:4]
                    ST_BYTE1_SEND: begin
                        // MCP3008 format: {1'b1 (Single/Diff), curr_ch[2:0], 4'b0000}
                        spi_tx_data <= {1'b1, 1'b0, curr_ch, 4'b0000};
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE1_WAIT;
                        timeout_cnt <= 16'd0;
                    end

                    ST_BYTE1_WAIT: begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                        if (timeout_cnt > TIMEOUT_LIMIT) begin
                            adc_comm_fault <= 1'b1;
                            cs_n_reg       <= 1'b1;
                            state          <= ST_IDLE;
                        end else if (spi_done) begin
                            rx_byte1 <= spi_rx_data; // bits [1:0] are B9, B8
                            state    <= ST_BYTE2_SEND;
                        end
                    end

                    // Byte 2: Clock out remaining 8 bits (B7..B0)
                    ST_BYTE2_SEND: begin
                        spi_tx_data <= 8'h00;
                        spi_start   <= 1'b1;
                        state       <= ST_BYTE2_WAIT;
                        timeout_cnt <= 16'd0;
                    end

                    ST_BYTE2_WAIT: begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                        if (timeout_cnt > TIMEOUT_LIMIT) begin
                            adc_comm_fault <= 1'b1;
                            cs_n_reg       <= 1'b1;
                            state          <= ST_IDLE;
                        end else if (spi_done) begin
                            rx_byte2 <= spi_rx_data; // bits [7:0] are B7..B0
                            state    <= ST_CS_DEASSERT;
                        end
                    end

                    ST_CS_DEASSERT: begin
                        cs_n_reg <= 1'b1; // Deassert CS#

                        // Store 10-bit reading into corresponding temp buffer
                        case (curr_ch)
                            2'd0: temp_ch0 <= {rx_byte1[1:0], rx_byte2};
                            2'd1: temp_ch1 <= {rx_byte1[1:0], rx_byte2};
                            2'd2: temp_ch2 <= {rx_byte1[1:0], rx_byte2};
                            2'd3: temp_ch3 <= {rx_byte1[1:0], rx_byte2};
                        endcase
                        state <= ST_NEXT_CH;
                    end

                    ST_NEXT_CH: begin
                        if (curr_ch == 2'd3) begin
                            state <= ST_FINISH;
                        end else begin
                            curr_ch <= curr_ch + 1'b1;
                            state   <= ST_CS_ASSERT;
                        end
                    end

                    ST_FINISH: begin
                        adc_ch0_gas    <= temp_ch0;
                        adc_ch1_temp   <= temp_ch1;
                        adc_ch2_flame  <= temp_ch2;
                        adc_ch3_hum    <= temp_ch3;
                        adc_data_valid <= 1'b1;
                        adc_comm_fault <= 1'b0;
                        state          <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
