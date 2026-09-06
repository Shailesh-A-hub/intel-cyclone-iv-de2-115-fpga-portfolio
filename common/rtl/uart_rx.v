//=============================================================================
// Module: uart_rx
// Description: Robust UART receiver with 16x oversampling, start-bit glitch
//              rejection, and framing error detection.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer DATA_BITS   = 8
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 rx_line,    // Serial physical line input
    output reg  [DATA_BITS-1:0] rx_data,    // Received byte
    output reg                  rx_valid,   // 1-cycle pulse upon valid byte arrival
    output reg                  rx_error    // 1-cycle pulse on framing/parity error
);

    // 16x oversampling clock divider
    localparam integer OVERSAMPLE_RATE   = 16;
    localparam integer OS_DIVISOR        = (CLK_FREQ_HZ > (BAUD_RATE * OVERSAMPLE_RATE)) ? 
                                           (CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE_RATE)) : 1;
    localparam integer OS_DIV_W          = (OS_DIVISOR > 1) ? $clog2(OS_DIVISOR) : 1;

    // Synchronize rx_line to eliminate metastability
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        if (rst) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_line;
            rx_sync2 <= rx_sync1;
        end
    end

    // Oversampling tick generation
    reg [OS_DIV_W-1:0] os_cnt;
    wire os_tick = (os_cnt >= OS_DIVISOR - 1);

    always @(posedge clk) begin
        if (rst) begin
            os_cnt <= {OS_DIV_W{1'b0}};
        end else begin
            if (os_tick) begin
                os_cnt <= {OS_DIV_W{1'b0}};
            end else begin
                os_cnt <= os_cnt + 1'b1;
            end
        end
    end

    // FSM State Encoding
    localparam [1:0]
        STATE_IDLE  = 2'b00,
        STATE_START = 2'b01,
        STATE_DATA  = 2'b10,
        STATE_STOP  = 2'b11;

    reg [1:0]           state;
    reg [3:0]           sample_cnt;
    reg [2:0]           bit_idx;
    reg [DATA_BITS-1:0] rx_shifter;

    always @(posedge clk) begin
        if (rst) begin
            state      <= STATE_IDLE;
            sample_cnt <= 4'd0;
            bit_idx    <= 3'd0;
            rx_shifter <= {DATA_BITS{1'b0}};
            rx_data    <= {DATA_BITS{1'b0}};
            rx_valid   <= 1'b0;
            rx_error   <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // Default pulse low
            rx_error <= 1'b0;

            if (os_tick) begin
                case (state)
                    STATE_IDLE: begin
                        sample_cnt <= 4'd0;
                        bit_idx    <= 3'd0;
                        // Detect falling edge of start bit
                        if (~rx_sync2) begin
                            state <= STATE_START;
                        end
                    end

                    STATE_START: begin
                        // Check midpoint of start bit (sample 7)
                        if (sample_cnt == 4'd7) begin
                            if (~rx_sync2) begin
                                // Valid start bit
                                sample_cnt <= 4'd0;
                                state      <= STATE_DATA;
                            end else begin
                                // Glitch rejected
                                state <= STATE_IDLE;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    STATE_DATA: begin
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            rx_shifter <= {rx_sync2, rx_shifter[DATA_BITS-1:1]};
                            if (bit_idx >= DATA_BITS - 1) begin
                                bit_idx <= 3'd0;
                                state   <= STATE_STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    STATE_STOP: begin
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            state      <= STATE_IDLE;
                            if (rx_sync2) begin
                                rx_data  <= rx_shifter;
                                rx_valid <= 1'b1; // Valid frame complete
                            end else begin
                                rx_error <= 1'b1; // Framing error (stop bit wasn't high)
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 1'b1;
                        end
                    end

                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

endmodule
