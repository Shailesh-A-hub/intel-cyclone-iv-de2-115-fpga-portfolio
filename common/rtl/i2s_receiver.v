//=============================================================================
// Module: i2s_receiver
// Description: Standard Philips I2S audio receiver. Synchronizes external BCLK,
//              LRCLK, and SDATA to the system clock, decodes 16-bit or 24-bit signed
//              stereo PCM audio, and generates a sample_valid strobe.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module i2s_receiver #(
    parameter integer AUDIO_WIDTH = 16 // 16-bit or 24-bit PCM
)(
    input  wire                   clk,          // System clock (50 MHz)
    input  wire                   rst,          // Synchronous active-high reset
    // Physical I2S bus pins from WM8731 codec
    input  wire                   i2s_bclk,     // Bit clock
    input  wire                   i2s_lrclk,    // Left/Right word select clock (0 = Left, 1 = Right)
    input  wire                   i2s_sdata,    // Serial audio data stream
    // Parallel audio output
    output reg  signed [AUDIO_WIDTH-1:0] left_data,
    output reg  signed [AUDIO_WIDTH-1:0] right_data,
    output reg                           sample_valid  // 1-cycle pulse upon completion of stereo pair
);

    // 2-stage synchronizers for external I2S inputs
    reg [2:0] bclk_sync;
    reg [2:0] lrclk_sync;
    reg [2:0] sdata_sync;

    always @(posedge clk) begin
        if (rst) begin
            bclk_sync  <= 3'b000;
            lrclk_sync <= 3'b000;
            sdata_sync <= 3'b000;
        end else begin
            bclk_sync  <= {bclk_sync[1:0], i2s_bclk};
            lrclk_sync <= {lrclk_sync[1:0], i2s_lrclk};
            sdata_sync <= {sdata_sync[1:0], i2s_sdata};
        end
    end

    // Detect edges on synchronized I2S clocks
    wire bclk_rising   = (bclk_sync[2:1] == 2'b01);
    wire bclk_falling  = (bclk_sync[2:1] == 2'b10);
    wire lrclk_changed = (lrclk_sync[2] != lrclk_sync[1]);

    reg [5:0]              bit_cnt;
    reg                    channel; // 0 = Left, 1 = Right
    reg [AUDIO_WIDTH-1:0]  shift_reg;
    reg                    first_bclk_after_lrclk;

    always @(posedge clk) begin
        if (rst) begin
            left_data              <= {AUDIO_WIDTH{1'b0}};
            right_data             <= {AUDIO_WIDTH{1'b0}};
            sample_valid           <= 1'b0;
            bit_cnt                <= 6'd0;
            channel                <= 1'b0;
            shift_reg              <= {AUDIO_WIDTH{1'b0}};
            first_bclk_after_lrclk <= 1'b0;
        end else begin
            sample_valid <= 1'b0; // Default pulse low

            // Handle LRCLK channel transitions
            if (lrclk_changed) begin
                first_bclk_after_lrclk <= 1'b1; // Philips I2S delay: skip 1 BCLK after LRCLK edge
                channel                <= lrclk_sync[1]; // Next channel (0=Left, 1=Right)
                bit_cnt                <= 6'd0;
            end

            // Sample data on BCLK rising edge
            if (bclk_rising) begin
                if (first_bclk_after_lrclk) begin
                    // 1-bit delay period in Philips standard; do not sample MSB here
                    first_bclk_after_lrclk <= 1'b0;
                end else if (bit_cnt < AUDIO_WIDTH) begin
                    shift_reg <= {shift_reg[AUDIO_WIDTH-2:0], sdata_sync[2]};
                    bit_cnt   <= bit_cnt + 1'b1;

                    // When final bit of current channel is sampled
                    if (bit_cnt == AUDIO_WIDTH - 1) begin
                        if (channel == 1'b0) begin
                            // Left channel complete
                            left_data <= {shift_reg[AUDIO_WIDTH-2:0], sdata_sync[2]};
                        end else begin
                            // Right channel complete -> entire stereo frame valid!
                            right_data   <= {shift_reg[AUDIO_WIDTH-2:0], sdata_sync[2]};
                            sample_valid <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
