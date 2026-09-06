//=============================================================================
// Module: periodic_timer
// Description: Fully parameterized periodic interval timer. Emits a 1-cycle tick
//              at configured intervals. Supports prescaled timebases (e.g. 1ms tick).
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module periodic_timer #(
    parameter integer PERIOD = 1000,
    parameter integer WIDTH  = 32
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             enable,      // 1 = active, 0 = paused
    input  wire             tick_in,     // Timebase tick enable (tie 1'b1 to count clock cycles)
    output reg              tick_out,    // 1-cycle pulse upon period expiration
    output reg  [WIDTH-1:0] count_val    // Current accumulated count
);

    always @(posedge clk) begin
        if (rst) begin
            count_val <= {WIDTH{1'b0}};
            tick_out  <= 1'b0;
        end else if (enable) begin
            if (tick_in) begin
                if (count_val >= PERIOD - 1) begin
                    count_val <= {WIDTH{1'b0}};
                    tick_out  <= 1'b1;
                end else begin
                    count_val <= count_val + 1'b1;
                    tick_out  <= 1'b0;
                end
            end else begin
                tick_out <= 1'b0;
            end
        end else begin
            tick_out <= 1'b0;
        end
    end

endmodule
