//=============================================================================
// Module: clock_divider
// Description: Parameterized integer clock divider. Provides both a 50% duty
//              cycle divided clock and a single-cycle synchronous clock enable tick.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module clock_divider #(
    parameter integer DIVISOR = 50_000_000 // Input clock cycles per output period
)(
    input  wire clk,        // Source clock (e.g. 50 MHz)
    input  wire rst,        // Synchronous active-high reset
    output reg  clk_out,    // 50% duty cycle divided clock
    output reg  tick_out    // 1-cycle strobe active on the terminal count
);

    // Calculate required counter bit width
    localparam integer WIDTH = (DIVISOR > 1) ? $clog2(DIVISOR) : 1;
    localparam integer HALF_DIVISOR = DIVISOR / 2;

    reg [WIDTH-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count    <= {WIDTH{1'b0}};
            clk_out  <= 1'b0;
            tick_out <= 1'b0;
        end else begin
            if (count == DIVISOR - 1) begin
                count    <= {WIDTH{1'b0}};
                tick_out <= 1'b1;
                clk_out  <= ~clk_out;
            end else begin
                tick_out <= 1'b0;
                count    <= count + 1'b1;
                if (count == HALF_DIVISOR - 1) begin
                    clk_out <= ~clk_out;
                end
            end
        end
    end

endmodule
