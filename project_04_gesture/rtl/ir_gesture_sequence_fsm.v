//=============================================================================
// Module: ir_gesture_sequence_fsm
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Implements a 2-step sequence recognizer across 4 IR sensors:
//              - LEFT -> CENTER   = SELECT / Cursor Down
//              - RIGHT -> CENTER  = BACK / Cursor Up
//              - CENTER -> CONFIRM = CONFIRM Selection
//              Includes ~1.5-second timeout window and false-trigger rejection.
//              Provides visual step 1 and step 2 feedback for LED chase effect.
//              Includes Mode Select Mux to bypass IR with manual test pushbuttons.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module ir_gesture_sequence_fsm #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer TIMEOUT_MS  = 1500,       // 1.5s timeout window
    parameter integer SIMULATION  = 0
)(
    input  wire clk,
    input  wire rst,

    // Debounced IR Sensor Inputs (Active-High)
    input  wire ir_l,       // Left sensor
    input  wire ir_c,       // Center sensor
    input  wire ir_r,       // Right sensor
    input  wire ir_k,       // Confirm sensor

    // Mode Selection & Manual Buttons
    input  wire sw_manual_mode,     // 0 = Gesture Mode, 1 = Manual Mode
    input  wire btn_select_pulse,   // Manual step down
    input  wire btn_back_pulse,     // Manual step up
    input  wire btn_confirm_pulse,  // Manual confirm

    // Gesture Output Pulses (single cycle)
    output reg  gesture_select_pulse,
    output reg  gesture_back_pulse,
    output reg  gesture_confirm_pulse,

    // LED Chase / Progress Indicators
    output reg  step1_active,       // LEDG[0]: First sensor detected
    output reg  step2_confirmed     // LEDG[1]: Sequence completed
);

    localparam integer TIMEOUT_CYCLES = (SIMULATION) ? 7_500 : ((CLK_FREQ_HZ / 1000) * TIMEOUT_MS);
    localparam integer CONFIRM_HOLD   = (SIMULATION) ? 500   : (CLK_FREQ_HZ / 10); // 100ms LED pulse

    // Edge detectors for each sensor
    reg ir_l_r, ir_c_r, ir_r_r, ir_k_r;
    wire ir_l_edge = ir_l && !ir_l_r;
    wire ir_c_edge = ir_c && !ir_c_r;
    wire ir_r_edge = ir_r && !ir_r_r;
    wire ir_k_edge = ir_k && !ir_k_r;

    always @(posedge clk) begin
        if (rst) begin
            ir_l_r <= 1'b0;
            ir_c_r <= 1'b0;
            ir_r_r <= 1'b0;
            ir_k_r <= 1'b0;
        end else begin
            ir_l_r <= ir_l;
            ir_c_r <= ir_c;
            ir_r_r <= ir_r;
            ir_k_r <= ir_k;
        end
    end

    // FSM States
    localparam [2:0]
        S_IDLE          = 3'd0,
        S_LEFT_FIRST    = 3'd1, // Left triggered, waiting for Center
        S_RIGHT_FIRST   = 3'd2, // Right triggered, waiting for Center
        S_CENTER_FIRST  = 3'd3, // Center triggered, waiting for Confirm
        S_CONFIRMED     = 3'd4,
        S_WAIT_CLEAR    = 3'd5;

    reg [2:0] state, next_state;
    reg [$clog2(TIMEOUT_CYCLES):0] timer;
    reg timer_en, timer_rst;

    reg [1:0] detected_gesture; // 1=Select, 2=Back, 3=Confirm
    reg [1:0] next_detected_gesture;

    // Timeout counter
    always @(posedge clk) begin
        if (rst || timer_rst) begin
            timer <= 0;
        end else if (timer_en) begin
            if (timer < TIMEOUT_CYCLES)
                timer <= timer + 1'b1;
        end
    end

    wire timeout = (timer >= TIMEOUT_CYCLES);

    // Confirmation LED pulse hold timer
    reg [$clog2(CONFIRM_HOLD):0] confirm_timer;
    always @(posedge clk) begin
        if (rst) begin
            confirm_timer <= 0;
        end else if (state == S_CONFIRMED) begin
            confirm_timer <= CONFIRM_HOLD;
        end else if (confirm_timer > 0) begin
            confirm_timer <= confirm_timer - 1'b1;
        end
    end

    // State Register
    always @(posedge clk) begin
        if (rst) begin
            state            <= S_IDLE;
            detected_gesture <= 2'd0;
        end else begin
            state            <= next_state;
            detected_gesture <= next_detected_gesture;
        end
    end

    // Next State Logic (Automatic Gesture Recognition)
    reg auto_select_pulse;
    reg auto_back_pulse;
    reg auto_confirm_pulse;

    always @(*) begin
        next_state            = state;
        next_detected_gesture = detected_gesture;
        auto_select_pulse     = 1'b0;
        auto_back_pulse       = 1'b0;
        auto_confirm_pulse    = 1'b0;
        timer_en              = 1'b0;
        timer_rst             = 1'b0;

        case (state)
            S_IDLE: begin
                timer_rst = 1'b1;
                next_detected_gesture = 2'd0;
                if (ir_k_edge) begin
                    // Direct tap/hover on Confirm sensor (Sensor 4 on Linear Breadboard)
                    next_detected_gesture = 2'd3; // CONFIRM
                    next_state            = S_CONFIRMED;
                end else if (ir_l_edge) begin
                    next_state = S_LEFT_FIRST;
                end else if (ir_r_edge) begin
                    next_state = S_RIGHT_FIRST;
                end else if (ir_c_edge) begin
                    next_state = S_CENTER_FIRST;
                end
            end

            S_LEFT_FIRST: begin
                timer_en = 1'b1;
                // Left-to-Right swipe: Center or Right triggered
                if (ir_c_edge || ir_r_edge) begin
                    next_detected_gesture = 2'd1; // SELECT (Cursor Down)
                    next_state            = S_CONFIRMED;
                end else if (timeout) begin
                    next_state = S_IDLE; // False trigger abort
                end
            end

            S_RIGHT_FIRST: begin
                timer_en = 1'b1;
                // Right-to-Left swipe: Center or Left triggered
                if (ir_c_edge || ir_l_edge) begin
                    next_detected_gesture = 2'd2; // BACK (Cursor Up)
                    next_state            = S_CONFIRMED;
                end else if (timeout) begin
                    next_state = S_IDLE; // False trigger abort
                end
            end

            S_CENTER_FIRST: begin
                timer_en = 1'b1;
                if (ir_k_edge) begin
                    next_detected_gesture = 2'd3; // CONFIRM (T-shape Center->Down)
                    next_state            = S_CONFIRMED;
                end else if (timeout) begin
                    next_state = S_IDLE; // False trigger abort
                end
            end

            S_CONFIRMED: begin
                if (detected_gesture == 2'd1) auto_select_pulse = 1'b1;
                else if (detected_gesture == 2'd2) auto_back_pulse = 1'b1;
                else if (detected_gesture == 2'd3) auto_confirm_pulse = 1'b1;
                next_state = S_WAIT_CLEAR;
            end

            S_WAIT_CLEAR: begin
                // Return to idle when all sensors are clear
                if (!ir_l && !ir_c && !ir_r && !ir_k) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

    // Mode Select Mux (SW[0]): Gesture Mode vs Manual Test Mode
    always @(*) begin
        if (sw_manual_mode) begin
            // Manual test buttons bypass gesture FSM
            gesture_select_pulse  = btn_select_pulse;
            gesture_back_pulse    = btn_back_pulse;
            gesture_confirm_pulse = btn_confirm_pulse;
            step1_active          = 1'b0;
            step2_confirmed       = btn_confirm_pulse;
        end else begin
            gesture_select_pulse  = auto_select_pulse;
            gesture_back_pulse    = auto_back_pulse;
            gesture_confirm_pulse = auto_confirm_pulse;
            step1_active          = (state == S_LEFT_FIRST || state == S_RIGHT_FIRST || state == S_CENTER_FIRST);
            step2_confirmed       = (confirm_timer > 0);
        end
    end

endmodule
