//=============================================================================
// Module: hanning_window
// Description: Multiplies incoming 16-bit signed audio samples by pre-computed
//              Hanning window coefficients: w(n) = 0.5 - 0.5*cos(2*pi*n / N)
//              in Q0.16 unsigned format to eliminate Gibbs phenomenon and
//              spectral leakage before FFT processing.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module hanning_window #(
    parameter integer BUFFER_SIZE = 512,
    parameter integer DATA_WIDTH  = 16
)(
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         in_valid,
    input  wire [$clog2(BUFFER_SIZE)-1:0] sample_idx,
    input  wire signed [DATA_WIDTH-1:0] sample_in,

    output reg                          out_valid,
    output reg  [$clog2(BUFFER_SIZE)-1:0] out_idx,
    output reg  signed [DATA_WIDTH-1:0] sample_out
);

    localparam ADDR_WIDTH = $clog2(BUFFER_SIZE);

    // 16-bit unsigned Hanning coefficient ROM
    // Approximation: w(n) = 32767 * (1 - cos(2*pi*n / N))
    // Can be represented via a 64/256/512 entry lookup table
    reg [15:0] window_rom [0:BUFFER_SIZE-1];
    integer i;

    initial begin
        for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
            // Synthesizable initial block computes constant ROM at elaboration
            window_rom[i] = $rtoi((0.5 - 0.5 * $cos(2.0 * 3.141592653589793 * i / BUFFER_SIZE)) * 65535.0);
        end
    end

    wire [15:0] w_coeff = window_rom[sample_idx];

    // Signed multiplier: signed 16-bit sample * unsigned 16-bit window
    // Extended product: 32 bits
    wire signed [32:0] mult_product = $signed(sample_in) * $signed({1'b0, w_coeff});

    always @(posedge clk) begin
        if (!reset_n) begin
            out_valid  <= 1'b0;
            out_idx    <= {ADDR_WIDTH{1'b0}};
            sample_out <= {DATA_WIDTH{1'b0}};
        end else begin
            out_valid  <= in_valid;
            out_idx    <= sample_idx;
            if (in_valid) begin
                // Scale by 1/65536 (shift right by 16 bits)
                sample_out <= mult_product[31:16];
            end
        end
    end

endmodule
