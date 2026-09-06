//=============================================================================
// Module: timer_ms
// Description: Millisecond tick pulse generator. Emits a 1-clock-cycle strobe
//              every 1 ms (1 kHz) derived from the input system clock.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module timer_ms #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire clk,      // System clock
    input  wire rst,      // Synchronous active-high reset
    output reg  tick_1ms  // 1-cycle pulse every 1 ms
);

    localparam integer CYCLES_PER_MS = CLK_FREQ_HZ / 1000;
    localparam integer WIDTH = $clog2(CYCLES_PER_MS);

    reg [WIDTH-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count    <= {WIDTH{1'b0}};
            tick_1ms <= 1'b0;
        end else begin
            if (count >= CYCLES_PER_MS - 1) begin
                count    <= {WIDTH{1'b0}};
                tick_1ms <= 1'b1;
            end else begin
                count    <= count + 1'b1;
                tick_1ms <= 1'b0;
            end
        end
    end

endmodule
