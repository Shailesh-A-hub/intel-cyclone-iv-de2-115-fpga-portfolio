//=============================================================================
// Module: hanning_window
// Description: Multiplies incoming 16-bit signed audio samples by pre-computed
//              Hanning window coefficients: w(n) = 0.5 - 0.5*cos(2*pi*n / N)
//              in Q0.16 unsigned format to eliminate Gibbs phenomenon and
//              spectral leakage before FFT processing.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module hanning_window #(
    parameter integer BUFFER_SIZE = 512,
    parameter integer DATA_WIDTH  = 16
)(
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         in_valid,
    input  wire [$clog2(BUFFER_SIZE)-1:0] sample_idx,
    input  wire signed [DATA_WIDTH-1:0] sample_in,

    output reg                          out_valid,
    output reg  [$clog2(BUFFER_SIZE)-1:0] out_idx,
    output reg  signed [DATA_WIDTH-1:0] sample_out
);

    localparam ADDR_WIDTH = $clog2(BUFFER_SIZE);

    // 16-bit unsigned Hanning coefficient ROM
    // Approximation: w(n) = 32767 * (1 - cos(2*pi*n / N))
    // Can be represented via a 64/256/512 entry lookup table
    reg [15:0] window_rom [0:BUFFER_SIZE-1];
    integer i;

    initial begin
        if (BUFFER_SIZE == 64) begin
            window_rom[0] = 16'h0000;
            window_rom[1] = 16'h009E;
            window_rom[2] = 16'h0276;
            window_rom[3] = 16'h0583;
            window_rom[4] = 16'h09BE;
            window_rom[5] = 16'h0F1D;
            window_rom[6] = 16'h1592;
            window_rom[7] = 16'h1D0E;
            window_rom[8] = 16'h257D;
            window_rom[9] = 16'h2ECC;
            window_rom[10] = 16'h38E3;
            window_rom[11] = 16'h43A9;
            window_rom[12] = 16'h4F04;
            window_rom[13] = 16'h5AD8;
            window_rom[14] = 16'h6707;
            window_rom[15] = 16'h7374;
            window_rom[16] = 16'h7FFF;
            window_rom[17] = 16'h8C8B;
            window_rom[18] = 16'h98F8;
            window_rom[19] = 16'hA527;
            window_rom[20] = 16'hB0FB;
            window_rom[21] = 16'hBC56;
            window_rom[22] = 16'hC71C;
            window_rom[23] = 16'hD133;
            window_rom[24] = 16'hDA82;
            window_rom[25] = 16'hE2F1;
            window_rom[26] = 16'hEA6D;
            window_rom[27] = 16'hF0E2;
            window_rom[28] = 16'hF641;
            window_rom[29] = 16'hFA7C;
            window_rom[30] = 16'hFD89;
            window_rom[31] = 16'hFF61;
            window_rom[32] = 16'hFFFF;
            window_rom[33] = 16'hFF61;
            window_rom[34] = 16'hFD89;
            window_rom[35] = 16'hFA7C;
            window_rom[36] = 16'hF641;
            window_rom[37] = 16'hF0E2;
            window_rom[38] = 16'hEA6D;
            window_rom[39] = 16'hE2F1;
            window_rom[40] = 16'hDA82;
            window_rom[41] = 16'hD133;
            window_rom[42] = 16'hC71C;
            window_rom[43] = 16'hBC56;
            window_rom[44] = 16'hB0FB;
            window_rom[45] = 16'hA527;
            window_rom[46] = 16'h98F8;
            window_rom[47] = 16'h8C8B;
            window_rom[48] = 16'h8000;
            window_rom[49] = 16'h7374;
            window_rom[50] = 16'h6707;
            window_rom[51] = 16'h5AD8;
            window_rom[52] = 16'h4F04;
            window_rom[53] = 16'h43A9;
            window_rom[54] = 16'h38E3;
            window_rom[55] = 16'h2ECC;
            window_rom[56] = 16'h257D;
            window_rom[57] = 16'h1D0E;
            window_rom[58] = 16'h1592;
            window_rom[59] = 16'h0F1D;
            window_rom[60] = 16'h09BE;
            window_rom[61] = 16'h0583;
            window_rom[62] = 16'h0276;
            window_rom[63] = 16'h009E;
        end else begin
            window_rom[0] = 16'h0000;
            window_rom[1] = 16'h000A;
            window_rom[2] = 16'h0027;
            window_rom[3] = 16'h0059;
            window_rom[4] = 16'h009E;
            window_rom[5] = 16'h00F6;
            window_rom[6] = 16'h0163;
            window_rom[7] = 16'h01E2;
            window_rom[8] = 16'h0276;
            window_rom[9] = 16'h031C;
            window_rom[10] = 16'h03D6;
            window_rom[11] = 16'h04A3;
            window_rom[12] = 16'h0583;
            window_rom[13] = 16'h0676;
            window_rom[14] = 16'h077B;
            window_rom[15] = 16'h0894;
            window_rom[16] = 16'h09BE;
            window_rom[17] = 16'h0AFB;
            window_rom[18] = 16'h0C4A;
            window_rom[19] = 16'h0DAB;
            window_rom[20] = 16'h0F1D;
            window_rom[21] = 16'h10A1;
            window_rom[22] = 16'h1236;
            window_rom[23] = 16'h13DC;
            window_rom[24] = 16'h1592;
            window_rom[25] = 16'h1759;
            window_rom[26] = 16'h1930;
            window_rom[27] = 16'h1B17;
            window_rom[28] = 16'h1D0E;
            window_rom[29] = 16'h1F14;
            window_rom[30] = 16'h2128;
            window_rom[31] = 16'h234C;
            window_rom[32] = 16'h257D;
            window_rom[33] = 16'h27BD;
            window_rom[34] = 16'h2A0A;
            window_rom[35] = 16'h2C65;
            window_rom[36] = 16'h2ECC;
            window_rom[37] = 16'h3140;
            window_rom[38] = 16'h33C0;
            window_rom[39] = 16'h364C;
            window_rom[40] = 16'h38E3;
            window_rom[41] = 16'h3B85;
            window_rom[42] = 16'h3E32;
            window_rom[43] = 16'h40E8;
            window_rom[44] = 16'h43A9;
            window_rom[45] = 16'h4673;
            window_rom[46] = 16'h4946;
            window_rom[47] = 16'h4C21;
            window_rom[48] = 16'h4F04;
            window_rom[49] = 16'h51EF;
            window_rom[50] = 16'h54E0;
            window_rom[51] = 16'h57D9;
            window_rom[52] = 16'h5AD8;
            window_rom[53] = 16'h5DDC;
            window_rom[54] = 16'h60E6;
            window_rom[55] = 16'h63F4;
            window_rom[56] = 16'h6707;
            window_rom[57] = 16'h6A1E;
            window_rom[58] = 16'h6D38;
            window_rom[59] = 16'h7054;
            window_rom[60] = 16'h7374;
            window_rom[61] = 16'h7695;
            window_rom[62] = 16'h79B8;
            window_rom[63] = 16'h7CDB;
            window_rom[64] = 16'h7FFF;
            window_rom[65] = 16'h8324;
            window_rom[66] = 16'h8647;
            window_rom[67] = 16'h896A;
            window_rom[68] = 16'h8C8B;
            window_rom[69] = 16'h8FAB;
            window_rom[70] = 16'h92C7;
            window_rom[71] = 16'h95E1;
            window_rom[72] = 16'h98F8;
            window_rom[73] = 16'h9C0B;
            window_rom[74] = 16'h9F19;
            window_rom[75] = 16'hA223;
            window_rom[76] = 16'hA527;
            window_rom[77] = 16'hA826;
            window_rom[78] = 16'hAB1F;
            window_rom[79] = 16'hAE10;
            window_rom[80] = 16'hB0FB;
            window_rom[81] = 16'hB3DE;
            window_rom[82] = 16'hB6B9;
            window_rom[83] = 16'hB98C;
            window_rom[84] = 16'hBC56;
            window_rom[85] = 16'hBF17;
            window_rom[86] = 16'hC1CD;
            window_rom[87] = 16'hC47A;
            window_rom[88] = 16'hC71C;
            window_rom[89] = 16'hC9B3;
            window_rom[90] = 16'hCC3F;
            window_rom[91] = 16'hCEBF;
            window_rom[92] = 16'hD133;
            window_rom[93] = 16'hD39A;
            window_rom[94] = 16'hD5F5;
            window_rom[95] = 16'hD842;
            window_rom[96] = 16'hDA82;
            window_rom[97] = 16'hDCB3;
            window_rom[98] = 16'hDED7;
            window_rom[99] = 16'hE0EB;
            window_rom[100] = 16'hE2F1;
            window_rom[101] = 16'hE4E8;
            window_rom[102] = 16'hE6CF;
            window_rom[103] = 16'hE8A6;
            window_rom[104] = 16'hEA6D;
            window_rom[105] = 16'hEC23;
            window_rom[106] = 16'hEDC9;
            window_rom[107] = 16'hEF5E;
            window_rom[108] = 16'hF0E2;
            window_rom[109] = 16'hF254;
            window_rom[110] = 16'hF3B5;
            window_rom[111] = 16'hF504;
            window_rom[112] = 16'hF641;
            window_rom[113] = 16'hF76B;
            window_rom[114] = 16'hF884;
            window_rom[115] = 16'hF989;
            window_rom[116] = 16'hFA7C;
            window_rom[117] = 16'hFB5C;
            window_rom[118] = 16'hFC29;
            window_rom[119] = 16'hFCE3;
            window_rom[120] = 16'hFD89;
            window_rom[121] = 16'hFE1D;
            window_rom[122] = 16'hFE9C;
            window_rom[123] = 16'hFF09;
            window_rom[124] = 16'hFF61;
            window_rom[125] = 16'hFFA6;
            window_rom[126] = 16'hFFD8;
            window_rom[127] = 16'hFFF5;
            window_rom[128] = 16'hFFFF;
            window_rom[129] = 16'hFFF5;
            window_rom[130] = 16'hFFD8;
            window_rom[131] = 16'hFFA6;
            window_rom[132] = 16'hFF61;
            window_rom[133] = 16'hFF09;
            window_rom[134] = 16'hFE9C;
            window_rom[135] = 16'hFE1D;
            window_rom[136] = 16'hFD89;
            window_rom[137] = 16'hFCE3;
            window_rom[138] = 16'hFC29;
            window_rom[139] = 16'hFB5C;
            window_rom[140] = 16'hFA7C;
            window_rom[141] = 16'hF989;
            window_rom[142] = 16'hF884;
            window_rom[143] = 16'hF76B;
            window_rom[144] = 16'hF641;
            window_rom[145] = 16'hF504;
            window_rom[146] = 16'hF3B5;
            window_rom[147] = 16'hF254;
            window_rom[148] = 16'hF0E2;
            window_rom[149] = 16'hEF5E;
            window_rom[150] = 16'hEDC9;
            window_rom[151] = 16'hEC23;
            window_rom[152] = 16'hEA6D;
            window_rom[153] = 16'hE8A6;
            window_rom[154] = 16'hE6CF;
            window_rom[155] = 16'hE4E8;
            window_rom[156] = 16'hE2F1;
            window_rom[157] = 16'hE0EB;
            window_rom[158] = 16'hDED7;
            window_rom[159] = 16'hDCB3;
            window_rom[160] = 16'hDA82;
            window_rom[161] = 16'hD842;
            window_rom[162] = 16'hD5F5;
            window_rom[163] = 16'hD39A;
            window_rom[164] = 16'hD133;
            window_rom[165] = 16'hCEBF;
            window_rom[166] = 16'hCC3F;
            window_rom[167] = 16'hC9B3;
            window_rom[168] = 16'hC71C;
            window_rom[169] = 16'hC47A;
            window_rom[170] = 16'hC1CD;
            window_rom[171] = 16'hBF17;
            window_rom[172] = 16'hBC56;
            window_rom[173] = 16'hB98C;
            window_rom[174] = 16'hB6B9;
            window_rom[175] = 16'hB3DE;
            window_rom[176] = 16'hB0FB;
            window_rom[177] = 16'hAE10;
            window_rom[178] = 16'hAB1F;
            window_rom[179] = 16'hA826;
            window_rom[180] = 16'hA527;
            window_rom[181] = 16'hA223;
            window_rom[182] = 16'h9F19;
            window_rom[183] = 16'h9C0B;
            window_rom[184] = 16'h98F8;
            window_rom[185] = 16'h95E1;
            window_rom[186] = 16'h92C7;
            window_rom[187] = 16'h8FAB;
            window_rom[188] = 16'h8C8B;
            window_rom[189] = 16'h896A;
            window_rom[190] = 16'h8647;
            window_rom[191] = 16'h8324;
            window_rom[192] = 16'h8000;
            window_rom[193] = 16'h7CDB;
            window_rom[194] = 16'h79B8;
            window_rom[195] = 16'h7695;
            window_rom[196] = 16'h7374;
            window_rom[197] = 16'h7054;
            window_rom[198] = 16'h6D38;
            window_rom[199] = 16'h6A1E;
            window_rom[200] = 16'h6707;
            window_rom[201] = 16'h63F4;
            window_rom[202] = 16'h60E6;
            window_rom[203] = 16'h5DDC;
            window_rom[204] = 16'h5AD8;
            window_rom[205] = 16'h57D9;
            window_rom[206] = 16'h54E0;
            window_rom[207] = 16'h51EF;
            window_rom[208] = 16'h4F04;
            window_rom[209] = 16'h4C21;
            window_rom[210] = 16'h4946;
            window_rom[211] = 16'h4673;
            window_rom[212] = 16'h43A9;
            window_rom[213] = 16'h40E8;
            window_rom[214] = 16'h3E32;
            window_rom[215] = 16'h3B85;
            window_rom[216] = 16'h38E3;
            window_rom[217] = 16'h364C;
            window_rom[218] = 16'h33C0;
            window_rom[219] = 16'h3140;
            window_rom[220] = 16'h2ECC;
            window_rom[221] = 16'h2C65;
            window_rom[222] = 16'h2A0A;
            window_rom[223] = 16'h27BD;
            window_rom[224] = 16'h257D;
            window_rom[225] = 16'h234C;
            window_rom[226] = 16'h2128;
            window_rom[227] = 16'h1F14;
            window_rom[228] = 16'h1D0E;
            window_rom[229] = 16'h1B17;
            window_rom[230] = 16'h1930;
            window_rom[231] = 16'h1759;
            window_rom[232] = 16'h1592;
            window_rom[233] = 16'h13DC;
            window_rom[234] = 16'h1236;
            window_rom[235] = 16'h10A1;
            window_rom[236] = 16'h0F1D;
            window_rom[237] = 16'h0DAB;
            window_rom[238] = 16'h0C4A;
            window_rom[239] = 16'h0AFB;
            window_rom[240] = 16'h09BE;
            window_rom[241] = 16'h0894;
            window_rom[242] = 16'h077B;
            window_rom[243] = 16'h0676;
            window_rom[244] = 16'h0583;
            window_rom[245] = 16'h04A3;
            window_rom[246] = 16'h03D6;
            window_rom[247] = 16'h031C;
            window_rom[248] = 16'h0276;
            window_rom[249] = 16'h01E2;
            window_rom[250] = 16'h0163;
            window_rom[251] = 16'h00F6;
            window_rom[252] = 16'h009E;
            window_rom[253] = 16'h0059;
            window_rom[254] = 16'h0027;
            window_rom[255] = 16'h000A;
        end
    end

    wire [15:0] w_coeff = window_rom[sample_idx];

    // Signed multiplier: signed 16-bit sample * unsigned 16-bit window
    // Extended product: 32 bits
    wire signed [32:0] mult_product = $signed(sample_in) * $signed({1'b0, w_coeff});

    always @(posedge clk) begin
        if (!reset_n) begin
            out_valid  <= 1'b0;
            out_idx    <= {ADDR_WIDTH{1'b0}};
            sample_out <= {DATA_WIDTH{1'b0}};
        end else begin
            out_valid  <= in_valid;
            out_idx    <= sample_idx;
            if (in_valid) begin
                // Scale by 1/65536 (shift right by 16 bits)
                sample_out <= mult_product[31:16];
            end
        end
    end

endmodule
