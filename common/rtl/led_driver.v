//=============================================================================
// Module: led_driver
// Description: Multi-mode LED controller with solid, blink, and pulse patterns.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module led_driver #(
    parameter integer NUM_LEDS    = 18,
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire [NUM_LEDS-1:0]  led_data,       // Base LED on/off states
    input  wire [NUM_LEDS-1:0]  led_blink_mask, // 1 = LED blinks, 0 = solid
    input  wire [1:0]           blink_rate_sel, // 00 = 1Hz, 01 = 2Hz, 10 = 4Hz, 11 = 8Hz
    output reg  [NUM_LEDS-1:0]  led_out
);

    // Timing prescaler: 50 MHz / 16 gives ~3.125 MHz base
    localparam integer CYCLES_1HZ = CLK_FREQ_HZ;
    localparam integer CYCLES_2HZ = CLK_FREQ_HZ / 2;
    localparam integer CYCLES_4HZ = CLK_FREQ_HZ / 4;
    localparam integer CYCLES_8HZ = CLK_FREQ_HZ / 8;

    reg [31:0] counter;
    reg blink_toggle;

    reg [31:0] threshold;
    always @(*) begin
        case (blink_rate_sel)
            2'b00: threshold = CYCLES_1HZ / 2;
            2'b01: threshold = CYCLES_2HZ / 2;
            2'b10: threshold = CYCLES_4HZ / 2;
            2'b11: threshold = CYCLES_8HZ / 2;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            counter      <= 32'd0;
            blink_toggle <= 1'b0;
        end else begin
            if (counter >= threshold - 1) begin
                counter      <= 32'd0;
                blink_toggle <= ~blink_toggle;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

    integer i;
    always @(*) begin
        for (i = 0; i < NUM_LEDS; i = i + 1) begin
            if (led_blink_mask[i]) begin
                led_out[i] = led_data[i] & blink_toggle;
            end else begin
                led_out[i] = led_data[i];
            end
        end
    end

endmodule
