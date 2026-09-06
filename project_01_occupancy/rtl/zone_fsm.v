//=============================================================================
// Module: zone_fsm
// Project: Project 1 - Multi-Zone Occupancy & Energy-Saving Engine
// Description: Independent Zone Controller FSM. Manages VACANT, OCCUPIED, and
//              TIMEOUT states with motion retriggering, remaining countdown timer,
//              and stuck-at sensor fault detection.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module zone_fsm #(
    parameter integer ZONE_ID = 1
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        motion_in,        // Debounced motion/PIR trigger
    input  wire        tick_1s,          // 1-second pulse for timeout countdown
    input  wire [15:0] timeout_preset,   // Configurable timeout duration (seconds)
    input  wire [15:0] fault_timeout,    // Max continuous motion before stuck fault (seconds)
    output reg  [1:0]  state,            // 00=VACANT, 01=OCCUPIED, 10=TIMEOUT, 11=FAULT
    output wire        occupied_out,     // High in OCCUPIED and TIMEOUT
    output wire        light_req,        // High when zone demands illumination
    output wire        hvac_req,         // High when zone demands climate control
    output reg  [15:0] countdown_val,    // Remaining seconds before vacancy
    output reg         state_changed,    // 1-cycle pulse upon any state transition
    output reg         sensor_fault      // Asserted if sensor stuck active
);

    // State definitions
    localparam [1:0]
        S_VACANT   = 2'b00,
        S_OCCUPIED = 2'b01,
        S_TIMEOUT  = 2'b10,
        S_FAULT    = 2'b11;

    reg [1:0]  state_d;
    reg [15:0] stuck_timer;

    assign occupied_out = (state == S_OCCUPIED) || (state == S_TIMEOUT);
    assign light_req    = (state == S_OCCUPIED) || (state == S_TIMEOUT);
    assign hvac_req     = (state == S_OCCUPIED) || (state == S_TIMEOUT);

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_VACANT;
            state_d       <= S_VACANT;
            countdown_val <= 16'd0;
            stuck_timer   <= 16'd0;
            state_changed <= 1'b0;
            sensor_fault  <= 1'b0;
        end else begin
            state_d       <= state;
            state_changed <= (state != state_d);

            // Stuck-sensor fault detection logic
            if (motion_in) begin
                if (tick_1s) begin
                    if (fault_timeout > 0 && stuck_timer >= fault_timeout - 1) begin
                        sensor_fault <= 1'b1;
                    end else begin
                        stuck_timer <= stuck_timer + 1'b1;
                    end
                end
            end else begin
                stuck_timer  <= 16'd0;
                sensor_fault <= 1'b0;
            end

            // Core Occupancy FSM
            case (state)
                S_VACANT: begin
                    countdown_val <= 16'd0;
                    if (sensor_fault) begin
                        state <= S_FAULT;
                    end else if (motion_in) begin
                        countdown_val <= timeout_preset;
                        state         <= S_OCCUPIED;
                    end
                end

                S_OCCUPIED: begin
                    if (sensor_fault) begin
                        state <= S_FAULT;
                    end else if (motion_in) begin
                        // Retrigger timeout timer continuously while motion is detected
                        countdown_val <= timeout_preset;
                    end else begin
                        // Motion ceased; transition to TIMEOUT countdown state
                        state <= S_TIMEOUT;
                    end
                end

                S_TIMEOUT: begin
                    if (sensor_fault) begin
                        state <= S_FAULT;
                    end else if (motion_in) begin
                        // Motion retrigger during countdown -> immediate return to OCCUPIED
                        countdown_val <= timeout_preset;
                        state         <= S_OCCUPIED;
                    end else if (tick_1s) begin
                        if (countdown_val <= 16'd1) begin
                            countdown_val <= 16'd0;
                            state         <= S_VACANT; // Timeout expired -> VACANT
                        end else begin
                            countdown_val <= countdown_val - 1'b1;
                        end
                    end
                end

                S_FAULT: begin
                    countdown_val <= 16'd0;
                    // Automatically recover once sensor ceases continuous trigger
                    if (!sensor_fault && !motion_in) begin
                        state <= S_VACANT;
                    end
                end

                default: state <= S_VACANT;
            endcase
        end
    end

endmodule
