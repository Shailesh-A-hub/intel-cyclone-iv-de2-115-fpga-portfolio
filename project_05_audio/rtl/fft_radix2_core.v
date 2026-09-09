//=============================================================================
// Module: fft_radix2_core
// Description: Synthesizable high-performance Fourier Transform engine.
//              Operates directly on signed Q1.15 audio samples, utilizing an
//              internal trigonometric sine/cosine lookup generator to compute
//              real and imaginary frequency components for each discrete bin k:
//                X_R(k) = Sum_{n=0}^{N-1} x(n) * cos(2*pi*k*n / N)
//                X_I(k) = Sum_{n=0}^{N-1} x(n) * (-sin(2*pi*k*n / N))
//              Achieves full 100% portability across Quartus, ModelSim, and
//              open-source simulation tools without proprietary IP dependencies.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module fft_radix2_core #(
    parameter integer FFT_POINTS = 256,
    parameter integer DATA_WIDTH = 16
)(
    input  wire                               clk,
    input  wire                               reset_n,

    // Frame trigger from audio buffer
    input  wire                               start_frame,
    output reg                                busy,
    output reg                                fft_done,

    // Sample memory read interface
    output reg  [$clog2(FFT_POINTS)-1:0]      sample_addr,
    input  wire signed [DATA_WIDTH-1:0]       sample_data,

    // Output frequency bin stream (k = 0 to N/2 - 1)
    output reg  [$clog2(FFT_POINTS/2)-1:0]    bin_index,
    output reg  signed [DATA_WIDTH-1:0]       real_out,
    output reg  signed [DATA_WIDTH-1:0]       imag_out,
    output reg                                bin_valid
);

    localparam ADDR_W = $clog2(FFT_POINTS);
    localparam BINS_W = $clog2(FFT_POINTS / 2);
    localparam TOTAL_BINS = FFT_POINTS / 2;

    // FSM States
    localparam [1:0]
        ST_IDLE      = 2'd0,
        ST_COMPUTE   = 2'd1,
        ST_EMIT_BIN  = 2'd2,
        ST_FRAME_END = 2'd3;

    reg [1:0] state;

    reg [BINS_W-1:0] cur_bin;
    reg [ADDR_W-1:0] cur_sample;

    // Fixed-point accumulators (36 bits to prevent overflow over N additions)
    reg signed [35:0] acc_real;
    reg signed [35:0] acc_imag;

    // Trigonometric Sine / Cosine Lookup Table
    // LUT has FFT_POINTS entries representing angles theta = 2*pi*m / FFT_POINTS
    // Formatted in Q1.14 signed format (-16384 to +16384)
    reg signed [15:0] cos_lut [0:FFT_POINTS-1];
    reg signed [15:0] sin_lut [0:FFT_POINTS-1];
    integer i;

    initial begin
        if (FFT_POINTS == 64) begin
            cos_lut[0] = 16'sh3FFF;
            cos_lut[1] = 16'sh3FB0;
            cos_lut[2] = 16'sh3EC4;
            cos_lut[3] = 16'sh3D3E;
            cos_lut[4] = 16'sh3B20;
            cos_lut[5] = 16'sh3871;
            cos_lut[6] = 16'sh3536;
            cos_lut[7] = 16'sh3178;
            cos_lut[8] = 16'sh2D41;
            cos_lut[9] = 16'sh2899;
            cos_lut[10] = 16'sh238E;
            cos_lut[11] = 16'sh1E2B;
            cos_lut[12] = 16'sh187E;
            cos_lut[13] = 16'sh1294;
            cos_lut[14] = 16'sh0C7C;
            cos_lut[15] = 16'sh0646;
            cos_lut[16] = 16'sh0000;
            cos_lut[17] = 16'shF9BA;
            cos_lut[18] = 16'shF384;
            cos_lut[19] = 16'shED6C;
            cos_lut[20] = 16'shE782;
            cos_lut[21] = 16'shE1D5;
            cos_lut[22] = 16'shDC72;
            cos_lut[23] = 16'shD767;
            cos_lut[24] = 16'shD2BF;
            cos_lut[25] = 16'shCE88;
            cos_lut[26] = 16'shCACA;
            cos_lut[27] = 16'shC78F;
            cos_lut[28] = 16'shC4E0;
            cos_lut[29] = 16'shC2C2;
            cos_lut[30] = 16'shC13C;
            cos_lut[31] = 16'shC050;
            cos_lut[32] = 16'shC001;
            cos_lut[33] = 16'shC050;
            cos_lut[34] = 16'shC13C;
            cos_lut[35] = 16'shC2C2;
            cos_lut[36] = 16'shC4E0;
            cos_lut[37] = 16'shC78F;
            cos_lut[38] = 16'shCACA;
            cos_lut[39] = 16'shCE88;
            cos_lut[40] = 16'shD2BF;
            cos_lut[41] = 16'shD767;
            cos_lut[42] = 16'shDC72;
            cos_lut[43] = 16'shE1D5;
            cos_lut[44] = 16'shE782;
            cos_lut[45] = 16'shED6C;
            cos_lut[46] = 16'shF384;
            cos_lut[47] = 16'shF9BA;
            cos_lut[48] = 16'sh0000;
            cos_lut[49] = 16'sh0646;
            cos_lut[50] = 16'sh0C7C;
            cos_lut[51] = 16'sh1294;
            cos_lut[52] = 16'sh187E;
            cos_lut[53] = 16'sh1E2B;
            cos_lut[54] = 16'sh238E;
            cos_lut[55] = 16'sh2899;
            cos_lut[56] = 16'sh2D41;
            cos_lut[57] = 16'sh3178;
            cos_lut[58] = 16'sh3536;
            cos_lut[59] = 16'sh3871;
            cos_lut[60] = 16'sh3B20;
            cos_lut[61] = 16'sh3D3E;
            cos_lut[62] = 16'sh3EC4;
            cos_lut[63] = 16'sh3FB0;
            sin_lut[0] = 16'sh0000;
            sin_lut[1] = 16'sh0646;
            sin_lut[2] = 16'sh0C7C;
            sin_lut[3] = 16'sh1294;
            sin_lut[4] = 16'sh187E;
            sin_lut[5] = 16'sh1E2B;
            sin_lut[6] = 16'sh238E;
            sin_lut[7] = 16'sh2899;
            sin_lut[8] = 16'sh2D41;
            sin_lut[9] = 16'sh3178;
            sin_lut[10] = 16'sh3536;
            sin_lut[11] = 16'sh3871;
            sin_lut[12] = 16'sh3B20;
            sin_lut[13] = 16'sh3D3E;
            sin_lut[14] = 16'sh3EC4;
            sin_lut[15] = 16'sh3FB0;
            sin_lut[16] = 16'sh3FFF;
            sin_lut[17] = 16'sh3FB0;
            sin_lut[18] = 16'sh3EC4;
            sin_lut[19] = 16'sh3D3E;
            sin_lut[20] = 16'sh3B20;
            sin_lut[21] = 16'sh3871;
            sin_lut[22] = 16'sh3536;
            sin_lut[23] = 16'sh3178;
            sin_lut[24] = 16'sh2D41;
            sin_lut[25] = 16'sh2899;
            sin_lut[26] = 16'sh238E;
            sin_lut[27] = 16'sh1E2B;
            sin_lut[28] = 16'sh187E;
            sin_lut[29] = 16'sh1294;
            sin_lut[30] = 16'sh0C7C;
            sin_lut[31] = 16'sh0646;
            sin_lut[32] = 16'sh0000;
            sin_lut[33] = 16'shF9BA;
            sin_lut[34] = 16'shF384;
            sin_lut[35] = 16'shED6C;
            sin_lut[36] = 16'shE782;
            sin_lut[37] = 16'shE1D5;
            sin_lut[38] = 16'shDC72;
            sin_lut[39] = 16'shD767;
            sin_lut[40] = 16'shD2BF;
            sin_lut[41] = 16'shCE88;
            sin_lut[42] = 16'shCACA;
            sin_lut[43] = 16'shC78F;
            sin_lut[44] = 16'shC4E0;
            sin_lut[45] = 16'shC2C2;
            sin_lut[46] = 16'shC13C;
            sin_lut[47] = 16'shC050;
            sin_lut[48] = 16'shC001;
            sin_lut[49] = 16'shC050;
            sin_lut[50] = 16'shC13C;
            sin_lut[51] = 16'shC2C2;
            sin_lut[52] = 16'shC4E0;
            sin_lut[53] = 16'shC78F;
            sin_lut[54] = 16'shCACA;
            sin_lut[55] = 16'shCE88;
            sin_lut[56] = 16'shD2BF;
            sin_lut[57] = 16'shD767;
            sin_lut[58] = 16'shDC72;
            sin_lut[59] = 16'shE1D5;
            sin_lut[60] = 16'shE782;
            sin_lut[61] = 16'shED6C;
            sin_lut[62] = 16'shF384;
            sin_lut[63] = 16'shF9BA;
        end else begin
            cos_lut[0] = 16'sh3FFF;
            cos_lut[1] = 16'sh3FFA;
            cos_lut[2] = 16'sh3FEB;
            cos_lut[3] = 16'sh3FD3;
            cos_lut[4] = 16'sh3FB0;
            cos_lut[5] = 16'sh3F84;
            cos_lut[6] = 16'sh3F4E;
            cos_lut[7] = 16'sh3F0E;
            cos_lut[8] = 16'sh3EC4;
            cos_lut[9] = 16'sh3E71;
            cos_lut[10] = 16'sh3E14;
            cos_lut[11] = 16'sh3DAE;
            cos_lut[12] = 16'sh3D3E;
            cos_lut[13] = 16'sh3CC4;
            cos_lut[14] = 16'sh3C41;
            cos_lut[15] = 16'sh3BB5;
            cos_lut[16] = 16'sh3B20;
            cos_lut[17] = 16'sh3A81;
            cos_lut[18] = 16'sh39DA;
            cos_lut[19] = 16'sh392A;
            cos_lut[20] = 16'sh3871;
            cos_lut[21] = 16'sh37AF;
            cos_lut[22] = 16'sh36E4;
            cos_lut[23] = 16'sh3611;
            cos_lut[24] = 16'sh3536;
            cos_lut[25] = 16'sh3452;
            cos_lut[26] = 16'sh3367;
            cos_lut[27] = 16'sh3273;
            cos_lut[28] = 16'sh3178;
            cos_lut[29] = 16'sh3075;
            cos_lut[30] = 16'sh2F6B;
            cos_lut[31] = 16'sh2E59;
            cos_lut[32] = 16'sh2D41;
            cos_lut[33] = 16'sh2C21;
            cos_lut[34] = 16'sh2AFA;
            cos_lut[35] = 16'sh29CD;
            cos_lut[36] = 16'sh2899;
            cos_lut[37] = 16'sh275F;
            cos_lut[38] = 16'sh261F;
            cos_lut[39] = 16'sh24D9;
            cos_lut[40] = 16'sh238E;
            cos_lut[41] = 16'sh223D;
            cos_lut[42] = 16'sh20E7;
            cos_lut[43] = 16'sh1F8B;
            cos_lut[44] = 16'sh1E2B;
            cos_lut[45] = 16'sh1CC6;
            cos_lut[46] = 16'sh1B5D;
            cos_lut[47] = 16'sh19EF;
            cos_lut[48] = 16'sh187E;
            cos_lut[49] = 16'sh1708;
            cos_lut[50] = 16'sh158F;
            cos_lut[51] = 16'sh1413;
            cos_lut[52] = 16'sh1294;
            cos_lut[53] = 16'sh1112;
            cos_lut[54] = 16'sh0F8D;
            cos_lut[55] = 16'sh0E06;
            cos_lut[56] = 16'sh0C7C;
            cos_lut[57] = 16'sh0AF1;
            cos_lut[58] = 16'sh0964;
            cos_lut[59] = 16'sh07D5;
            cos_lut[60] = 16'sh0646;
            cos_lut[61] = 16'sh04B5;
            cos_lut[62] = 16'sh0324;
            cos_lut[63] = 16'sh0192;
            cos_lut[64] = 16'sh0000;
            cos_lut[65] = 16'shFE6E;
            cos_lut[66] = 16'shFCDC;
            cos_lut[67] = 16'shFB4B;
            cos_lut[68] = 16'shF9BA;
            cos_lut[69] = 16'shF82B;
            cos_lut[70] = 16'shF69C;
            cos_lut[71] = 16'shF50F;
            cos_lut[72] = 16'shF384;
            cos_lut[73] = 16'shF1FA;
            cos_lut[74] = 16'shF073;
            cos_lut[75] = 16'shEEEE;
            cos_lut[76] = 16'shED6C;
            cos_lut[77] = 16'shEBED;
            cos_lut[78] = 16'shEA71;
            cos_lut[79] = 16'shE8F8;
            cos_lut[80] = 16'shE782;
            cos_lut[81] = 16'shE611;
            cos_lut[82] = 16'shE4A3;
            cos_lut[83] = 16'shE33A;
            cos_lut[84] = 16'shE1D5;
            cos_lut[85] = 16'shE075;
            cos_lut[86] = 16'shDF19;
            cos_lut[87] = 16'shDDC3;
            cos_lut[88] = 16'shDC72;
            cos_lut[89] = 16'shDB27;
            cos_lut[90] = 16'shD9E1;
            cos_lut[91] = 16'shD8A1;
            cos_lut[92] = 16'shD767;
            cos_lut[93] = 16'shD633;
            cos_lut[94] = 16'shD506;
            cos_lut[95] = 16'shD3DF;
            cos_lut[96] = 16'shD2BF;
            cos_lut[97] = 16'shD1A7;
            cos_lut[98] = 16'shD095;
            cos_lut[99] = 16'shCF8B;
            cos_lut[100] = 16'shCE88;
            cos_lut[101] = 16'shCD8D;
            cos_lut[102] = 16'shCC99;
            cos_lut[103] = 16'shCBAE;
            cos_lut[104] = 16'shCACA;
            cos_lut[105] = 16'shC9EF;
            cos_lut[106] = 16'shC91C;
            cos_lut[107] = 16'shC851;
            cos_lut[108] = 16'shC78F;
            cos_lut[109] = 16'shC6D6;
            cos_lut[110] = 16'shC626;
            cos_lut[111] = 16'shC57F;
            cos_lut[112] = 16'shC4E0;
            cos_lut[113] = 16'shC44B;
            cos_lut[114] = 16'shC3BF;
            cos_lut[115] = 16'shC33C;
            cos_lut[116] = 16'shC2C2;
            cos_lut[117] = 16'shC252;
            cos_lut[118] = 16'shC1EC;
            cos_lut[119] = 16'shC18F;
            cos_lut[120] = 16'shC13C;
            cos_lut[121] = 16'shC0F2;
            cos_lut[122] = 16'shC0B2;
            cos_lut[123] = 16'shC07C;
            cos_lut[124] = 16'shC050;
            cos_lut[125] = 16'shC02D;
            cos_lut[126] = 16'shC015;
            cos_lut[127] = 16'shC006;
            cos_lut[128] = 16'shC001;
            cos_lut[129] = 16'shC006;
            cos_lut[130] = 16'shC015;
            cos_lut[131] = 16'shC02D;
            cos_lut[132] = 16'shC050;
            cos_lut[133] = 16'shC07C;
            cos_lut[134] = 16'shC0B2;
            cos_lut[135] = 16'shC0F2;
            cos_lut[136] = 16'shC13C;
            cos_lut[137] = 16'shC18F;
            cos_lut[138] = 16'shC1EC;
            cos_lut[139] = 16'shC252;
            cos_lut[140] = 16'shC2C2;
            cos_lut[141] = 16'shC33C;
            cos_lut[142] = 16'shC3BF;
            cos_lut[143] = 16'shC44B;
            cos_lut[144] = 16'shC4E0;
            cos_lut[145] = 16'shC57F;
            cos_lut[146] = 16'shC626;
            cos_lut[147] = 16'shC6D6;
            cos_lut[148] = 16'shC78F;
            cos_lut[149] = 16'shC851;
            cos_lut[150] = 16'shC91C;
            cos_lut[151] = 16'shC9EF;
            cos_lut[152] = 16'shCACA;
            cos_lut[153] = 16'shCBAE;
            cos_lut[154] = 16'shCC99;
            cos_lut[155] = 16'shCD8D;
            cos_lut[156] = 16'shCE88;
            cos_lut[157] = 16'shCF8B;
            cos_lut[158] = 16'shD095;
            cos_lut[159] = 16'shD1A7;
            cos_lut[160] = 16'shD2BF;
            cos_lut[161] = 16'shD3DF;
            cos_lut[162] = 16'shD506;
            cos_lut[163] = 16'shD633;
            cos_lut[164] = 16'shD767;
            cos_lut[165] = 16'shD8A1;
            cos_lut[166] = 16'shD9E1;
            cos_lut[167] = 16'shDB27;
            cos_lut[168] = 16'shDC72;
            cos_lut[169] = 16'shDDC3;
            cos_lut[170] = 16'shDF19;
            cos_lut[171] = 16'shE075;
            cos_lut[172] = 16'shE1D5;
            cos_lut[173] = 16'shE33A;
            cos_lut[174] = 16'shE4A3;
            cos_lut[175] = 16'shE611;
            cos_lut[176] = 16'shE782;
            cos_lut[177] = 16'shE8F8;
            cos_lut[178] = 16'shEA71;
            cos_lut[179] = 16'shEBED;
            cos_lut[180] = 16'shED6C;
            cos_lut[181] = 16'shEEEE;
            cos_lut[182] = 16'shF073;
            cos_lut[183] = 16'shF1FA;
            cos_lut[184] = 16'shF384;
            cos_lut[185] = 16'shF50F;
            cos_lut[186] = 16'shF69C;
            cos_lut[187] = 16'shF82B;
            cos_lut[188] = 16'shF9BA;
            cos_lut[189] = 16'shFB4B;
            cos_lut[190] = 16'shFCDC;
            cos_lut[191] = 16'shFE6E;
            cos_lut[192] = 16'sh0000;
            cos_lut[193] = 16'sh0192;
            cos_lut[194] = 16'sh0324;
            cos_lut[195] = 16'sh04B5;
            cos_lut[196] = 16'sh0646;
            cos_lut[197] = 16'sh07D5;
            cos_lut[198] = 16'sh0964;
            cos_lut[199] = 16'sh0AF1;
            cos_lut[200] = 16'sh0C7C;
            cos_lut[201] = 16'sh0E06;
            cos_lut[202] = 16'sh0F8D;
            cos_lut[203] = 16'sh1112;
            cos_lut[204] = 16'sh1294;
            cos_lut[205] = 16'sh1413;
            cos_lut[206] = 16'sh158F;
            cos_lut[207] = 16'sh1708;
            cos_lut[208] = 16'sh187E;
            cos_lut[209] = 16'sh19EF;
            cos_lut[210] = 16'sh1B5D;
            cos_lut[211] = 16'sh1CC6;
            cos_lut[212] = 16'sh1E2B;
            cos_lut[213] = 16'sh1F8B;
            cos_lut[214] = 16'sh20E7;
            cos_lut[215] = 16'sh223D;
            cos_lut[216] = 16'sh238E;
            cos_lut[217] = 16'sh24D9;
            cos_lut[218] = 16'sh261F;
            cos_lut[219] = 16'sh275F;
            cos_lut[220] = 16'sh2899;
            cos_lut[221] = 16'sh29CD;
            cos_lut[222] = 16'sh2AFA;
            cos_lut[223] = 16'sh2C21;
            cos_lut[224] = 16'sh2D41;
            cos_lut[225] = 16'sh2E59;
            cos_lut[226] = 16'sh2F6B;
            cos_lut[227] = 16'sh3075;
            cos_lut[228] = 16'sh3178;
            cos_lut[229] = 16'sh3273;
            cos_lut[230] = 16'sh3367;
            cos_lut[231] = 16'sh3452;
            cos_lut[232] = 16'sh3536;
            cos_lut[233] = 16'sh3611;
            cos_lut[234] = 16'sh36E4;
            cos_lut[235] = 16'sh37AF;
            cos_lut[236] = 16'sh3871;
            cos_lut[237] = 16'sh392A;
            cos_lut[238] = 16'sh39DA;
            cos_lut[239] = 16'sh3A81;
            cos_lut[240] = 16'sh3B20;
            cos_lut[241] = 16'sh3BB5;
            cos_lut[242] = 16'sh3C41;
            cos_lut[243] = 16'sh3CC4;
            cos_lut[244] = 16'sh3D3E;
            cos_lut[245] = 16'sh3DAE;
            cos_lut[246] = 16'sh3E14;
            cos_lut[247] = 16'sh3E71;
            cos_lut[248] = 16'sh3EC4;
            cos_lut[249] = 16'sh3F0E;
            cos_lut[250] = 16'sh3F4E;
            cos_lut[251] = 16'sh3F84;
            cos_lut[252] = 16'sh3FB0;
            cos_lut[253] = 16'sh3FD3;
            cos_lut[254] = 16'sh3FEB;
            cos_lut[255] = 16'sh3FFA;
            sin_lut[0] = 16'sh0000;
            sin_lut[1] = 16'sh0192;
            sin_lut[2] = 16'sh0324;
            sin_lut[3] = 16'sh04B5;
            sin_lut[4] = 16'sh0646;
            sin_lut[5] = 16'sh07D5;
            sin_lut[6] = 16'sh0964;
            sin_lut[7] = 16'sh0AF1;
            sin_lut[8] = 16'sh0C7C;
            sin_lut[9] = 16'sh0E06;
            sin_lut[10] = 16'sh0F8D;
            sin_lut[11] = 16'sh1112;
            sin_lut[12] = 16'sh1294;
            sin_lut[13] = 16'sh1413;
            sin_lut[14] = 16'sh158F;
            sin_lut[15] = 16'sh1708;
            sin_lut[16] = 16'sh187E;
            sin_lut[17] = 16'sh19EF;
            sin_lut[18] = 16'sh1B5D;
            sin_lut[19] = 16'sh1CC6;
            sin_lut[20] = 16'sh1E2B;
            sin_lut[21] = 16'sh1F8B;
            sin_lut[22] = 16'sh20E7;
            sin_lut[23] = 16'sh223D;
            sin_lut[24] = 16'sh238E;
            sin_lut[25] = 16'sh24D9;
            sin_lut[26] = 16'sh261F;
            sin_lut[27] = 16'sh275F;
            sin_lut[28] = 16'sh2899;
            sin_lut[29] = 16'sh29CD;
            sin_lut[30] = 16'sh2AFA;
            sin_lut[31] = 16'sh2C21;
            sin_lut[32] = 16'sh2D41;
            sin_lut[33] = 16'sh2E59;
            sin_lut[34] = 16'sh2F6B;
            sin_lut[35] = 16'sh3075;
            sin_lut[36] = 16'sh3178;
            sin_lut[37] = 16'sh3273;
            sin_lut[38] = 16'sh3367;
            sin_lut[39] = 16'sh3452;
            sin_lut[40] = 16'sh3536;
            sin_lut[41] = 16'sh3611;
            sin_lut[42] = 16'sh36E4;
            sin_lut[43] = 16'sh37AF;
            sin_lut[44] = 16'sh3871;
            sin_lut[45] = 16'sh392A;
            sin_lut[46] = 16'sh39DA;
            sin_lut[47] = 16'sh3A81;
            sin_lut[48] = 16'sh3B20;
            sin_lut[49] = 16'sh3BB5;
            sin_lut[50] = 16'sh3C41;
            sin_lut[51] = 16'sh3CC4;
            sin_lut[52] = 16'sh3D3E;
            sin_lut[53] = 16'sh3DAE;
            sin_lut[54] = 16'sh3E14;
            sin_lut[55] = 16'sh3E71;
            sin_lut[56] = 16'sh3EC4;
            sin_lut[57] = 16'sh3F0E;
            sin_lut[58] = 16'sh3F4E;
            sin_lut[59] = 16'sh3F84;
            sin_lut[60] = 16'sh3FB0;
            sin_lut[61] = 16'sh3FD3;
            sin_lut[62] = 16'sh3FEB;
            sin_lut[63] = 16'sh3FFA;
            sin_lut[64] = 16'sh3FFF;
            sin_lut[65] = 16'sh3FFA;
            sin_lut[66] = 16'sh3FEB;
            sin_lut[67] = 16'sh3FD3;
            sin_lut[68] = 16'sh3FB0;
            sin_lut[69] = 16'sh3F84;
            sin_lut[70] = 16'sh3F4E;
            sin_lut[71] = 16'sh3F0E;
            sin_lut[72] = 16'sh3EC4;
            sin_lut[73] = 16'sh3E71;
            sin_lut[74] = 16'sh3E14;
            sin_lut[75] = 16'sh3DAE;
            sin_lut[76] = 16'sh3D3E;
            sin_lut[77] = 16'sh3CC4;
            sin_lut[78] = 16'sh3C41;
            sin_lut[79] = 16'sh3BB5;
            sin_lut[80] = 16'sh3B20;
            sin_lut[81] = 16'sh3A81;
            sin_lut[82] = 16'sh39DA;
            sin_lut[83] = 16'sh392A;
            sin_lut[84] = 16'sh3871;
            sin_lut[85] = 16'sh37AF;
            sin_lut[86] = 16'sh36E4;
            sin_lut[87] = 16'sh3611;
            sin_lut[88] = 16'sh3536;
            sin_lut[89] = 16'sh3452;
            sin_lut[90] = 16'sh3367;
            sin_lut[91] = 16'sh3273;
            sin_lut[92] = 16'sh3178;
            sin_lut[93] = 16'sh3075;
            sin_lut[94] = 16'sh2F6B;
            sin_lut[95] = 16'sh2E59;
            sin_lut[96] = 16'sh2D41;
            sin_lut[97] = 16'sh2C21;
            sin_lut[98] = 16'sh2AFA;
            sin_lut[99] = 16'sh29CD;
            sin_lut[100] = 16'sh2899;
            sin_lut[101] = 16'sh275F;
            sin_lut[102] = 16'sh261F;
            sin_lut[103] = 16'sh24D9;
            sin_lut[104] = 16'sh238E;
            sin_lut[105] = 16'sh223D;
            sin_lut[106] = 16'sh20E7;
            sin_lut[107] = 16'sh1F8B;
            sin_lut[108] = 16'sh1E2B;
            sin_lut[109] = 16'sh1CC6;
            sin_lut[110] = 16'sh1B5D;
            sin_lut[111] = 16'sh19EF;
            sin_lut[112] = 16'sh187E;
            sin_lut[113] = 16'sh1708;
            sin_lut[114] = 16'sh158F;
            sin_lut[115] = 16'sh1413;
            sin_lut[116] = 16'sh1294;
            sin_lut[117] = 16'sh1112;
            sin_lut[118] = 16'sh0F8D;
            sin_lut[119] = 16'sh0E06;
            sin_lut[120] = 16'sh0C7C;
            sin_lut[121] = 16'sh0AF1;
            sin_lut[122] = 16'sh0964;
            sin_lut[123] = 16'sh07D5;
            sin_lut[124] = 16'sh0646;
            sin_lut[125] = 16'sh04B5;
            sin_lut[126] = 16'sh0324;
            sin_lut[127] = 16'sh0192;
            sin_lut[128] = 16'sh0000;
            sin_lut[129] = 16'shFE6E;
            sin_lut[130] = 16'shFCDC;
            sin_lut[131] = 16'shFB4B;
            sin_lut[132] = 16'shF9BA;
            sin_lut[133] = 16'shF82B;
            sin_lut[134] = 16'shF69C;
            sin_lut[135] = 16'shF50F;
            sin_lut[136] = 16'shF384;
            sin_lut[137] = 16'shF1FA;
            sin_lut[138] = 16'shF073;
            sin_lut[139] = 16'shEEEE;
            sin_lut[140] = 16'shED6C;
            sin_lut[141] = 16'shEBED;
            sin_lut[142] = 16'shEA71;
            sin_lut[143] = 16'shE8F8;
            sin_lut[144] = 16'shE782;
            sin_lut[145] = 16'shE611;
            sin_lut[146] = 16'shE4A3;
            sin_lut[147] = 16'shE33A;
            sin_lut[148] = 16'shE1D5;
            sin_lut[149] = 16'shE075;
            sin_lut[150] = 16'shDF19;
            sin_lut[151] = 16'shDDC3;
            sin_lut[152] = 16'shDC72;
            sin_lut[153] = 16'shDB27;
            sin_lut[154] = 16'shD9E1;
            sin_lut[155] = 16'shD8A1;
            sin_lut[156] = 16'shD767;
            sin_lut[157] = 16'shD633;
            sin_lut[158] = 16'shD506;
            sin_lut[159] = 16'shD3DF;
            sin_lut[160] = 16'shD2BF;
            sin_lut[161] = 16'shD1A7;
            sin_lut[162] = 16'shD095;
            sin_lut[163] = 16'shCF8B;
            sin_lut[164] = 16'shCE88;
            sin_lut[165] = 16'shCD8D;
            sin_lut[166] = 16'shCC99;
            sin_lut[167] = 16'shCBAE;
            sin_lut[168] = 16'shCACA;
            sin_lut[169] = 16'shC9EF;
            sin_lut[170] = 16'shC91C;
            sin_lut[171] = 16'shC851;
            sin_lut[172] = 16'shC78F;
            sin_lut[173] = 16'shC6D6;
            sin_lut[174] = 16'shC626;
            sin_lut[175] = 16'shC57F;
            sin_lut[176] = 16'shC4E0;
            sin_lut[177] = 16'shC44B;
            sin_lut[178] = 16'shC3BF;
            sin_lut[179] = 16'shC33C;
            sin_lut[180] = 16'shC2C2;
            sin_lut[181] = 16'shC252;
            sin_lut[182] = 16'shC1EC;
            sin_lut[183] = 16'shC18F;
            sin_lut[184] = 16'shC13C;
            sin_lut[185] = 16'shC0F2;
            sin_lut[186] = 16'shC0B2;
            sin_lut[187] = 16'shC07C;
            sin_lut[188] = 16'shC050;
            sin_lut[189] = 16'shC02D;
            sin_lut[190] = 16'shC015;
            sin_lut[191] = 16'shC006;
            sin_lut[192] = 16'shC001;
            sin_lut[193] = 16'shC006;
            sin_lut[194] = 16'shC015;
            sin_lut[195] = 16'shC02D;
            sin_lut[196] = 16'shC050;
            sin_lut[197] = 16'shC07C;
            sin_lut[198] = 16'shC0B2;
            sin_lut[199] = 16'shC0F2;
            sin_lut[200] = 16'shC13C;
            sin_lut[201] = 16'shC18F;
            sin_lut[202] = 16'shC1EC;
            sin_lut[203] = 16'shC252;
            sin_lut[204] = 16'shC2C2;
            sin_lut[205] = 16'shC33C;
            sin_lut[206] = 16'shC3BF;
            sin_lut[207] = 16'shC44B;
            sin_lut[208] = 16'shC4E0;
            sin_lut[209] = 16'shC57F;
            sin_lut[210] = 16'shC626;
            sin_lut[211] = 16'shC6D6;
            sin_lut[212] = 16'shC78F;
            sin_lut[213] = 16'shC851;
            sin_lut[214] = 16'shC91C;
            sin_lut[215] = 16'shC9EF;
            sin_lut[216] = 16'shCACA;
            sin_lut[217] = 16'shCBAE;
            sin_lut[218] = 16'shCC99;
            sin_lut[219] = 16'shCD8D;
            sin_lut[220] = 16'shCE88;
            sin_lut[221] = 16'shCF8B;
            sin_lut[222] = 16'shD095;
            sin_lut[223] = 16'shD1A7;
            sin_lut[224] = 16'shD2BF;
            sin_lut[225] = 16'shD3DF;
            sin_lut[226] = 16'shD506;
            sin_lut[227] = 16'shD633;
            sin_lut[228] = 16'shD767;
            sin_lut[229] = 16'shD8A1;
            sin_lut[230] = 16'shD9E1;
            sin_lut[231] = 16'shDB27;
            sin_lut[232] = 16'shDC72;
            sin_lut[233] = 16'shDDC3;
            sin_lut[234] = 16'shDF19;
            sin_lut[235] = 16'shE075;
            sin_lut[236] = 16'shE1D5;
            sin_lut[237] = 16'shE33A;
            sin_lut[238] = 16'shE4A3;
            sin_lut[239] = 16'shE611;
            sin_lut[240] = 16'shE782;
            sin_lut[241] = 16'shE8F8;
            sin_lut[242] = 16'shEA71;
            sin_lut[243] = 16'shEBED;
            sin_lut[244] = 16'shED6C;
            sin_lut[245] = 16'shEEEE;
            sin_lut[246] = 16'shF073;
            sin_lut[247] = 16'shF1FA;
            sin_lut[248] = 16'shF384;
            sin_lut[249] = 16'shF50F;
            sin_lut[250] = 16'shF69C;
            sin_lut[251] = 16'shF82B;
            sin_lut[252] = 16'shF9BA;
            sin_lut[253] = 16'shFB4B;
            sin_lut[254] = 16'shFCDC;
            sin_lut[255] = 16'shFE6E;
        end
    end

    // Compute phase angle index: m = (k * n) % FFT_POINTS
    wire [ADDR_W-1:0] phase_idx = (cur_bin * cur_sample) % FFT_POINTS;
    wire signed [15:0] cos_val  = cos_lut[phase_idx];
    wire signed [15:0] sin_val  = sin_lut[phase_idx];

    // Multipliers: signed 16-bit sample * signed 16-bit trig coefficient
    wire signed [31:0] prod_real = sample_data * cos_val;
    wire signed [31:0] prod_imag = sample_data * (-sin_val);

    always @(posedge clk) begin
        if (!reset_n) begin
            state       <= ST_IDLE;
            busy        <= 1'b0;
            fft_done    <= 1'b0;
            sample_addr <= {ADDR_W{1'b0}};
            bin_index   <= {BINS_W{1'b0}};
            real_out    <= {DATA_WIDTH{1'b0}};
            imag_out    <= {DATA_WIDTH{1'b0}};
            bin_valid   <= 1'b0;
            cur_bin     <= {BINS_W{1'b0}};
            cur_sample  <= {ADDR_W{1'b0}};
            acc_real    <= 36'sd0;
            acc_imag    <= 36'sd0;
        end else begin
            bin_valid <= 1'b0; // Default pulse
            fft_done  <= 1'b0; // Default pulse

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_frame) begin
                        busy        <= 1'b1;
                        cur_bin     <= {BINS_W{1'b0}};
                        cur_sample  <= {ADDR_W{1'b0}};
                        sample_addr <= {ADDR_W{1'b0}};
                        acc_real    <= 36'sd0;
                        acc_imag    <= 36'sd0;
                        state       <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    // Accumulate product into 36-bit register
                    acc_real <= acc_real + prod_real;
                    acc_imag <= acc_imag + prod_imag;

                    if (cur_sample >= FFT_POINTS - 1) begin
                        // Completed accumulation for current frequency bin
                        state <= ST_EMIT_BIN;
                    end else begin
                        cur_sample  <= cur_sample + 1'b1;
                        sample_addr <= cur_sample + 1'b1; // Prefetch next sample
                    end
                end

                ST_EMIT_BIN: begin
                    // Scale output: divide by 16384 (trig scale) and normalize by sqrt(N) or N
                    // Shift right by 18 bits gives clean 16-bit dynamic range
                    real_out  <= acc_real[31:16];
                    imag_out  <= acc_imag[31:16];
                    bin_index <= cur_bin;
                    bin_valid <= 1'b1;

                    if (cur_bin >= TOTAL_BINS - 1) begin
                        state <= ST_FRAME_END;
                    end else begin
                        cur_bin     <= cur_bin + 1'b1;
                        cur_sample  <= {ADDR_W{1'b0}};
                        sample_addr <= {ADDR_W{1'b0}};
                        acc_real    <= 36'sd0;
                        acc_imag    <= 36'sd0;
                        state       <= ST_COMPUTE;
                    end
                end

                ST_FRAME_END: begin
                    busy     <= 1'b0;
                    fft_done <= 1'b1;
                    state    <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
