//=============================================================================
// Module: uart_tx
// Description: Parameterized UART transmitter with configurable baud rate,
//              start bit, 8 data bits, and stop bits.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer DATA_BITS   = 8,
    parameter integer STOP_BITS   = 1
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 tx_start,   // Pulse high for 1 cycle to transmit tx_data
    input  wire [DATA_BITS-1:0] tx_data,    // Byte to transmit
    output reg                  tx_line,    // Serial physical line (idle high)
    output reg                  tx_busy,    // High while transmission is in progress
    output reg                  tx_done     // 1-cycle pulse upon transmission completion
);

    localparam integer BIT_PERIOD = (CLK_FREQ_HZ > BAUD_RATE) ? (CLK_FREQ_HZ / BAUD_RATE) : 1;
    localparam integer BIT_CNT_W  = (BIT_PERIOD > 1) ? $clog2(BIT_PERIOD) : 1;

    // FSM State Encoding
    localparam [2:0]
        STATE_IDLE  = 3'b000,
        STATE_START = 3'b001,
        STATE_DATA  = 3'b010,
        STATE_STOP  = 3'b011;

    reg [2:0]           state;
    reg [BIT_CNT_W-1:0] baud_cnt;
    reg [2:0]           bit_idx;
    reg [DATA_BITS-1:0] tx_shifter;
    reg [1:0]           stop_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state      <= STATE_IDLE;
            tx_line    <= 1'b1; // Idle high
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            baud_cnt   <= {BIT_CNT_W{1'b0}};
            bit_idx    <= 3'd0;
            tx_shifter <= {DATA_BITS{1'b0}};
            stop_cnt   <= 2'd0;
        end else begin
            tx_done <= 1'b0; // Default pulse low

            case (state)
                STATE_IDLE: begin
                    tx_line <= 1'b1;
                    tx_busy <= 1'b0;
                    baud_cnt <= {BIT_CNT_W{1'b0}};
                    bit_idx  <= 3'd0;
                    stop_cnt <= 2'd0;

                    if (tx_start) begin
                        tx_shifter <= tx_data;
                        tx_busy    <= 1'b1;
                        tx_line    <= 1'b0; // Assert Start bit
                        state      <= STATE_START;
                    end
                end

                STATE_START: begin
                    tx_line <= 1'b0;
                    tx_busy <= 1'b1;
                    if (baud_cnt >= BIT_PERIOD - 1) begin
                        baud_cnt <= {BIT_CNT_W{1'b0}};
                        tx_line  <= tx_shifter[0];
                        state    <= STATE_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STATE_DATA: begin
                    tx_line <= tx_shifter[0];
                    tx_busy <= 1'b1;
                    if (baud_cnt >= BIT_PERIOD - 1) begin
                        baud_cnt <= {BIT_CNT_W{1'b0}};
                        if (bit_idx >= DATA_BITS - 1) begin
                            bit_idx  <= 3'd0;
                            tx_line  <= 1'b1; // Assert Stop bit
                            state    <= STATE_STOP;
                        end else begin
                            bit_idx    <= bit_idx + 1'b1;
                            tx_shifter <= tx_shifter >> 1;
                            tx_line    <= tx_shifter[1];
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STATE_STOP: begin
                    tx_line <= 1'b1; // Stop bit high
                    tx_busy <= 1'b1;
                    if (baud_cnt >= BIT_PERIOD - 1) begin
                        baud_cnt <= {BIT_CNT_W{1'b0}};
                        if (stop_cnt >= STOP_BITS - 1) begin
                            tx_done  <= 1'b1;
                            tx_busy  <= 1'b0;
                            state    <= STATE_IDLE;
                        end else begin
                            stop_cnt <= stop_cnt + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
