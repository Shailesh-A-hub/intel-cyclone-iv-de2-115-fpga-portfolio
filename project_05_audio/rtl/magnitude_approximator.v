//=============================================================================
// Module: magnitude_approximator
// Description: Alpha-Max Beta-Min (AMBM) vector magnitude approximation engine:
//                |X| approx max(|R|, |I|) + 3/8 * min(|R|, |I|)
//              Calculates accurate single-cycle Euclidean magnitude for complex
//              spectral bins without costly square-root hardware. Peak error is
//              theoretically bounded to < 6.8% across all phase angles.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module magnitude_approximator #(
    parameter integer DATA_WIDTH = 16,
    parameter integer BIN_WIDTH  = 8
)(
    input  wire                   clk,
    input  wire                   reset_n,

    // Streaming complex bin input from FFT
    input  wire                   bin_valid,
    input  wire [BIN_WIDTH-1:0]   bin_index,
    input  wire signed [DATA_WIDTH-1:0] real_in,
    input  wire signed [DATA_WIDTH-1:0] imag_in,

    // Streaming magnitude output
    output reg                    mag_valid,
    output reg  [BIN_WIDTH-1:0]   mag_bin_index,
    output reg  [DATA_WIDTH-1:0]  magnitude_out
);

    // Absolute values of real and imaginary components
    wire [DATA_WIDTH-1:0] abs_r = (real_in < 0) ? (-real_in) : real_in;
    wire [DATA_WIDTH-1:0] abs_i = (imag_in < 0) ? (-imag_in) : imag_in;

    wire [DATA_WIDTH-1:0] val_max = (abs_r >= abs_i) ? abs_r : abs_i;
    wire [DATA_WIDTH-1:0] val_min = (abs_r >= abs_i) ? abs_i : abs_r;

    // AMBM Calculation: max + 3/8 * min = max + ((min * 3) >> 3)
    wire [DATA_WIDTH+1:0] min_x3 = {1'b0, val_min} + {val_min, 1'b0}; // val_min * 3
    wire [DATA_WIDTH-1:0] beta_term = min_x3[DATA_WIDTH+1:3];          // >> 3

    wire [DATA_WIDTH:0] sum_mag = val_max + beta_term;

    always @(posedge clk) begin
        if (!reset_n) begin
            mag_valid     <= 1'b0;
            mag_bin_index <= {BIN_WIDTH{1'b0}};
            magnitude_out <= {DATA_WIDTH{1'b0}};
        end else begin
            mag_valid     <= bin_valid;
            mag_bin_index <= bin_index;
            if (bin_valid) begin
                // Saturate to 16 bits if sum overflows
                magnitude_out <= (sum_mag[DATA_WIDTH]) ? {DATA_WIDTH{1'b1}} : sum_mag[DATA_WIDTH-1:0];
            end
        end
    end

endmodule
