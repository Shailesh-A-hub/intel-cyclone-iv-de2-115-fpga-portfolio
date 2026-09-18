//=============================================================================
// Module: ir_direction_fsm
// Project: Basic #3 - IR-Based Occupancy / Entry-Exit Counter
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Determines entry vs exit from the activation sequence of two IR
//              break-beam sensors. If IR_A triggers then IR_B triggers within
//              a 1.0-second timeout window, an entry_pulse is generated.
//              If IR_B triggers then IR_A triggers within 1.0s, an exit_pulse
//              is generated. Incomplete triggers reset silently to IDLE.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module ir_direction_fsm #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer TIMEOUT_MS  = 1000,        // 1.0 second timeout window
    parameter integer SIMULATION  = 0
)(
    input  wire clk,
    input  wire rst_n,          // Active-low reset

    // Debounced, active-high pulse or level from IR sensors
    input  wire ir_a_active,    // Outer sensor active (beam broken)
    input  wire ir_b_active,    // Inner sensor active (beam broken)

    // Classified Direction Pulses (single-cycle)
    output reg  entry_pulse,
    output reg  exit_pulse,

    // Debug / State outputs
    output reg  [2:0] state_out
);

    // Timeout cycles calculation
    localparam integer TIMEOUT_CYCLES = (SIMULATION) ? 5_000 : ((CLK_FREQ_HZ / 1000) * TIMEOUT_MS);

    // FSM States
    localparam [2:0]
        S_IDLE            = 3'd0,
        S_A_TRIGGERED     = 3'd1,
        S_B_TRIGGERED     = 3'd2,
        S_ENTRY_CONFIRMED = 3'd3,
        S_EXIT_CONFIRMED  = 3'd4,
        S_WAIT_CLEAR      = 3'd5;

    reg [2:0] state, next_state;
    reg [$clog2(TIMEOUT_CYCLES):0] timer;
    reg timer_en, timer_rst;

    // Detect rising edges of sensor activations
    reg ir_a_r, ir_b_r;
    wire ir_a_edge = ir_a_active && !ir_a_r;
    wire ir_b_edge = ir_b_active && !ir_b_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_a_r <= 1'b0;
            ir_b_r <= 1'b0;
        end else begin
            ir_a_r <= ir_a_active;
            ir_b_r <= ir_b_active;
        end
    end

    // Timer Counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer <= 0;
        end else if (timer_rst) begin
            timer <= 0;
        end else if (timer_en) begin
            if (timer < TIMEOUT_CYCLES)
                timer <= timer + 1'b1;
        end
    end

    wire timeout = (timer >= TIMEOUT_CYCLES);

    // State Register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next State Logic
    always @(*) begin
        next_state   = state;
        entry_pulse  = 1'b0;
        exit_pulse   = 1'b0;
        timer_en     = 1'b0;
        timer_rst    = 1'b0;
        state_out    = state;

        case (state)
            S_IDLE: begin
                timer_rst = 1'b1;
                if (ir_a_edge) begin
                    next_state = S_A_TRIGGERED;
                end else if (ir_b_edge) begin
                    next_state = S_B_TRIGGERED;
                end
            end

            S_A_TRIGGERED: begin
                timer_en = 1'b1;
                if (ir_b_edge) begin
                    next_state = S_ENTRY_CONFIRMED;
                end else if (timeout) begin
                    next_state = S_IDLE; // False trigger cancellation
                end
            end

            S_B_TRIGGERED: begin
                timer_en = 1'b1;
                if (ir_a_edge) begin
                    next_state = S_EXIT_CONFIRMED;
                end else if (timeout) begin
                    next_state = S_IDLE; // False trigger cancellation
                end
            end

            S_ENTRY_CONFIRMED: begin
                entry_pulse = 1'b1;
                next_state  = S_WAIT_CLEAR;
            end

            S_EXIT_CONFIRMED: begin
                exit_pulse = 1'b1;
                next_state = S_WAIT_CLEAR;
            end

            S_WAIT_CLEAR: begin
                // Wait until both beams are clear before returning to IDLE
                if (!ir_a_active && !ir_b_active) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
