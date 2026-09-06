//=============================================================================
// Module: pwm_generator
// Description: Parameterized PWM generator with programmable frequency prescaler,
//              period, and duty cycle. Suitable for buzzer tone generation,
//              motor control, and LED brightness regulation.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module pwm_generator #(
    parameter integer RESOLUTION_BITS = 16
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         enable,       // 1 = active PWM, 0 = output 0
    input  wire [15:0]                  prescaler,    // Clock divider: 0 = div by 1, 1 = div by 2, etc.
    input  wire [RESOLUTION_BITS-1:0]   period,       // Total period in prescaled ticks
    input  wire [RESOLUTION_BITS-1:0]   duty_cycle,   // High-time duration in prescaled ticks
    output reg                          pwm_out,      // Modulated PWM output
    output reg                          cycle_end     // 1-cycle pulse at completion of each period
);

    reg [15:0] prescale_cnt;
    wire prescale_tick = (prescale_cnt >= prescaler);

    // Prescaler logic
    always @(posedge clk) begin
        if (rst || !enable) begin
            prescale_cnt <= 16'd0;
        end else begin
            if (prescale_tick) begin
                prescale_cnt <= 16'd0;
            end else begin
                prescale_cnt <= prescale_cnt + 1'b1;
            end
        end
    end

    // PWM period counter
    reg [RESOLUTION_BITS-1:0] pwm_cnt;

    always @(posedge clk) begin
        if (rst || !enable) begin
            pwm_cnt   <= {RESOLUTION_BITS{1'b0}};
            pwm_out   <= 1'b0;
            cycle_end <= 1'b0;
        end else begin
            cycle_end <= 1'b0;
            if (prescale_tick) begin
                if (pwm_cnt >= period - 1) begin
                    pwm_cnt   <= {RESOLUTION_BITS{1'b0}};
                    cycle_end <= 1'b1;
                end else begin
                    pwm_cnt <= pwm_cnt + 1'b1;
                end

                // Generate output based on comparison
                if (duty_cycle == {RESOLUTION_BITS{1'b0}}) begin
                    pwm_out <= 1'b0; // 0% duty cycle
                end else if (duty_cycle >= period) begin
                    pwm_out <= 1'b1; // 100% duty cycle
                end else begin
                    pwm_out <= (pwm_cnt < duty_cycle);
                end
            end
        end
    end

endmodule
