// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   alarm_buzzer_controller.v
// Description: Multi-mode alarm tone and cadence generator for piezo buzzer.
//              - SAFE:    Completely silent (0% duty cycle)
//              - CAUTION: Intermittent 1.0 kHz warning chirp (100ms on, 900ms off)
//              - DANGER:  Alternating 2.0 kHz / 2.5 kHz high-priority emergency siren
//              - FAULT:   500 Hz rapid warning pulses (100ms on, 100ms off)
//              Includes alarm mute / acknowledge latch.
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module alarm_buzzer_controller #(
    parameter CLK_FREQ_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [1:0]  risk_level,       // 00=SAFE, 01=CAUTION, 10=DANGER, 11=FAULT
    input  wire        alarm_mute_press, // Mute / acknowledge button pulse

    output wire        buzzer_pwm_out,
    output reg         alarm_active,
    output reg         alarm_muted
);

    localparam [1:0]
        LVL_SAFE    = 2'b00,
        LVL_CAUTION = 2'b01,
        LVL_DANGER  = 2'b10,
        LVL_FAULT   = 2'b11;

    // Millisecond cadence timer
    localparam MS_CYCLES = CLK_FREQ_HZ / 1_000;
    reg [$clog2(MS_CYCLES):0] ms_counter;
    reg [11:0] ms_tick_cnt; // Counts up to 4095 ms

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_counter  <= 0;
            ms_tick_cnt <= 12'd0;
        end else begin
            if (ms_counter >= MS_CYCLES - 1) begin
                ms_counter <= 0;
                if (ms_tick_cnt >= 12'd999)
                    ms_tick_cnt <= 12'd0;
                else
                    ms_tick_cnt <= ms_tick_cnt + 1'b1;
            end else begin
                ms_counter <= ms_counter + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Mute Logic
    // ------------------------------------------------------------------------
    reg [1:0] prev_risk_level;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_muted     <= 1'b0;
            prev_risk_level <= LVL_SAFE;
        end else begin
            prev_risk_level <= risk_level;

            // Automatically unmute if entering DANGER or level changes to higher severity
            if (risk_level == LVL_DANGER && prev_risk_level != LVL_DANGER) begin
                alarm_muted <= 1'b0;
            end else if (risk_level == LVL_SAFE) begin
                alarm_muted <= 1'b0;
            end else if (alarm_mute_press) begin
                alarm_muted <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Cadence and Tone Frequency Selection
    // ------------------------------------------------------------------------
    // PWM period = CLK_FREQ_HZ / TONE_HZ
    // 500 Hz  -> 100,000 cycles
    // 1000 Hz ->  50,000 cycles
    // 2000 Hz ->  25,000 cycles
    // 2500 Hz ->  20,000 cycles

    localparam PERIOD_500HZ  = CLK_FREQ_HZ / 500;
    localparam PERIOD_1000HZ = CLK_FREQ_HZ / 1000;
    localparam PERIOD_2000HZ = CLK_FREQ_HZ / 2000;
    localparam PERIOD_2500HZ = CLK_FREQ_HZ / 2500;

    reg [31:0] tone_period;
    reg [31:0] tone_duty;
    reg        sound_enable;

    always @(*) begin
        case (risk_level)
            LVL_SAFE: begin
                sound_enable = 1'b0;
                tone_period  = PERIOD_1000HZ;
                tone_duty    = 0;
            end

            LVL_CAUTION: begin
                // 100ms ON every 1000ms
                sound_enable = (ms_tick_cnt < 12'd100);
                tone_period  = PERIOD_1000HZ;
                tone_duty    = PERIOD_1000HZ / 4; // 25% duty
            end

            LVL_DANGER: begin
                // Siren toggling every 250ms (2000 Hz <-> 2500 Hz)
                sound_enable = 1'b1;
                if (ms_tick_cnt < 12'd250 || (ms_tick_cnt >= 12'd500 && ms_tick_cnt < 12'd750)) begin
                    tone_period = PERIOD_2000HZ;
                    tone_duty   = PERIOD_2000HZ / 2;
                end else begin
                    tone_period = PERIOD_2500HZ;
                    tone_duty   = PERIOD_2500HZ / 2;
                end
            end

            LVL_FAULT: begin
                // 500 Hz, 100ms on, 100ms off
                sound_enable = (ms_tick_cnt[7]); // Simple oscillation
                tone_period  = PERIOD_500HZ;
                tone_duty    = PERIOD_500HZ / 2;
            end

            default: begin
                sound_enable = 1'b0;
                tone_period  = PERIOD_1000HZ;
                tone_duty    = 0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_active <= 1'b0;
        end else begin
            alarm_active <= (risk_level != LVL_SAFE) && !alarm_muted;
        end
    end

    // ------------------------------------------------------------------------
    // PWM Generator Instance
    // ------------------------------------------------------------------------
    wire raw_pwm;
    wire [31:0] active_duty = (sound_enable && !alarm_muted) ? tone_duty : 32'd0;

    pwm_generator #(
        .RESOLUTION_BITS(16)
    ) u_pwm (
        .clk         (clk),
        .rst         (~rst_n),
        .enable      (sound_enable && !alarm_muted),
        .prescaler   (16'd0),
        .period      (tone_period[15:0]),
        .duty_cycle  (active_duty[15:0]),
        .pwm_out     (raw_pwm),
        .cycle_end   ()
    );

    assign buzzer_pwm_out = raw_pwm;

endmodule
