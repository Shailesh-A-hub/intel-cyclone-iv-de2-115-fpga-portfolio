//=============================================================================
// Module: edge_detector
// Description: Multi-bit parameterized synchronous edge detector. Generates
//              registered single-cycle pulses on rising, falling, or both transitions.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module edge_detector #(
    parameter integer WIDTH = 1
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] signal_in,
    output reg  [WIDTH-1:0] rising_edge,
    output reg  [WIDTH-1:0] falling_edge,
    output reg  [WIDTH-1:0] both_edges
);

    reg [WIDTH-1:0] signal_d;

    always @(posedge clk) begin
        if (rst) begin
            signal_d     <= {WIDTH{1'b0}};
            rising_edge  <= {WIDTH{1'b0}};
            falling_edge <= {WIDTH{1'b0}};
            both_edges   <= {WIDTH{1'b0}};
        end else begin
            signal_d     <= signal_in;
            rising_edge  <= signal_in & ~signal_d;
            falling_edge <= ~signal_in & signal_d;
            both_edges   <= signal_in ^ signal_d;
        end
    end

endmodule
