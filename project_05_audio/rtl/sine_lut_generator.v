//=============================================================================
// Module: sine_lut_generator
// Description: Direct Digital Synthesis (DDS) test tone generator and Galois LFSR
//              white noise source for bench verification of the Audio Spectrum Analyzer.
//              Generates 16-bit signed PCM audio samples at 48 kHz for known
//              test frequencies: 1 kHz, 2 kHz, 5 kHz, and broadband noise.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module sine_lut_generator #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer SAMPLE_RATE = 48_000,
    parameter integer SIMULATION  = 0
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire [2:0]  tone_select,    // 0: Silence, 1: 1kHz, 2: 2kHz, 3: 5kHz, 4: Noise
    output reg  signed [15:0] audio_sample,
    output reg         sample_tick
);

    // 48 kHz Sample Tick Generator
    localparam integer TICK_DIV = CLK_FREQ_HZ / SAMPLE_RATE;
    reg [11:0] tick_cnt;

    always @(posedge clk) begin
        if (!reset_n) begin
            tick_cnt    <= 12'd0;
            sample_tick <= 1'b0;
        end else begin
            if (tick_cnt >= TICK_DIV - 1) begin
                tick_cnt    <= 12'd0;
                sample_tick <= 1'b1;
            end else begin
                tick_cnt    <= tick_cnt + 1'b1;
                sample_tick <= 1'b0;
            end
        end
    end

    // 256-word 16-bit Signed Sine Wave ROM
    reg signed [15:0] sine_rom [0:255];
    integer i;

    initial begin
        sine_rom[0] = 16'sh0000;
        sine_rom[1] = 16'sh01EB;
        sine_rom[2] = 16'sh03D5;
        sine_rom[3] = 16'sh05BF;
        sine_rom[4] = 16'sh07A8;
        sine_rom[5] = 16'sh0990;
        sine_rom[6] = 16'sh0B77;
        sine_rom[7] = 16'sh0D5B;
        sine_rom[8] = 16'sh0F3E;
        sine_rom[9] = 16'sh111E;
        sine_rom[10] = 16'sh12FC;
        sine_rom[11] = 16'sh14D6;
        sine_rom[12] = 16'sh16AE;
        sine_rom[13] = 16'sh1882;
        sine_rom[14] = 16'sh1A52;
        sine_rom[15] = 16'sh1C1E;
        sine_rom[16] = 16'sh1DE6;
        sine_rom[17] = 16'sh1FA9;
        sine_rom[18] = 16'sh2167;
        sine_rom[19] = 16'sh2320;
        sine_rom[20] = 16'sh24D4;
        sine_rom[21] = 16'sh2682;
        sine_rom[22] = 16'sh282A;
        sine_rom[23] = 16'sh29CC;
        sine_rom[24] = 16'sh2B67;
        sine_rom[25] = 16'sh2CFC;
        sine_rom[26] = 16'sh2E8A;
        sine_rom[27] = 16'sh3011;
        sine_rom[28] = 16'sh3190;
        sine_rom[29] = 16'sh3307;
        sine_rom[30] = 16'sh3477;
        sine_rom[31] = 16'sh35DF;
        sine_rom[32] = 16'sh373E;
        sine_rom[33] = 16'sh3895;
        sine_rom[34] = 16'sh39E3;
        sine_rom[35] = 16'sh3B28;
        sine_rom[36] = 16'sh3C64;
        sine_rom[37] = 16'sh3D97;
        sine_rom[38] = 16'sh3EC0;
        sine_rom[39] = 16'sh3FE0;
        sine_rom[40] = 16'sh40F5;
        sine_rom[41] = 16'sh4201;
        sine_rom[42] = 16'sh4303;
        sine_rom[43] = 16'sh43FA;
        sine_rom[44] = 16'sh44E6;
        sine_rom[45] = 16'sh45C8;
        sine_rom[46] = 16'sh46A0;
        sine_rom[47] = 16'sh476C;
        sine_rom[48] = 16'sh482E;
        sine_rom[49] = 16'sh48E4;
        sine_rom[50] = 16'sh498F;
        sine_rom[51] = 16'sh4A2F;
        sine_rom[52] = 16'sh4AC3;
        sine_rom[53] = 16'sh4B4C;
        sine_rom[54] = 16'sh4BC9;
        sine_rom[55] = 16'sh4C3A;
        sine_rom[56] = 16'sh4CA0;
        sine_rom[57] = 16'sh4CFA;
        sine_rom[58] = 16'sh4D48;
        sine_rom[59] = 16'sh4D8A;
        sine_rom[60] = 16'sh4DC0;
        sine_rom[61] = 16'sh4DEA;
        sine_rom[62] = 16'sh4E08;
        sine_rom[63] = 16'sh4E1A;
        sine_rom[64] = 16'sh4E20;
        sine_rom[65] = 16'sh4E1A;
        sine_rom[66] = 16'sh4E08;
        sine_rom[67] = 16'sh4DEA;
        sine_rom[68] = 16'sh4DC0;
        sine_rom[69] = 16'sh4D8A;
        sine_rom[70] = 16'sh4D48;
        sine_rom[71] = 16'sh4CFA;
        sine_rom[72] = 16'sh4CA0;
        sine_rom[73] = 16'sh4C3A;
        sine_rom[74] = 16'sh4BC9;
        sine_rom[75] = 16'sh4B4C;
        sine_rom[76] = 16'sh4AC3;
        sine_rom[77] = 16'sh4A2F;
        sine_rom[78] = 16'sh498F;
        sine_rom[79] = 16'sh48E4;
        sine_rom[80] = 16'sh482E;
        sine_rom[81] = 16'sh476C;
        sine_rom[82] = 16'sh46A0;
        sine_rom[83] = 16'sh45C8;
        sine_rom[84] = 16'sh44E6;
        sine_rom[85] = 16'sh43FA;
        sine_rom[86] = 16'sh4303;
        sine_rom[87] = 16'sh4201;
        sine_rom[88] = 16'sh40F5;
        sine_rom[89] = 16'sh3FE0;
        sine_rom[90] = 16'sh3EC0;
        sine_rom[91] = 16'sh3D97;
        sine_rom[92] = 16'sh3C64;
        sine_rom[93] = 16'sh3B28;
        sine_rom[94] = 16'sh39E3;
        sine_rom[95] = 16'sh3895;
        sine_rom[96] = 16'sh373E;
        sine_rom[97] = 16'sh35DF;
        sine_rom[98] = 16'sh3477;
        sine_rom[99] = 16'sh3307;
        sine_rom[100] = 16'sh3190;
        sine_rom[101] = 16'sh3011;
        sine_rom[102] = 16'sh2E8A;
        sine_rom[103] = 16'sh2CFC;
        sine_rom[104] = 16'sh2B67;
        sine_rom[105] = 16'sh29CC;
        sine_rom[106] = 16'sh282A;
        sine_rom[107] = 16'sh2682;
        sine_rom[108] = 16'sh24D4;
        sine_rom[109] = 16'sh2320;
        sine_rom[110] = 16'sh2167;
        sine_rom[111] = 16'sh1FA9;
        sine_rom[112] = 16'sh1DE6;
        sine_rom[113] = 16'sh1C1E;
        sine_rom[114] = 16'sh1A52;
        sine_rom[115] = 16'sh1882;
        sine_rom[116] = 16'sh16AE;
        sine_rom[117] = 16'sh14D6;
        sine_rom[118] = 16'sh12FC;
        sine_rom[119] = 16'sh111E;
        sine_rom[120] = 16'sh0F3E;
        sine_rom[121] = 16'sh0D5B;
        sine_rom[122] = 16'sh0B77;
        sine_rom[123] = 16'sh0990;
        sine_rom[124] = 16'sh07A8;
        sine_rom[125] = 16'sh05BF;
        sine_rom[126] = 16'sh03D5;
        sine_rom[127] = 16'sh01EB;
        sine_rom[128] = 16'sh0000;
        sine_rom[129] = 16'shFE15;
        sine_rom[130] = 16'shFC2B;
        sine_rom[131] = 16'shFA41;
        sine_rom[132] = 16'shF858;
        sine_rom[133] = 16'shF670;
        sine_rom[134] = 16'shF489;
        sine_rom[135] = 16'shF2A5;
        sine_rom[136] = 16'shF0C2;
        sine_rom[137] = 16'shEEE2;
        sine_rom[138] = 16'shED04;
        sine_rom[139] = 16'shEB2A;
        sine_rom[140] = 16'shE952;
        sine_rom[141] = 16'shE77E;
        sine_rom[142] = 16'shE5AE;
        sine_rom[143] = 16'shE3E2;
        sine_rom[144] = 16'shE21A;
        sine_rom[145] = 16'shE057;
        sine_rom[146] = 16'shDE99;
        sine_rom[147] = 16'shDCE0;
        sine_rom[148] = 16'shDB2C;
        sine_rom[149] = 16'shD97E;
        sine_rom[150] = 16'shD7D6;
        sine_rom[151] = 16'shD634;
        sine_rom[152] = 16'shD499;
        sine_rom[153] = 16'shD304;
        sine_rom[154] = 16'shD176;
        sine_rom[155] = 16'shCFEF;
        sine_rom[156] = 16'shCE70;
        sine_rom[157] = 16'shCCF9;
        sine_rom[158] = 16'shCB89;
        sine_rom[159] = 16'shCA21;
        sine_rom[160] = 16'shC8C2;
        sine_rom[161] = 16'shC76B;
        sine_rom[162] = 16'shC61D;
        sine_rom[163] = 16'shC4D8;
        sine_rom[164] = 16'shC39C;
        sine_rom[165] = 16'shC269;
        sine_rom[166] = 16'shC140;
        sine_rom[167] = 16'shC020;
        sine_rom[168] = 16'shBF0B;
        sine_rom[169] = 16'shBDFF;
        sine_rom[170] = 16'shBCFD;
        sine_rom[171] = 16'shBC06;
        sine_rom[172] = 16'shBB1A;
        sine_rom[173] = 16'shBA38;
        sine_rom[174] = 16'shB960;
        sine_rom[175] = 16'shB894;
        sine_rom[176] = 16'shB7D2;
        sine_rom[177] = 16'shB71C;
        sine_rom[178] = 16'shB671;
        sine_rom[179] = 16'shB5D1;
        sine_rom[180] = 16'shB53D;
        sine_rom[181] = 16'shB4B4;
        sine_rom[182] = 16'shB437;
        sine_rom[183] = 16'shB3C6;
        sine_rom[184] = 16'shB360;
        sine_rom[185] = 16'shB306;
        sine_rom[186] = 16'shB2B8;
        sine_rom[187] = 16'shB276;
        sine_rom[188] = 16'shB240;
        sine_rom[189] = 16'shB216;
        sine_rom[190] = 16'shB1F8;
        sine_rom[191] = 16'shB1E6;
        sine_rom[192] = 16'shB1E0;
        sine_rom[193] = 16'shB1E6;
        sine_rom[194] = 16'shB1F8;
        sine_rom[195] = 16'shB216;
        sine_rom[196] = 16'shB240;
        sine_rom[197] = 16'shB276;
        sine_rom[198] = 16'shB2B8;
        sine_rom[199] = 16'shB306;
        sine_rom[200] = 16'shB360;
        sine_rom[201] = 16'shB3C6;
        sine_rom[202] = 16'shB437;
        sine_rom[203] = 16'shB4B4;
        sine_rom[204] = 16'shB53D;
        sine_rom[205] = 16'shB5D1;
        sine_rom[206] = 16'shB671;
        sine_rom[207] = 16'shB71C;
        sine_rom[208] = 16'shB7D2;
        sine_rom[209] = 16'shB894;
        sine_rom[210] = 16'shB960;
        sine_rom[211] = 16'shBA38;
        sine_rom[212] = 16'shBB1A;
        sine_rom[213] = 16'shBC06;
        sine_rom[214] = 16'shBCFD;
        sine_rom[215] = 16'shBDFF;
        sine_rom[216] = 16'shBF0B;
        sine_rom[217] = 16'shC020;
        sine_rom[218] = 16'shC140;
        sine_rom[219] = 16'shC269;
        sine_rom[220] = 16'shC39C;
        sine_rom[221] = 16'shC4D8;
        sine_rom[222] = 16'shC61D;
        sine_rom[223] = 16'shC76B;
        sine_rom[224] = 16'shC8C2;
        sine_rom[225] = 16'shCA21;
        sine_rom[226] = 16'shCB89;
        sine_rom[227] = 16'shCCF9;
        sine_rom[228] = 16'shCE70;
        sine_rom[229] = 16'shCFEF;
        sine_rom[230] = 16'shD176;
        sine_rom[231] = 16'shD304;
        sine_rom[232] = 16'shD499;
        sine_rom[233] = 16'shD634;
        sine_rom[234] = 16'shD7D6;
        sine_rom[235] = 16'shD97E;
        sine_rom[236] = 16'shDB2C;
        sine_rom[237] = 16'shDCE0;
        sine_rom[238] = 16'shDE99;
        sine_rom[239] = 16'shE057;
        sine_rom[240] = 16'shE21A;
        sine_rom[241] = 16'shE3E2;
        sine_rom[242] = 16'shE5AE;
        sine_rom[243] = 16'shE77E;
        sine_rom[244] = 16'shE952;
        sine_rom[245] = 16'shEB2A;
        sine_rom[246] = 16'shED04;
        sine_rom[247] = 16'shEEE2;
        sine_rom[248] = 16'shF0C2;
        sine_rom[249] = 16'shF2A5;
        sine_rom[250] = 16'shF489;
        sine_rom[251] = 16'shF670;
        sine_rom[252] = 16'shF858;
        sine_rom[253] = 16'shFA41;
        sine_rom[254] = 16'shFC2B;
        sine_rom[255] = 16'shFE15;
    end

    // Phase Tuning Words:
    // In Simulation (N=64 @ 2.5MHz):
    // Bin 2: 2048 (Speech Midrange Band 2)
    // Bin 3: 3072 (Speech Midrange Band 2)
    // Bin 5: 5120 (Upper-Mid / High-Frequency Band 3/4)
    // In Hardware (N=256 @ 48kHz): delta_phi = (f_target * 65536) / 48000
    localparam [15:0]
        PHASE_1KHZ = (SIMULATION) ? 16'd2048 : 16'd1365,
        PHASE_2KHZ = (SIMULATION) ? 16'd3072 : 16'd2731,
        PHASE_5KHZ = (SIMULATION) ? 16'd5120 : 16'd6827;

    reg [15:0] phase_acc;
    reg [15:0] lfsr_reg;

    always @(posedge clk) begin
        if (!reset_n) begin
            phase_acc    <= 16'd0;
            lfsr_reg     <= 16'hACE1;
            audio_sample <= 16'sd0;
        end else if (sample_tick) begin
            // 16-bit Galois LFSR for white noise (polynomial x^16 + x^14 + x^13 + x^11 + 1)
            lfsr_reg <= (lfsr_reg >> 1) ^ (-(lfsr_reg & 1'b1) & 16'hB400);

            case (tone_select)
                3'd0: begin // Silence
                    phase_acc    <= 16'd0;
                    audio_sample <= 16'sd0;
                end

                3'd1: begin // 1 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_1KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd2: begin // 2 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_2KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd3: begin // 5 kHz Sine Tone
                    phase_acc    <= phase_acc + PHASE_5KHZ;
                    audio_sample <= sine_rom[phase_acc[15:8]];
                end

                3'd4, 3'd5: begin // White Noise
                    audio_sample <= $signed(lfsr_reg);
                end

                default: begin
                    audio_sample <= 16'sd0;
                end
            endcase
        end
    end

endmodule
