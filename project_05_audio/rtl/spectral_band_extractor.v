//=============================================================================
// Module: spectral_band_extractor
// Description: Accumulates discrete FFT magnitude bins into 6 standard
//              psychoacoustic frequency bands: Sub-Bass, Bass, Midrange (Speech),
//              Upper-Mid, High-Frequency, and Air. Extracts total spectral energy,
//              tracks dominant peak frequency bin, and provides latched frame outputs.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module spectral_band_extractor #(
    parameter integer FFT_POINTS = 256,
    parameter integer DATA_WIDTH = 16
)(
    input  wire                              clk,
    input  wire                              reset_n,

    // Streaming magnitude input from magnitude_approximator
    input  wire                              mag_valid,
    input  wire [$clog2(FFT_POINTS/2)-1:0]   bin_index,
    input  wire [DATA_WIDTH-1:0]             magnitude,
    input  wire                              fft_done,

    // Latched psychoacoustic band energies
    output reg  [23:0]                       band0_energy, // Sub-Bass
    output reg  [23:0]                       band1_energy, // Bass / Low-Mid
    output reg  [23:0]                       band2_energy, // Midrange (Speech)
    output reg  [23:0]                       band3_energy, // Upper-Mid
    output reg  [23:0]                       band4_energy, // High Frequencies
    output reg  [23:0]                       band5_energy, // Air / Brilliance

    // Overall spectral metrics
    output reg  [27:0]                       total_energy,
    output reg  [$clog2(FFT_POINTS/2)-1:0]   peak_bin_index,
    output reg  [DATA_WIDTH-1:0]             peak_magnitude,
    output reg                               frame_valid_pulse
);

    localparam BINS_W = $clog2(FFT_POINTS / 2);
    localparam TOTAL_BINS = FFT_POINTS / 2;

    // Band Boundaries mapped proportionally to total bins
    // For 128 bins (N=256 @ 48kHz, bin=187.5Hz):
    // Band 0: bins 1..2   (Sub-bass: 187 - 375 Hz)
    // Band 1: bins 3..4   (Bass: 560 - 750 Hz)
    // Band 2: bins 5..13  (Speech Midrange: 937 - 2437 Hz)
    // Band 3: bins 14..26 (Upper Mid: 2625 - 4875 Hz)
    // Band 4: bins 27..53 (High: 5062 - 9937 Hz)
    // Band 5: bins 54..127(Air: 10.1 kHz - 24 kHz)
    wire [BINS_W-1:0] BND0_END = (TOTAL_BINS * 2)  / 128;
    wire [BINS_W-1:0] BND1_END = (TOTAL_BINS * 4)  / 128;
    wire [BINS_W-1:0] BND2_END = (TOTAL_BINS * 13) / 128;
    wire [BINS_W-1:0] BND3_END = (TOTAL_BINS * 26) / 128;
    wire [BINS_W-1:0] BND4_END = (TOTAL_BINS * 53) / 128;

    // Running Accumulators
    reg [23:0] acc_b0, acc_b1, acc_b2, acc_b3, acc_b4, acc_b5;
    reg [27:0] acc_tot;
    reg [BINS_W-1:0] run_peak_bin;
    reg [DATA_WIDTH-1:0] run_peak_mag;

    always @(posedge clk) begin
        if (!reset_n) begin
            acc_b0            <= 24'd0;
            acc_b1            <= 24'd0;
            acc_b2            <= 24'd0;
            acc_b3            <= 24'd0;
            acc_b4            <= 24'd0;
            acc_b5            <= 24'd0;
            acc_tot           <= 28'd0;
            run_peak_bin      <= {BINS_W{1'b0}};
            run_peak_mag      <= {DATA_WIDTH{1'b0}};
            band0_energy      <= 24'd0;
            band1_energy      <= 24'd0;
            band2_energy      <= 24'd0;
            band3_energy      <= 24'd0;
            band4_energy      <= 24'd0;
            band5_energy      <= 24'd0;
            total_energy      <= 28'd0;
            peak_bin_index    <= {BINS_W{1'b0}};
            peak_magnitude    <= {DATA_WIDTH{1'b0}};
            frame_valid_pulse <= 1'b0;
        end else begin
            frame_valid_pulse <= 1'b0; // Default pulse

            if (mag_valid) begin
                // Accumulate into running total (ignore DC bin 0)
                if (bin_index > 0) begin
                    acc_tot <= acc_tot + magnitude;

                    // Track peak frequency bin
                    if (magnitude > run_peak_mag) begin
                        run_peak_mag <= magnitude;
                        run_peak_bin <= bin_index;
                    end

                    // Accumulate into respective psychoacoustic frequency band
                    if (bin_index <= BND0_END)
                        acc_b0 <= acc_b0 + magnitude;
                    else if (bin_index <= BND1_END)
                        acc_b1 <= acc_b1 + magnitude;
                    else if (bin_index <= BND2_END)
                        acc_b2 <= acc_b2 + magnitude;
                    else if (bin_index <= BND3_END)
                        acc_b3 <= acc_b3 + magnitude;
                    else if (bin_index <= BND4_END)
                        acc_b4 <= acc_b4 + magnitude;
                    else
                        acc_b5 <= acc_b5 + magnitude;
                end
            end

            // When FFT completes frame: Latch metrics and reset accumulators
            if (fft_done) begin
                band0_energy      <= acc_b0;
                band1_energy      <= acc_b1;
                band2_energy      <= acc_b2;
                band3_energy      <= acc_b3;
                band4_energy      <= acc_b4;
                band5_energy      <= acc_b5;
                total_energy      <= acc_tot;
                peak_bin_index    <= run_peak_bin;
                peak_magnitude    <= run_peak_mag;
                frame_valid_pulse <= 1'b1;

                // Clear running accumulators for next audio frame
                acc_b0       <= 24'd0;
                acc_b1       <= 24'd0;
                acc_b2       <= 24'd0;
                acc_b3       <= 24'd0;
                acc_b4       <= 24'd0;
                acc_b5       <= 24'd0;
                acc_tot      <= 28'd0;
                run_peak_bin <= {BINS_W{1'b0}};
                run_peak_mag <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
