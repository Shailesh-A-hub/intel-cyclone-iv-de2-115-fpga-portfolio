//=============================================================================
// Module: seven_seg_dec
// Description: Active-low 7-segment decimal decoder (0-9) with leading-zero
//              blanking, negative sign, and error indicator capability.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module seven_seg_dec (
    input  wire [3:0] dec_digit,  // Decimal digit (0-9). Values > 9 display error '-'
    input  wire       blank,      // Blank display (1 = turn off)
    input  wire       show_dash,  // Force display of minus/dash sign '-'
    output reg  [6:0] seg_out     // Active-low segments: {g, f, e, d, c, b, a}
);

    always @(*) begin
        if (blank) begin
            seg_out = 7'b111_1111; // Blank
        end else if (show_dash) begin
            seg_out = 7'b011_1111; // Dash '-' (only segment g active)
        end else begin
            case (dec_digit)
                4'd0: seg_out = 7'b100_0000; // 0
                4'd1: seg_out = 7'b111_1001; // 1
                4'd2: seg_out = 7'b010_0100; // 2
                4'd3: seg_out = 7'b011_0000; // 3
                4'd4: seg_out = 7'b001_1001; // 4
                4'd5: seg_out = 7'b001_0010; // 5
                4'd6: seg_out = 7'b000_0010; // 6
                4'd7: seg_out = 7'b111_1000; // 7
                4'd8: seg_out = 7'b000_0000; // 8
                4'd9: seg_out = 7'b001_0000; // 9
                default: seg_out = 7'b011_1111; // Dash '-' for invalid decimal
            endcase
        end
    end

endmodule
