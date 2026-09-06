//=============================================================================
// Module: gesture_decoder
// Description: Multi-directional spatial gesture classification engine for
//              optical photodiode datasets (U, D, L, R) from APDS-9960.
//              Tracks trajectory phase vectors, detects differential peaks,
//              and classifies UP, DOWN, LEFT, RIGHT, NEAR, and FAR gestures.
//              Includes synthetic event injection for deterministic bench test.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gesture_decoder #(
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer REFRACTORY_MS = 250,
    parameter integer SIMULATION    = 0
)(
    input  wire        clk,
    input  wire        reset_n,

    // Real sensor photodiode sample stream
    input  wire [7:0]  raw_u,
    input  wire [7:0]  raw_d,
    input  wire [7:0]  raw_l,
    input  wire [7:0]  raw_r,
    input  wire        sample_valid,

    // Synthetic gesture event injection
    input  wire        synth_mode,
    input  wire        synth_trigger,
    input  wire [2:0]  synth_gesture,

    // Classified gesture event output
    output reg         gesture_valid,
    output reg  [2:0]  gesture_code,
    output reg  [31:0] gesture_ascii,
    output reg  [15:0] gesture_count,
    output reg         gesture_active,
    output reg  [2:0]  fsm_state_dbg
);

    // Gesture Encodings
    localparam [2:0]
        GESTURE_NONE    = 3'd0,
        GESTURE_UP      = 3'd1,
        GESTURE_DOWN    = 3'd2,
        GESTURE_LEFT    = 3'd3,
        GESTURE_RIGHT   = 3'd4,
        GESTURE_NEAR    = 3'd5,
        GESTURE_FAR     = 3'd6,
        GESTURE_INVALID = 3'd7;

    // Detection thresholds
    localparam [9:0] ENTER_THRESHOLD = 10'd50; // Sum U+D+L+R to start tracking
    localparam [9:0] EXIT_THRESHOLD  = 10'd30; // Sum U+D+L+R to end tracking
    localparam signed [9:0] DIFF_DELTA = 10'sd15; // Minimum difference to identify direction

    // Refractory timer cycles (lockout period after gesture)
    localparam integer REFRACTORY_CYCLES = (SIMULATION) ? 5_000 : ((CLK_FREQ_HZ / 1000) * REFRACTORY_MS);
    localparam integer TIMEOUT_CYCLES    = (SIMULATION) ? 50_000 : (CLK_FREQ_HZ / 2); // 500ms gesture window

    // Decoder FSM States
    localparam [2:0]
        ST_IDLE       = 3'd0,
        ST_TRACKING   = 3'd1,
        ST_CLASSIFY   = 3'd2,
        ST_REFRACTORY = 3'd3;

    reg [2:0]  state;
    reg [23:0] timer_cnt;

    // Trackers for first-half and second-half differentials
    reg signed [9:0] diff_ud_phase1, diff_ud_phase2;
    reg signed [9:0] diff_lr_phase1, diff_lr_phase2;
    reg [7:0] sample_count_in_gesture;
    reg [9:0] max_sum;

    wire [9:0] current_sum = raw_u + raw_d + raw_l + raw_r;
    wire signed [9:0] cur_diff_ud = $signed({2'b00, raw_u}) - $signed({2'b00, raw_d});
    wire signed [9:0] cur_diff_lr = $signed({2'b00, raw_l}) - $signed({2'b00, raw_r});

    // Helper task to assign ASCII representation
    function [31:0] get_ascii;
        input [2:0] code;
        begin
            case (code)
                GESTURE_UP:      get_ascii = "UP  ";
                GESTURE_DOWN:    get_ascii = "DOWN";
                GESTURE_LEFT:    get_ascii = "LEFT";
                GESTURE_RIGHT:   get_ascii = "RGHT";
                GESTURE_NEAR:    get_ascii = "NEAR";
                GESTURE_FAR:     get_ascii = "FAR ";
                GESTURE_INVALID: get_ascii = "INVL";
                default:         get_ascii = "NONE";
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!reset_n) begin
            state                   <= ST_IDLE;
            gesture_valid           <= 1'b0;
            gesture_code            <= GESTURE_NONE;
            gesture_ascii           <= "NONE";
            gesture_count           <= 16'd0;
            gesture_active          <= 1'b0;
            fsm_state_dbg           <= ST_IDLE;
            timer_cnt               <= 24'd0;
            diff_ud_phase1          <= 10'sd0;
            diff_ud_phase2          <= 10'sd0;
            diff_lr_phase1          <= 10'sd0;
            diff_lr_phase2          <= 10'sd0;
            sample_count_in_gesture <= 8'd0;
            max_sum                 <= 10'd0;
        end else begin
            gesture_valid <= 1'b0; // Default single-cycle pulse
            fsm_state_dbg <= state;

            // Synthetic injection bypass
            if (synth_mode) begin
                state          <= ST_IDLE;
                gesture_active <= 1'b0;
                if (synth_trigger && (synth_gesture != GESTURE_NONE)) begin
                    gesture_valid <= 1'b1;
                    gesture_code  <= synth_gesture;
                    gesture_ascii <= get_ascii(synth_gesture);
                    gesture_count <= gesture_count + 1'b1;
                end
            end else begin
                // Physical sensor decoding state machine
                case (state)
                    ST_IDLE: begin
                        gesture_active          <= 1'b0;
                        sample_count_in_gesture <= 8'd0;
                        timer_cnt               <= 24'd0;
                        max_sum                 <= 10'd0;
                        diff_ud_phase1          <= 10'sd0;
                        diff_ud_phase2          <= 10'sd0;
                        diff_lr_phase1          <= 10'sd0;
                        diff_lr_phase2          <= 10'sd0;

                        if (sample_valid && (current_sum >= ENTER_THRESHOLD)) begin
                            gesture_active <= 1'b1;
                            diff_ud_phase1 <= cur_diff_ud;
                            diff_lr_phase1 <= cur_diff_lr;
                            max_sum        <= current_sum;
                            state          <= ST_TRACKING;
                        end
                    end

                    ST_TRACKING: begin
                        timer_cnt <= timer_cnt + 1'b1;

                        if (sample_valid) begin
                            sample_count_in_gesture <= sample_count_in_gesture + 1'b1;
                            
                            if (current_sum > max_sum) begin
                                max_sum <= current_sum;
                            end

                            // Latch second phase differentials on later samples
                            diff_ud_phase2 <= cur_diff_ud;
                            diff_lr_phase2 <= cur_diff_lr;

                            // If proximity drops below exit threshold, finish gesture
                            if (current_sum < EXIT_THRESHOLD && sample_count_in_gesture >= 8'd2) begin
                                state <= ST_CLASSIFY;
                            end
                        end

                        // Timeout safety if object lingers or leaves abruptly
                        if (timer_cnt >= TIMEOUT_CYCLES) begin
                            if (sample_count_in_gesture >= 8'd2) begin
                                state <= ST_CLASSIFY;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end
                    end

                    ST_CLASSIFY: begin
                        gesture_active <= 1'b0;
                        gesture_valid  <= 1'b1;
                        timer_cnt      <= 24'd0;
                        gesture_count  <= gesture_count + 1'b1;

                        // Decision Logic:
                        // UP: Entered D heavy (diff_ud negative), exited U heavy (diff_ud positive)
                        if ((diff_ud_phase1 < -DIFF_DELTA) && (diff_ud_phase2 > DIFF_DELTA)) begin
                            gesture_code  <= GESTURE_UP;
                            gesture_ascii <= "UP  ";
                        // DOWN: Entered U heavy (diff_ud positive), exited D heavy (diff_ud negative)
                        end else if ((diff_ud_phase1 > DIFF_DELTA) && (diff_ud_phase2 < -DIFF_DELTA)) begin
                            gesture_code  <= GESTURE_DOWN;
                            gesture_ascii <= "DOWN";
                        // LEFT: Entered R heavy (diff_lr negative), exited L heavy (diff_lr positive)
                        end else if ((diff_lr_phase1 < -DIFF_DELTA) && (diff_lr_phase2 > DIFF_DELTA)) begin
                            gesture_code  <= GESTURE_LEFT;
                            gesture_ascii <= "LEFT";
                        // RIGHT: Entered L heavy (diff_lr positive), exited R heavy (diff_lr negative)
                        end else if ((diff_lr_phase1 > DIFF_DELTA) && (diff_lr_phase2 < -DIFF_DELTA)) begin
                            gesture_code  <= GESTURE_RIGHT;
                            gesture_ascii <= "RGHT";
                        // NEAR: Uniform elevation without large spatial deviation
                        end else if (max_sum >= 10'd180) begin
                            gesture_code  <= GESTURE_NEAR;
                            gesture_ascii <= "NEAR";
                        // FAR: Quick low magnitude sweep
                        end else if (max_sum >= 10'd60 && max_sum < 10'd100) begin
                            gesture_code  <= GESTURE_FAR;
                            gesture_ascii <= "FAR ";
                        // Ambiguous motion
                        end else begin
                            gesture_code  <= GESTURE_INVALID;
                            gesture_ascii <= "INVL";
                        end

                        state <= ST_REFRACTORY;
                    end

                    ST_REFRACTORY: begin
                        if (timer_cnt >= REFRACTORY_CYCLES) begin
                            state     <= ST_IDLE;
                            timer_cnt <= 24'd0;
                        end else begin
                            timer_cnt <= timer_cnt + 1'b1;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
