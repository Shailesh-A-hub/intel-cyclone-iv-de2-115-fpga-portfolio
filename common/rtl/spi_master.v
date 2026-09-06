//=============================================================================
// Module: spi_master
// Description: Fully parameterized SPI Master supporting Modes 0, 1, 2, 3,
//              configurable word widths, programmable SCLK divider, and active-low CS.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module spi_master #(
    parameter integer DATA_WIDTH = 8,  // Number of bits per SPI transaction
    parameter integer CPOL       = 0,  // 0 = SCLK idle low, 1 = SCLK idle high
    parameter integer CPHA       = 0,  // 0 = sample on first edge, 1 = sample on second edge
    parameter integer CLK_DIV    = 50  // SCLK period = CLK_DIV * clk cycles (must be even >= 2)
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,         // Initiate SPI transaction
    input  wire [DATA_WIDTH-1:0] tx_data,       // Data to transmit (MSB first)
    output reg  [DATA_WIDTH-1:0] rx_data,       // Received data
    output reg                   busy,          // High during active transaction
    output reg                   done,          // 1-cycle pulse upon completion
    // SPI Physical Bus
    output reg                   spi_sclk,      // Serial Clock
    output reg                   spi_mosi,      // Master Out Slave In
    input  wire                  spi_miso,      // Master In Slave Out
    output reg                   spi_cs_n       // Active-Low Chip Select
);

    localparam integer HALF_DIV = CLK_DIV / 2;
    localparam integer DIV_W    = $clog2(CLK_DIV);
    localparam integer BIT_W    = $clog2(DATA_WIDTH + 1);

    localparam [2:0]
        S_IDLE     = 3'b000,
        S_PREPARE  = 3'b001,
        S_EDGE_1   = 3'b010,
        S_EDGE_2   = 3'b011,
        S_FINISH   = 3'b100;

    reg [2:0]            state;
    reg [DIV_W-1:0]      div_cnt;
    reg [BIT_W-1:0]      bit_cnt;
    reg [DATA_WIDTH-1:0] tx_shifter;
    reg [DATA_WIDTH-1:0] rx_shifter;

    // Synchronize MISO to internal clock
    reg miso_sync1, miso_sync2;
    always @(posedge clk) begin
        if (rst) begin
            miso_sync1 <= 1'b0;
            miso_sync2 <= 1'b0;
        end else begin
            miso_sync1 <= spi_miso;
            miso_sync2 <= miso_sync1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            spi_sclk   <= (CPOL != 0);
            spi_mosi   <= 1'b0;
            spi_cs_n   <= 1'b1;
            div_cnt    <= {DIV_W{1'b0}};
            bit_cnt    <= {BIT_W{1'b0}};
            tx_shifter <= {DATA_WIDTH{1'b0}};
            rx_shifter <= {DATA_WIDTH{1'b0}};
            rx_data    <= {DATA_WIDTH{1'b0}};
        end else begin
            done <= 1'b0; // Default pulse low

            case (state)
                S_IDLE: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= (CPOL != 0);
                    busy     <= 1'b0;
                    div_cnt  <= {DIV_W{1'b0}};
                    bit_cnt  <= {BIT_W{1'b0}};

                    if (start) begin
                        busy       <= 1'b1;
                        spi_cs_n   <= 1'b0; // Assert CS
                        tx_shifter <= tx_data;
                        state      <= S_PREPARE;
                    end
                end

                S_PREPARE: begin
                    busy <= 1'b1;
                    // Setup first bit if CPHA == 0
                    if (CPHA == 0) begin
                        spi_mosi <= tx_shifter[DATA_WIDTH-1];
                    end
                    div_cnt <= {DIV_W{1'b0}};
                    state   <= S_EDGE_1;
                end

                S_EDGE_1: begin
                    busy <= 1'b1;
                    if (div_cnt >= HALF_DIV - 1) begin
                        div_cnt  <= {DIV_W{1'b0}};
                        spi_sclk <= ~spi_sclk; // First active edge

                        if (CPHA == 0) begin
                            // Sample on first edge
                            rx_shifter <= {rx_shifter[DATA_WIDTH-2:0], miso_sync2};
                        end else begin
                            // Drive on first edge
                            spi_mosi <= tx_shifter[DATA_WIDTH-1];
                        end
                        state <= S_EDGE_2;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                S_EDGE_2: begin
                    busy <= 1'b1;
                    if (div_cnt >= HALF_DIV - 1) begin
                        div_cnt  <= {DIV_W{1'b0}};
                        spi_sclk <= ~spi_sclk; // Second edge (return to idle)

                        if (CPHA == 0) begin
                            // Shift out next bit
                            tx_shifter <= {tx_shifter[DATA_WIDTH-2:0], 1'b0};
                            if (bit_cnt < DATA_WIDTH - 1) begin
                                spi_mosi <= tx_shifter[DATA_WIDTH-2];
                            end
                        end else begin
                            // Sample on second edge
                            rx_shifter <= {rx_shifter[DATA_WIDTH-2:0], miso_sync2};
                            tx_shifter <= {tx_shifter[DATA_WIDTH-2:0], 1'b0};
                        end

                        if (bit_cnt >= DATA_WIDTH - 1) begin
                            bit_cnt <= {BIT_W{1'b0}};
                            state   <= S_FINISH;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                            state   <= S_EDGE_1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                S_FINISH: begin
                    busy <= 1'b1;
                    if (div_cnt >= HALF_DIV - 1) begin
                        div_cnt  <= {DIV_W{1'b0}};
                        spi_cs_n <= 1'b1; // De-assert CS
                        rx_data  <= rx_shifter;
                        done     <= 1'b1;
                        busy     <= 1'b0;
                        state    <= S_IDLE;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
