// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   pump_controller_fsm.v
// Description: Safety-critical pump and relay actuator FSM.
//              Enforces:
//                - Dual-threshold hysteresis control
//                - Minimum ON runtime protection (motor short-cycle prevention)
//                - Minimum OFF rest duration (soil absorption & winding cooling)
//                - Immediate rain sensor lockout
//                - Manual override prioritization
//                - Watering cycle count and cumulative seconds accumulation
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module pump_controller_fsm #(
    parameter MIN_ON_SECONDS  = 5,
    parameter MIN_OFF_SECONDS = 10
)(
    input  wire        clk,
    input  wire        rst_n,

    // Sensor & Threshold Inputs
    input  wire [6:0]  moisture_percent,
    input  wire [6:0]  turn_on_threshold,
    input  wire [6:0]  turn_off_threshold,

    // Safety & Override Controls
    input  wire        rain_detected,
    input  wire        manual_override,
    input  wire        sensor_fault,

    // Timebase Tick (1 Hz nominal)
    input  wire        sec_tick,

    // Pump Outputs
    output reg         relay_pump_ctrl,        // 1 = Energize relay, 0 = De-energize
    output reg         pump_is_running,
    output reg         rain_lockout_active,
    output reg         manual_override_active,
    output reg  [2:0]  fsm_state_id,

    // Telemetry Statistics
    output reg  [15:0] watering_cycles_count,
    output reg  [31:0] total_watering_seconds
);

    // ------------------------------------------------------------------------
    // FSM State Encoding
    // ------------------------------------------------------------------------
    localparam [2:0]
        ST_OFF_READY     = 3'd0,
        ST_RUN_MIN_ON    = 3'd1,
        ST_RUN_NORMAL    = 3'd2,
        ST_MIN_OFF_WAIT  = 3'd3,
        ST_RAIN_LOCKOUT  = 3'd4,
        ST_MANUAL_ON     = 3'd5;

    reg [2:0]   state;
    reg [15:0]  on_timer_sec;
    reg [15:0]  off_timer_sec;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_OFF_READY;
            relay_pump_ctrl        <= 1'b0;
            pump_is_running        <= 1'b0;
            rain_lockout_active    <= 1'b0;
            manual_override_active <= 1'b0;
            fsm_state_id           <= ST_OFF_READY;
            on_timer_sec           <= 16'd0;
            off_timer_sec          <= 16'd0;
            watering_cycles_count  <= 16'd0;
            total_watering_seconds <= 32'd0;
        end else begin
            // Accumulate total watering runtime
            if (relay_pump_ctrl && sec_tick) begin
                total_watering_seconds <= total_watering_seconds + 1'b1;
            end

            fsm_state_id <= state;

            case (state)
                // ------------------------------------------------------------
                // ST_OFF_READY: Pump is OFF and available for actuation
                // ------------------------------------------------------------
                ST_OFF_READY: begin
                    relay_pump_ctrl        <= 1'b0;
                    pump_is_running        <= 1'b0;
                    manual_override_active <= 1'b0;
                    rain_lockout_active    <= 1'b0;
                    on_timer_sec           <= 16'd0;
                    off_timer_sec          <= 16'd0;

                    if (rain_detected) begin
                        state <= ST_RAIN_LOCKOUT;
                    end else if (manual_override) begin
                        relay_pump_ctrl       <= 1'b1;
                        pump_is_running       <= 1'b1;
                        watering_cycles_count <= watering_cycles_count + 1'b1;
                        state                 <= ST_MANUAL_ON;
                    end else if (!sensor_fault && (moisture_percent < turn_on_threshold)) begin
                        // Trigger automatic watering
                        relay_pump_ctrl       <= 1'b1;
                        pump_is_running       <= 1'b1;
                        watering_cycles_count <= watering_cycles_count + 1'b1;
                        state                 <= ST_RUN_MIN_ON;
                    end
                end

                // ------------------------------------------------------------
                // ST_RUN_MIN_ON: Enforces minimum ON duration to protect motor
                // ------------------------------------------------------------
                ST_RUN_MIN_ON: begin
                    relay_pump_ctrl        <= 1'b1;
                    pump_is_running        <= 1'b1;
                    manual_override_active <= 1'b0;
                    rain_lockout_active    <= 1'b0;

                    if (rain_detected) begin
                        // Emergency rain abort
                        relay_pump_ctrl <= 1'b0;
                        pump_is_running <= 1'b0;
                        state           <= ST_RAIN_LOCKOUT;
                    end else begin
                        if (sec_tick) begin
                            on_timer_sec <= on_timer_sec + 1'b1;
                        end

                        if (on_timer_sec >= MIN_ON_SECONDS) begin
                            state <= ST_RUN_NORMAL;
                        end
                    end
                end

                // ------------------------------------------------------------
                // ST_RUN_NORMAL: Automatic watering until moisture restored
                // ------------------------------------------------------------
                ST_RUN_NORMAL: begin
                    relay_pump_ctrl        <= 1'b1;
                    pump_is_running        <= 1'b1;
                    manual_override_active <= 1'b0;
                    rain_lockout_active    <= 1'b0;

                    if (rain_detected) begin
                        relay_pump_ctrl <= 1'b0;
                        pump_is_running <= 1'b0;
                        state           <= ST_RAIN_LOCKOUT;
                    end else if (manual_override) begin
                        state <= ST_MANUAL_ON;
                    end else if (sensor_fault || (moisture_percent >= turn_off_threshold)) begin
                        // Soil adequately moist or sensor failed -> Stop pump
                        relay_pump_ctrl <= 1'b0;
                        pump_is_running <= 1'b0;
                        off_timer_sec   <= 16'd0;
                        state           <= ST_MIN_OFF_WAIT;
                    end
                end

                // ------------------------------------------------------------
                // ST_MIN_OFF_WAIT: Enforces rest period before next cycle
                // ------------------------------------------------------------
                ST_MIN_OFF_WAIT: begin
                    relay_pump_ctrl        <= 1'b0;
                    pump_is_running        <= 1'b0;
                    manual_override_active <= 1'b0;
                    rain_lockout_active    <= 1'b0;

                    if (rain_detected) begin
                        state <= ST_RAIN_LOCKOUT;
                    end else if (manual_override) begin
                        // Manual override can break rest period if urgently commanded
                        relay_pump_ctrl       <= 1'b1;
                        pump_is_running       <= 1'b1;
                        watering_cycles_count <= watering_cycles_count + 1'b1;
                        state                 <= ST_MANUAL_ON;
                    end else begin
                        if (sec_tick) begin
                            off_timer_sec <= off_timer_sec + 1'b1;
                        end

                        if (off_timer_sec >= MIN_OFF_SECONDS) begin
                            state <= ST_OFF_READY;
                        end
                    end
                end

                // ------------------------------------------------------------
                // ST_RAIN_LOCKOUT: Safety lockout while rain sensor active
                // ------------------------------------------------------------
                ST_RAIN_LOCKOUT: begin
                    relay_pump_ctrl        <= 1'b0;
                    pump_is_running        <= 1'b0;
                    rain_lockout_active    <= 1'b1;
                    manual_override_active <= 1'b0;
                    off_timer_sec          <= 16'd0;

                    if (!rain_detected) begin
                        // Rain cleared -> Enter rest period to ensure water absorbs
                        state <= ST_MIN_OFF_WAIT;
                    end
                end

                // ------------------------------------------------------------
                // ST_MANUAL_ON: User forced actuation
                // ------------------------------------------------------------
                ST_MANUAL_ON: begin
                    relay_pump_ctrl        <= 1'b1;
                    pump_is_running        <= 1'b1;
                    manual_override_active <= 1'b1;
                    rain_lockout_active    <= 1'b0;

                    if (rain_detected) begin
                        // Rain lockout takes precedence over manual override
                        relay_pump_ctrl <= 1'b0;
                        pump_is_running <= 1'b0;
                        state           <= ST_RAIN_LOCKOUT;
                    end else if (!manual_override) begin
                        // User released manual override
                        relay_pump_ctrl <= 1'b0;
                        pump_is_running <= 1'b0;
                        off_timer_sec   <= 16'd0;
                        state           <= ST_MIN_OFF_WAIT;
                    end
                end

                default: state <= ST_OFF_READY;
            endcase
        end
    end

endmodule
