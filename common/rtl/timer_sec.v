//=============================================================================
// Module: timer_sec
// Description: Second tick pulse generator. Emits a 1-clock-cycle strobe
//              every 1 second (1 Hz) derived from the input system clock.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module timer_sec #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire clk,       // System clock
    input  wire rst,       // Synchronous active-high reset
    output reg  tick_1sec  // 1-cycle pulse every 1 second
);

    localparam integer CYCLES_PER_SEC = CLK_FREQ_HZ;
    localparam integer WIDTH = $clog2(CYCLES_PER_SEC);

    reg [WIDTH-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count     <= {WIDTH{1'b0}};
            tick_1sec <= 1'b0;
        end else begin
            if (count >= CYCLES_PER_SEC - 1) begin
                count     <= {WIDTH{1'b0}};
                tick_1sec <= 1'b1;
            end else begin
                count     <= count + 1'b1;
                tick_1sec <= 1'b0;
            end
        end
    end

endmodule
