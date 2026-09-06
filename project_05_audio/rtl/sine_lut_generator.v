//=============================================================================
// Module: sine_lut_generator
// Description: Direct Digital Synthesis (DDS) test tone generator and Galois LFSR
//              white noise source for bench verification of the Audio Spectrum Analyzer.
//              Generates 16-bit signed PCM audio samples at 48 kHz for known
//              test frequencies: 1 kHz, 2 kHz, 5 kHz, and broadband noise.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module sine_lut_generator #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer SAMPLE_RATE = 48_000,
    parameter integer SIMULATION  = 0
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire [2:0]  tone_select,    // 0: Silence, 1: 1kHz, 2: 2kHz, 3: 5kHz, 4: Noise
    output reg  signed [15:0] audio_sample,
    output reg         sample_tick
);

    // 48 kHz Sample Tick Generator
    localparam integer TICK_DIV = CLK_FREQ_HZ / SAMPLE_RATE;
    reg [11:0] tick_cnt;

    always @(posedge clk) begin
        if (!reset_n) begin
            tick_cnt    <= 12'd0;
            sample_tick <= 1'b0;
        end else begin
            if (tick_cnt >= TICK_DIV - 1) begin
                tick_cnt    <= 12'd0;
                sample_tick <= 1'b1;
            end else begin
                tick_cnt    <= tick_cnt + 1'b1;
                sample_tick <= 1'b0;
            end
        end
    end

    // 256-word 16-bit Signed Sine Wave ROM
    reg signed [15:0] sine_rom [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            sine_rom[i] = $rtoi($sin(2.0 * 3.141592653589793 * i / 256.0) * 20000.0);
        end
    end

    // Phase Tuning Words:
    // In Simulation (N=64 @ 2.5MHz):
    // Bin 2: 2048 (Speech Midrange Band 2)
    // Bin 3: 3072 (Speech Midrange Band 2)
    // Bin 5: 5120 (Upper-Mid / High-Frequency Band 3/4)
    // In Hardware (N=256 @ 48kHz): delta_phi = (f_target * 65536) / 48000
    localparam [15:0]
        PHASE_1KHZ = (SIMULATION) ? 16'd2048 : 16'd1365,
        PHASE_2KHZ = (SIMULATION) ? 16'd3072 : 16'd2731,
        PHASE_5KHZ = (SIMULATION) ? 16'd5120 : 16'd6827;

    reg [15:0] phase_acc;
    reg [15:0] lfsr_reg;

    always @(posedge clk) begin
        if (!reset_n) begin
            phase_acc    <= 16'd0;
            lfsr_reg     <= 16'hACE1;
            audio_sample <= 16'sd0;
        end else if (sample_tick) begin
            // 16-bit Galois LFSR for white noise (polynomial x^16 + x^14 + x^13 + x^11 + 1)
            lfsr_reg <= (lfsr_reg >> 1) ^ (-(lfsr_reg & 1'b1) & 16'hB400);

            case (tone_select)
                3'd0: begin // Silence
                    phase_acc    <= 16'd0;
                    audio_sample <= 16'sd0;
                end

                3'd1: begin // 1 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_1KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd2: begin // 2 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_2KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd3: begin // 5 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_5KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd4, 3'd5: begin // White Noise
                    audio_sample <= $signed(lfsr_reg);
                end

                default: begin
                    audio_sample <= 16'sd0;
                end
            endcase
        end
    end

endmodule
