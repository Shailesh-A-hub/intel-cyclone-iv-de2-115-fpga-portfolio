//=============================================================================
// Module: seven_seg_hex
// Description: Active-low 7-segment hexadecimal decoder (0-F).
//              Maps 4-bit binary input to active-low segment patterns {g,f,e,d,c,b,a}.
//              Compatible with DE2-115 HEX0-HEX7 displays.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module seven_seg_hex (
    input  wire [3:0] hex_digit,  // 4-bit hexadecimal value (0x0 - 0xF)
    input  wire       blank,      // Blanking input (1 = blank/turn off display)
    output reg  [6:0] seg_out     // Active-low segments: {g, f, e, d, c, b, a}
);

    always @(*) begin
        if (blank) begin
            seg_out = 7'b111_1111; // All segments OFF
        end else begin
            case (hex_digit)
                4'h0: seg_out = 7'b100_0000; // 0
                4'h1: seg_out = 7'b111_1001; // 1
                4'h2: seg_out = 7'b010_0100; // 2
                4'h3: seg_out = 7'b011_0000; // 3
                4'h4: seg_out = 7'b001_1001; // 4
                4'h5: seg_out = 7'b001_0010; // 5
                4'h6: seg_out = 7'b000_0010; // 6
                4'h7: seg_out = 7'b111_1000; // 7
                4'h8: seg_out = 7'b000_0000; // 8
                4'h9: seg_out = 7'b001_0000; // 9
                4'hA: seg_out = 7'b000_1000; // A
                4'hB: seg_out = 7'b000_0011; // b
                4'hC: seg_out = 7'b100_0110; // C
                4'hD: seg_out = 7'b010_0001; // d
                4'hE: seg_out = 7'b000_0110; // E
                4'hF: seg_out = 7'b000_1110; // F
                default: seg_out = 7'b111_1111;
            endcase
        end
    end

endmodule
