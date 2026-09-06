//=============================================================================
// Testbench: tb_seven_seg
// Description: Self-checking testbench for seven_seg_hex and seven_seg_dec.
//=============================================================================

`timescale 1ns / 1ps

module tb_seven_seg;

    reg [3:0] hex_digit;
    reg       blank;
    wire [6:0] seg_hex;

    reg [3:0] dec_digit;
    reg       show_dash;
    wire [6:0] seg_dec;

    seven_seg_hex dut_hex (
        .hex_digit(hex_digit),
        .blank(blank),
        .seg_out(seg_hex)
    );

    seven_seg_dec dut_dec (
        .dec_digit(dec_digit),
        .blank(blank),
        .show_dash(show_dash),
        .seg_out(seg_dec)
    );

    integer errors = 0;
    integer i;

    initial begin
        blank = 0;
        show_dash = 0;

        // Verify all 16 hex digits
        for (i = 0; i < 16; i = i + 1) begin
            hex_digit = i[3:0];
            #10;
            case (i)
                0: if (seg_hex !== 7'b100_0000) begin $display("HEX 0 mismatch"); errors = errors + 1; end
                1: if (seg_hex !== 7'b111_1001) begin $display("HEX 1 mismatch"); errors = errors + 1; end
                2: if (seg_hex !== 7'b010_0100) begin $display("HEX 2 mismatch"); errors = errors + 1; end
                3: if (seg_hex !== 7'b011_0000) begin $display("HEX 3 mismatch"); errors = errors + 1; end
                4: if (seg_hex !== 7'b001_1001) begin $display("HEX 4 mismatch"); errors = errors + 1; end
                5: if (seg_hex !== 7'b001_0010) begin $display("HEX 5 mismatch"); errors = errors + 1; end
                6: if (seg_hex !== 7'b000_0010) begin $display("HEX 6 mismatch"); errors = errors + 1; end
                7: if (seg_hex !== 7'b111_1000) begin $display("HEX 7 mismatch"); errors = errors + 1; end
                8: if (seg_hex !== 7'b000_0000) begin $display("HEX 8 mismatch"); errors = errors + 1; end
                9: if (seg_hex !== 7'b001_0000) begin $display("HEX 9 mismatch"); errors = errors + 1; end
                10: if (seg_hex !== 7'b000_1000) begin $display("HEX A mismatch"); errors = errors + 1; end
                11: if (seg_hex !== 7'b000_0011) begin $display("HEX B mismatch"); errors = errors + 1; end
                12: if (seg_hex !== 7'b100_0110) begin $display("HEX C mismatch"); errors = errors + 1; end
                13: if (seg_hex !== 7'b010_0001) begin $display("HEX D mismatch"); errors = errors + 1; end
                14: if (seg_hex !== 7'b000_0110) begin $display("HEX E mismatch"); errors = errors + 1; end
                15: if (seg_hex !== 7'b000_1110) begin $display("HEX F mismatch"); errors = errors + 1; end
            endcase
        end

        // Test blanking
        blank = 1;
        #10;
        if (seg_hex !== 7'b111_1111 || seg_dec !== 7'b111_1111) begin
            $display("Blanking failed");
            errors = errors + 1;
        end
        blank = 0;

        // Test decimal dash
        show_dash = 1;
        #10;
        if (seg_dec !== 7'b011_1111) begin
            $display("Decimal dash failed");
            errors = errors + 1;
        end
        show_dash = 0;

        // Test decimal digits 0-9
        for (i = 0; i < 10; i = i + 1) begin
            dec_digit = i[3:0];
            #10;
            if (seg_dec[6:0] == 7'b111_1111) begin
                $display("Decimal %0d blank error", i);
                errors = errors + 1;
            end
        end

        #20;
        if (errors == 0) begin
            $display("=== TB_SEVEN_SEG: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_SEVEN_SEG: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
