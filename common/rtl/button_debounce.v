//=============================================================================
// Module: button_debounce
// Description: Parameterized debouncer and glitch filter with built-in
//              metastability synchronizers and edge strobe generation.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module button_debounce #(
    parameter integer CLK_FREQ_HZ   = 50_000_000, // System clock frequency
    parameter integer DEBOUNCE_MS   = 20,         // Debounce stability period in ms
    parameter integer ACTIVE_LOW_IN = 1           // 1 for active-low input (e.g. DE2-115 keys)
)(
    input  wire clk,              // System clock
    input  wire rst,              // Synchronous active-high reset
    input  wire btn_in,           // Raw input from pushbutton or switch
    output reg  debounced_state,  // Filtered state (1 = pressed/active, 0 = released)
    output reg  pressed_pulse,    // 1-cycle pulse upon press transition
    output reg  released_pulse    // 1-cycle pulse upon release transition
);

    // Calculate count threshold for debounce duration
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNTER_WIDTH   = $clog2(DEBOUNCE_CYCLES + 1);

    // 2-stage input synchronizer to eliminate metastability
    reg sync_ff1, sync_ff2;
    wire raw_active = ACTIVE_LOW_IN ? (~btn_in) : btn_in;

    always @(posedge clk) begin
        if (rst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= raw_active;
            sync_ff2 <= sync_ff1;
        end
    end

    // Counter-based glitch integrator
    reg [COUNTER_WIDTH-1:0] debounce_timer;
    reg debounced_state_d;

    always @(posedge clk) begin
        if (rst) begin
            debounce_timer    <= {COUNTER_WIDTH{1'b0}};
            debounced_state   <= 1'b0;
            debounced_state_d <= 1'b0;
            pressed_pulse     <= 1'b0;
            released_pulse    <= 1'b0;
        end else begin
            debounced_state_d <= debounced_state;

            // If synchronized input differs from debounced state, run stability counter
            if (sync_ff2 != debounced_state) begin
                if (debounce_timer >= DEBOUNCE_CYCLES - 1) begin
                    debounced_state <= sync_ff2;
                    debounce_timer  <= {COUNTER_WIDTH{1'b0}};
                end else begin
                    debounce_timer  <= debounce_timer + 1'b1;
                end
            end else begin
                debounce_timer <= {COUNTER_WIDTH{1'b0}};
            end

            // Generate single-cycle edge strobes
            pressed_pulse  <= (debounced_state & ~debounced_state_d);
            released_pulse <= (~debounced_state & debounced_state_d);
        end
    end

endmodule
