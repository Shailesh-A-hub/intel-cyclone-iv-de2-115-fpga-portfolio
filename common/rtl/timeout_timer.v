//=============================================================================
// Module: timeout_timer
// Description: Retriggerable countdown timeout timer with runtime-configurable
//              duration, start/retrigger/cancel control, and remaining time output.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module timeout_timer #(
    parameter integer WIDTH = 32
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,          // Trigger timer to begin counting
    input  wire             retrigger,      // Reload timer duration while running
    input  wire             cancel,         // Abort timer immediately
    input  wire             tick_enable,    // Clock enable tick (e.g. 1ms or 1s strobe)
    input  wire [WIDTH-1:0] duration,       // Countdown duration in tick units
    output reg              active,         // High while timer is counting down
    output reg              expired,        // 1-cycle pulse upon timeout completion
    output reg  [WIDTH-1:0] remaining_time  // Current remaining count
);

    always @(posedge clk) begin
        if (rst) begin
            active         <= 1'b0;
            expired        <= 1'b0;
            remaining_time <= {WIDTH{1'b0}};
        end else begin
            expired <= 1'b0; // Default pulse low

            if (cancel) begin
                active         <= 1'b0;
                remaining_time <= {WIDTH{1'b0}};
            end else if (start || (active && retrigger)) begin
                if (duration == {WIDTH{1'b0}}) begin
                    // Zero duration triggers immediate expiration
                    active         <= 1'b0;
                    expired        <= 1'b1;
                    remaining_time <= {WIDTH{1'b0}};
                end else begin
                    active         <= 1'b1;
                    remaining_time <= duration;
                end
            end else if (active) begin
                if (tick_enable) begin
                    if (remaining_time <= 1) begin
                        active         <= 1'b0;
                        expired        <= 1'b1;
                        remaining_time <= {WIDTH{1'b0}};
                    end else begin
                        remaining_time <= remaining_time - 1'b1;
                    end
                end
            end
        end
    end

endmodule
