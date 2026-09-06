//=============================================================================
// Module: audio_pingpong_buffer
// Description: Dual-bank ping-pong audio sample buffer. Continuously collects
//              16-bit signed PCM audio samples from the I2S receiver at 48 kHz
//              into one bank while the alternate bank is read out by the windowing
//              and FFT pipeline. Automatically toggles banks upon filling.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module audio_pingpong_buffer #(
    parameter integer BUFFER_SIZE = 512,
    parameter integer DATA_WIDTH  = 16
)(
    input  wire                   clk,
    input  wire                   reset_n,

    // Write interface (from I2S receiver @ 48 kHz)
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                         sample_valid,

    // Read interface (from windowing / FFT engine)
    input  wire [$clog2(BUFFER_SIZE)-1:0] rd_addr,
    output reg  signed [DATA_WIDTH-1:0]   rd_data,

    // Buffer status & handshaking
    output reg                          buffer_ready_pulse, // 1-cycle pulse when a bank is filled
    output reg                          active_bank         // 0 = Writing to Bank 0, 1 = Writing to Bank 1
);

    localparam ADDR_WIDTH = $clog2(BUFFER_SIZE);

    // Dual-bank memory storage
    reg signed [DATA_WIDTH-1:0] bank0 [0:BUFFER_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bank1 [0:BUFFER_SIZE-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;

    // Write Logic
    always @(posedge clk) begin
        if (!reset_n) begin
            wr_ptr             <= {ADDR_WIDTH{1'b0}};
            active_bank        <= 1'b0;
            buffer_ready_pulse <= 1'b0;
        end else begin
            buffer_ready_pulse <= 1'b0; // Default pulse

            if (sample_valid) begin
                if (!active_bank) begin
                    bank0[wr_ptr] <= sample_in;
                end else begin
                    bank1[wr_ptr] <= sample_in;
                end

                if (wr_ptr >= BUFFER_SIZE - 1) begin
                    wr_ptr             <= {ADDR_WIDTH{1'b0}};
                    active_bank        <= !active_bank; // Toggle bank
                    buffer_ready_pulse <= 1'b1;         // Notify downstream FFT
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
        end
    end

    // Read Logic (Reads the completed bank)
    always @(posedge clk) begin
        if (!active_bank) begin
            // Active write is Bank 0 -> Read from Bank 1
            rd_data <= bank1[rd_addr];
        end else begin
            // Active write is Bank 1 -> Read from Bank 0
            rd_data <= bank0[rd_addr];
        end
    end

endmodule
