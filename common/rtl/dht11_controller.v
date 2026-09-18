// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   dht11_controller.v
// Description: Dedicated microsecond-resolution state-machine driver for DHT11 /
//              DHT22 single-wire bidirectional temperature and humidity sensors.
//              Handles:
//                - 18ms low start pulse generation
//                - Tri-state line release and response pulse detection
//                - 40-bit data stream capture with pulse-width timing
//                - Checksum calculation: (Byte0 + Byte1 + Byte2 + Byte3) == Byte4
//                - Timeout watchdog and communication fault diagnostics
//                - Synthetic test mode override
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module dht11_controller #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter SIM_SPEEDUP = 0
)(
    input  wire        clk,
    input  wire        rst_n,

    // Periodic Read Trigger
    input  wire        start_read_pulse,

    // Synthetic Test Mode
    input  wire        synth_mode_en,
    input  wire [7:0]  synth_temp,
    input  wire [7:0]  synth_hum,
    input  wire        synth_fault_inject,

    // Physical Bidirectional Single-Wire Pin
    inout  wire        dht11_data_io,

    // Decoded Engineering Outputs
    output reg  [7:0]  humidity_int,      // 0 to 99 % RH
    output reg  [7:0]  temperature_int,   // 0 to 99 °C
    output reg         data_valid,
    output reg         checksum_error,
    output reg         timeout_error,
    output reg         busy
);

    // ------------------------------------------------------------------------
    // Microsecond Tick Generator (50 MHz / 1,000,000 = 50 clock cycles)
    // ------------------------------------------------------------------------
    localparam US_CYCLES = (SIM_SPEEDUP) ? 5 : (CLK_FREQ_HZ / 1_000_000);
    reg [$clog2(US_CYCLES):0] us_div_cnt;
    reg us_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            us_div_cnt <= 0;
            us_tick    <= 1'b0;
        end else begin
            if (us_div_cnt >= US_CYCLES - 1) begin
                us_div_cnt <= 0;
                us_tick    <= 1'b1;
            end else begin
                us_div_cnt <= us_div_cnt + 1'b1;
                us_tick    <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Bidirectional IO Pin Control & Synchronizer
    // ------------------------------------------------------------------------
    reg dht_drive_low; // 1 = pull low, 0 = release to high-Z (tri-state)
    assign dht11_data_io = (dht_drive_low) ? 1'b0 : 1'bz;

    reg dht_in_s1, dht_in_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dht_in_s1 <= 1'b1;
            dht_in_s2 <= 1'b1;
        end else begin
            dht_in_s1 <= dht11_data_io;
            dht_in_s2 <= dht_in_s1;
        end
    end
    wire dht_line_in = dht_in_s2;

    // Edge detectors on synchronized input line
    reg dht_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dht_prev <= 1'b1;
        else        dht_prev <= dht_line_in;
    end
    wire dht_falling = (dht_prev == 1'b1 && dht_line_in == 1'b0);
    wire dht_rising  = (dht_prev == 1'b0 && dht_line_in == 1'b1);

    // ------------------------------------------------------------------------
    // State Machine Definitions
    // ------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE              = 4'd0,
        ST_START_PULL_LOW    = 4'd1,  // Pull LOW for 18 ms
        ST_START_RELEASE     = 4'd2,  // Release for 20-40 us
        ST_WAIT_RESP_LOW     = 4'd3,  // Wait for DHT11 response pull LOW
        ST_RESP_LOW          = 4'd4,  // DHT11 pulls LOW for 80 us
        ST_RESP_HIGH         = 4'd5,  // DHT11 pulls HIGH for 80 us
        ST_BIT_START_LOW     = 4'd6,  // Each bit starts with 50 us LOW
        ST_BIT_MEASURE_HIGH  = 4'd7,  // High duration: 26-28us = '0', 70us = '1'
        ST_EVAL_CHECKSUM     = 4'd8,  // Verify 8-bit checksum
        ST_DONE              = 4'd9;

    reg [3:0]  state;
    reg [15:0] us_timer;
    reg [5:0]  bit_index;      // 0 to 39 bits
    reg [39:0] shift_data;

    // Timing Constants in Microseconds
    localparam START_LOW_US = (SIM_SPEEDUP) ? 180 : 18000; // 18 ms
    localparam TIMEOUT_US   = 200; // 200 us timeout for edge detection

    // ------------------------------------------------------------------------
    // FSM Execution
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            us_timer        <= 16'd0;
            bit_index       <= 6'd0;
            shift_data      <= 40'd0;
            dht_drive_low   <= 1'b0;
            humidity_int    <= 8'd50; // Default nominal 50%
            temperature_int <= 8'd25; // Default nominal 25°C
            data_valid      <= 1'b0;
            checksum_error  <= 1'b0;
            timeout_error   <= 1'b0;
            busy            <= 1'b0;
        end else begin
            data_valid <= 1'b0; // Default 1-cycle pulse

            if (synth_mode_en) begin
                // In synthetic mode, bypass physical 1-wire timing
                dht_drive_low   <= 1'b0;
                busy            <= 1'b0;
                humidity_int    <= synth_hum;
                temperature_int <= synth_temp;
                checksum_error  <= synth_fault_inject;
                timeout_error   <= 1'b0;
                if (start_read_pulse) begin
                    data_valid <= ~synth_fault_inject;
                end
                state <= ST_IDLE;
            end else begin
                // Physical 1-Wire Protocol FSM
                case (state)
                    ST_IDLE: begin
                        dht_drive_low <= 1'b0; // Line released (high-Z)
                        busy          <= 1'b0;
                        us_timer      <= 16'd0;
                        bit_index     <= 6'd0;
                        if (start_read_pulse) begin
                            busy          <= 1'b1;
                            dht_drive_low <= 1'b1; // Assert start signal LOW
                            state         <= ST_START_PULL_LOW;
                        end
                    end

                    // Drive line LOW for 18 ms
                    ST_START_PULL_LOW: begin
                        if (us_tick) begin
                            if (us_timer >= START_LOW_US - 1) begin
                                us_timer      <= 16'd0;
                                dht_drive_low <= 1'b0; // Release line
                                state         <= ST_START_RELEASE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // Release for 20-40 us while DHT11 prepares response
                    ST_START_RELEASE: begin
                        if (dht_falling) begin
                            us_timer <= 16'd0;
                            state    <= ST_RESP_LOW;
                        end else if (us_tick) begin
                            if (us_timer >= TIMEOUT_US) begin
                                timeout_error <= 1'b1;
                                state         <= ST_IDLE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // DHT11 pulls line LOW for ~80 us
                    ST_RESP_LOW: begin
                        if (dht_rising) begin
                            us_timer <= 16'd0;
                            state    <= ST_RESP_HIGH;
                        end else if (us_tick) begin
                            if (us_timer >= TIMEOUT_US) begin
                                timeout_error <= 1'b1;
                                state         <= ST_IDLE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // DHT11 pulls line HIGH for ~80 us
                    ST_RESP_HIGH: begin
                        if (dht_falling) begin
                            us_timer  <= 16'd0;
                            bit_index <= 6'd0;
                            state     <= ST_BIT_START_LOW;
                        end else if (us_tick) begin
                            if (us_timer >= TIMEOUT_US) begin
                                timeout_error <= 1'b1;
                                state         <= ST_IDLE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // Each bit starts with a 50 us LOW pulse
                    ST_BIT_START_LOW: begin
                        if (dht_rising) begin
                            us_timer <= 16'd0; // Begin measuring high-level duration
                            state    <= ST_BIT_MEASURE_HIGH;
                        end else if (us_tick) begin
                            if (us_timer >= TIMEOUT_US) begin
                                timeout_error <= 1'b1;
                                state         <= ST_IDLE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // Measure HIGH duration: 26-28 us = '0', 70 us = '1'
                    ST_BIT_MEASURE_HIGH: begin
                        if (dht_falling) begin
                            // Threshold at 45 us: <45us is '0', >=45us is '1'
                            if (us_timer >= 16'd45)
                                shift_data <= {shift_data[38:0], 1'b1};
                            else
                                shift_data <= {shift_data[38:0], 1'b0};

                            us_timer <= 16'd0;
                            if (bit_index >= 6'd39) begin
                                state <= ST_EVAL_CHECKSUM;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                                state     <= ST_BIT_START_LOW;
                            end
                        end else if (us_tick) begin
                            if (us_timer >= TIMEOUT_US) begin
                                timeout_error <= 1'b1;
                                state         <= ST_IDLE;
                            end else begin
                                us_timer <= us_timer + 1'b1;
                            end
                        end
                    end

                    // Checksum: lower 8 bits of (Byte0 + Byte1 + Byte2 + Byte3) == Byte4
                    ST_EVAL_CHECKSUM: begin
                        if (((shift_data[39:32] + shift_data[31:24] + shift_data[23:16] + shift_data[15:8]) & 8'hFF) == shift_data[7:0]) begin
                            humidity_int    <= shift_data[39:32];
                            temperature_int <= shift_data[23:16];
                            checksum_error  <= 1'b0;
                            timeout_error   <= 1'b0;
                            data_valid      <= 1'b1;
                        end else begin
                            checksum_error <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
