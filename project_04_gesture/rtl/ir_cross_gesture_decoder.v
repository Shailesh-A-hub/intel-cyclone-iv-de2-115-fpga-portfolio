//=============================================================================
// Module: ir_cross_gesture_decoder
// Project: Project 4 - FPGA Contactless Gesture Recognition & Menu System
// Description: Translates spatial hand swipes across a 4-sensor optical IR cross
//              array (UP, DOWN, LEFT, RIGHT) into directional gesture commands.
//              Implements hardware debouncing, temporal swipe correlation (50ms-400ms),
//              and refractory lockout to eliminate false double-triggers.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module ir_cross_gesture_decoder #(
    parameter integer CLK_FREQ_HZ     = 50_000_000,
    parameter integer DEBOUNCE_MS     = 10,
    parameter integer SWIPE_WINDOW_MS = 400,
    parameter integer REFRACTORY_MS   = 250,
    parameter integer ACTIVE_LOW      = 1,   // Standard IR obstacle sensors pull LOW when obstacle detected
    parameter integer SIMULATION      = 0
)(
    input  wire        clk,
    input  wire        reset_n,

    // 4 Physical IR Sensor Inputs (e.g. from JP5 GPIO pins)
    input  wire        ir_raw_u,  // North sensor
    input  wire        ir_raw_d,  // South sensor
    input  wire        ir_raw_l,  // West sensor
    input  wire        ir_raw_r,  // East sensor

    // Classified Gesture Output
    output reg         gesture_valid,
    output reg  [2:0]  gesture_code,
    output reg  [31:0] gesture_ascii,
    output reg  [15:0] gesture_count,
    output wire [3:0]  sensor_active_led // [3]=R, [2]=L, [1]=D, [0]=U
);

    // Gesture Encodings matching system standard
    localparam [2:0]
        GESTURE_NONE    = 3'd0,
        GESTURE_UP      = 3'd1,
        GESTURE_DOWN    = 3'd2,
        GESTURE_LEFT    = 3'd3,
        GESTURE_RIGHT   = 3'd4,
        GESTURE_NEAR    = 3'd5,
        GESTURE_FAR     = 3'd6;

    // Timing parameters
    localparam integer DB_CYCLES = (SIMULATION) ? 500 : ((CLK_FREQ_HZ / 1000) * DEBOUNCE_MS);
    localparam integer WIN_CYCLES = (SIMULATION) ? 5_000 : ((CLK_FREQ_HZ / 1000) * SWIPE_WINDOW_MS);
    localparam integer REF_CYCLES = (SIMULATION) ? 3_000 : ((CLK_FREQ_HZ / 1000) * REFRACTORY_MS);

    // -------------------------------------------------------------------------
    // 1. Debounce and Polarity Normalization for 4 IR Sensors
    // -------------------------------------------------------------------------
    wire [3:0] raw_inputs = {ir_raw_r, ir_raw_l, ir_raw_d, ir_raw_u};
    wire [3:0] norm_inputs = (ACTIVE_LOW) ? ~raw_inputs : raw_inputs;

    reg [3:0] sync_0, sync_1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync_0 <= 4'b0000;
            sync_1 <= 4'b0000;
        end else begin
            sync_0 <= norm_inputs;
            sync_1 <= sync_0;
        end
    end

    // Debounce counters per channel
    reg [19:0] db_cnt [0:3];
    reg [3:0]  debounced_state;
    reg [3:0]  prev_state;
    wire [3:0] trigger_pulse;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_debouncers
            always @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    db_cnt[i]          <= 20'd0;
                    debounced_state[i] <= 1'b0;
                end else begin
                    if (sync_1[i] != debounced_state[i]) begin
                        if (db_cnt[i] >= DB_CYCLES) begin
                            debounced_state[i] <= sync_1[i];
                            db_cnt[i]          <= 20'd0;
                        end else begin
                            db_cnt[i] <= db_cnt[i] + 1'b1;
                        end
                    end else begin
                        db_cnt[i] <= 20'd0;
                    end
                end
            end
            assign trigger_pulse[i] = (debounced_state[i] && !prev_state[i]);
        end
    endgenerate

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            prev_state <= 4'b0000;
        else
            prev_state <= debounced_state;
    end

    assign sensor_active_led = debounced_state;

    wire pulse_u = trigger_pulse[0];
    wire pulse_d = trigger_pulse[1];
    wire pulse_l = trigger_pulse[2];
    wire pulse_r = trigger_pulse[3];

    // -------------------------------------------------------------------------
    // 2. Spatial Swipe Correlation State Machine
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE          = 3'd0,
        S_WAIT_X        = 3'd1, // Horizontal: left or right triggered first
        S_WAIT_Y        = 3'd2, // Vertical: up or down triggered first
        S_EMIT_GESTURE  = 3'd3,
        S_REFRACTORY    = 3'd4;

    reg [2:0]  state;
    reg [31:0] timer;
    reg [1:0]  first_axis; // 00: L first, 01: R first, 10: U first, 11: D first
    reg [2:0]  pending_gesture;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= S_IDLE;
            timer           <= 32'd0;
            first_axis      <= 2'b00;
            pending_gesture <= GESTURE_NONE;
            gesture_valid   <= 1'b0;
            gesture_code    <= GESTURE_NONE;
            gesture_ascii   <= "NONE";
            gesture_count   <= 16'd0;
        end else begin
            gesture_valid <= 1'b0; // Default pulse low

            case (state)
                S_IDLE: begin
                    timer <= 32'd0;
                    // Horizontal swipes take precedence or first detected
                    if (pulse_l) begin
                        first_axis <= 2'b00; // Left first
                        state      <= S_WAIT_X;
                    end else if (pulse_r) begin
                        first_axis <= 2'b01; // Right first
                        state      <= S_WAIT_X;
                    end else if (pulse_u) begin
                        first_axis <= 2'b10; // Up first
                        state      <= S_WAIT_Y;
                    end else if (pulse_d) begin
                        first_axis <= 2'b11; // Down first
                        state      <= S_WAIT_Y;
                    end
                end

                S_WAIT_X: begin
                    if (timer >= WIN_CYCLES) begin
                        // Timer expired without second sensor -> direct tap/point
                        pending_gesture <= (first_axis == 2'b00) ? GESTURE_LEFT : GESTURE_RIGHT;
                        state           <= S_EMIT_GESTURE;
                    end else begin
                        timer <= timer + 1'b1;
                        if (first_axis == 2'b00 && pulse_r) begin
                            // Left then Right -> SWIPE RIGHT
                            pending_gesture <= GESTURE_RIGHT;
                            state           <= S_EMIT_GESTURE;
                        end else if (first_axis == 2'b01 && pulse_l) begin
                            // Right then Left -> SWIPE LEFT
                            pending_gesture <= GESTURE_LEFT;
                            state           <= S_EMIT_GESTURE;
                        end
                    end
                end

                S_WAIT_Y: begin
                    if (timer >= WIN_CYCLES) begin
                        // Timer expired without second sensor -> direct tap/point
                        pending_gesture <= (first_axis == 2'b10) ? GESTURE_UP : GESTURE_DOWN;
                        state           <= S_EMIT_GESTURE;
                    end else begin
                        timer <= timer + 1'b1;
                        if (first_axis == 2'b10 && pulse_d) begin
                            // Up then Down -> SWIPE DOWN
                            pending_gesture <= GESTURE_DOWN;
                            state           <= S_EMIT_GESTURE;
                        end else if (first_axis == 2'b11 && pulse_u) begin
                            // Down then Up -> SWIPE UP
                            pending_gesture <= GESTURE_UP;
                            state           <= S_EMIT_GESTURE;
                        end
                    end
                end

                S_EMIT_GESTURE: begin
                    gesture_valid <= 1'b1;
                    gesture_code  <= pending_gesture;
                    gesture_count <= gesture_count + 1'b1;

                    case (pending_gesture)
                        GESTURE_UP:    gesture_ascii <= "UP  ";
                        GESTURE_DOWN:  gesture_ascii <= "DOWN";
                        GESTURE_LEFT:  gesture_ascii <= "LEFT";
                        GESTURE_RIGHT: gesture_ascii <= "RGHT";
                        default:       gesture_ascii <= "NONE";
                    endcase

                    timer <= 32'd0;
                    state <= S_REFRACTORY;
                end

                S_REFRACTORY: begin
                    if (timer >= REF_CYCLES) begin
                        // Wait until all sensors are cleared before accepting next gesture
                        if (debounced_state == 4'b0000)
                            state <= S_IDLE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
