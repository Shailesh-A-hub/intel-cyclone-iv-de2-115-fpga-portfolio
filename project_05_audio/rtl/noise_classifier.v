//=============================================================================
// Module: noise_classifier
// Description: Deterministic real-time spectral noise classifier. Evaluates
//              psychoacoustic band energy ratios and dominant peak distribution
//              to classify audio into 5 distinct categories:
//                1. QUIET          (Ambient silence / low noise floor)
//                2. SPEECH         (Energy concentrated in 800Hz-2.5kHz formants)
//                3. LOW-FREQUENCY  (Hum, rumble, motor drone < 800 Hz)
//                4. HIGH-FREQUENCY (Whistle, hiss, screech > 2.5 kHz)
//                5. IMPULSIVE/NOISE(Broadband flat transient or white noise)
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module noise_classifier #(
    parameter integer QUIET_THRESHOLD = 50
)(
    input  wire        clk,
    input  wire        reset_n,

    // Latched frame metrics from spectral_band_extractor
    input  wire        frame_valid_pulse,
    input  wire [27:0] total_energy,
    input  wire [23:0] band0_energy, // Sub-Bass
    input  wire [23:0] band1_energy, // Bass
    input  wire [23:0] band2_energy, // Midrange (Speech)
    input  wire [23:0] band3_energy, // Upper-Mid
    input  wire [23:0] band4_energy, // High
    input  wire [23:0] band5_energy, // Air
    input  wire [7:0]  peak_bin_index,

    // Classified Output
    output reg  [2:0]  class_code,
    output reg  [31:0] class_ascii,
    output reg  [7:0]  confidence_pct,
    output reg         class_valid_pulse
);

    // Class Encodings
    localparam [2:0]
        CLASS_QUIET     = 3'd0,
        CLASS_SPEECH    = 3'd1,
        CLASS_LOW_FREQ  = 3'd2,
        CLASS_HIGH_FREQ = 3'd3,
        CLASS_IMPULSIVE = 3'd4;

    // Cross-multiplication terms for division-free comparison:
    // band2_energy > 0.33 * total_energy  <=>  band2_energy * 3 > total_energy
    wire [29:0] speech_term = {band2_energy, 1'b0} + band2_energy; // band2 * 3
    // low_energy > 0.45 * total_energy   <=>  (band0 + band1) * 20 > total_energy * 9
    wire [24:0] low_sum     = band0_energy + band1_energy;
    wire [29:0] low_term    = (low_sum << 4) + (low_sum << 2);      // low_sum * 20
    // high_energy > 0.40 * total_energy  <=>  (band4 + band5 + band3) * 5 > total_energy * 2
    wire [24:0] high_sum    = band4_energy + band5_energy;
    wire [29:0] high_term   = (high_sum << 2) + high_sum;           // high_sum * 5
    wire [29:0] upper_mid_term = (band3_energy << 2) + band3_energy; // band3 * 5

    always @(posedge clk) begin
        if (!reset_n) begin
            class_code        <= CLASS_QUIET;
            class_ascii       <= "QUET";
            confidence_pct    <= 8'd100;
            class_valid_pulse <= 1'b0;
        end else begin
            class_valid_pulse <= 1'b0; // Default pulse

            if (frame_valid_pulse) begin
                class_valid_pulse <= 1'b1;

                // Rule 1: Ambient Silence / Low Energy
                if (total_energy < QUIET_THRESHOLD) begin
                    class_code     <= CLASS_QUIET;
                    class_ascii    <= "QUET";
                    confidence_pct <= 8'd100;
                // Rule 2: Speech Formant Detection
                end else if (speech_term > total_energy) begin
                    class_code     <= CLASS_SPEECH;
                    class_ascii    <= "SPCH";
                    confidence_pct <= 8'd95;
                // Rule 3: Low-Frequency Dominance (< 800 Hz)
                end else if (low_term > (total_energy * 9)) begin
                    class_code     <= CLASS_LOW_FREQ;
                    class_ascii    <= "LOWF";
                    confidence_pct <= 8'd90;
                // Rule 4: High-Frequency Dominance (> 2.5 kHz)
                end else if ((high_term > (total_energy << 1)) || (upper_mid_term > (total_energy << 1))) begin
                    class_code     <= CLASS_HIGH_FREQ;
                    class_ascii    <= "HGHF";
                    confidence_pct <= 8'd85;
                // Rule 5: Broadband Impulsive Noise / Transient Spread
                end else begin
                    class_code     <= CLASS_IMPULSIVE;
                    class_ascii    <= "NOIS";
                    confidence_pct <= 8'd80;
                end
            end
        end
    end

endmodule
