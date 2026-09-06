//=============================================================================
// Module: audio_top
// Description: Top-Level System Integration of the Real-Time Audio Spectrum
//              Analyzer and Noise Classification System for the Altera/Intel
//              DE2-115 Development Board (Cyclone IV EP4CE115F29C7).
//              Integrates:
//                1. Wolfson WM8731 I2C Codec Configurator (48 kHz, 16-bit I2S)
//                2. Philips I2S Audio Streaming Receiver
//                3. Dual-Bank Ping-Pong Sample Buffer (256/512 points)
//                4. Hanning Spectral Windowing Unit
//                5. Radix-2 Discrete Fourier Transform (FFT) Engine
//                6. Alpha-Max Beta-Min (AMBM) Vector Magnitude Approximator
//                7. 6-Band Psychoacoustic Frequency Energy Extractor
//                8. Deterministic Spectral Noise Classification Engine
//                9. 640x480 @ 60Hz VGA Gradient Equalizer Dashboard with Peak-Hold
//               10. HD44780 16x2 Character LCD Controller
//               11. 115200 Baud ASCII Serial Telemetry Logger
//               12. Onboard Synthetic DDS Tone & Noise Verification Generator
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module audio_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer FFT_POINTS  = 256,
    parameter integer SIMULATION  = 0
)(
    // Clock & Pushbuttons
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,               // KEY[0]: Reset_n, KEY[1]: Re-init Codec, KEY[2]: Tone Cycle
    input  wire [17:0] SW,                // SW[17]: Synth Mode, SW[16:14]: Tone Sel

    // Onboard Wolfson WM8731 Codec Physical Interface
    output wire        I2C_SCLK,          // PIN_B7
    inout  wire        I2C_SDAT,          // PIN_A8
    input  wire        AUD_BCLK,          // PIN_F2
    output wire        AUD_XCK,           // PIN_E1 (12.5 MHz Master Clock)
    input  wire        AUD_ADCLRCK,       // PIN_E2
    input  wire        AUD_ADCDAT,        // PIN_D2
    output wire        AUD_DACLRCK,       // PIN_E3
    output wire        AUD_DACDAT,        // PIN_D1

    // 16x2 Character LCD
    inout  wire [7:0]  LCD_DATA,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_RS,

    // ADV7123 24-bit Video DAC (VGA)
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,

    // 7-Segment Displays (HEX0 - HEX7)
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3,
    output wire [6:0]  HEX4, HEX5, HEX6, HEX7,

    // Status LEDs
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // RS-232 UART Telemetry
    output wire        UART_TXD
);

    // -------------------------------------------------------------------------
    // Reset Synchronizer
    // -------------------------------------------------------------------------
    wire sys_reset_n;
    reset_synchronizer #(
        .STAGES(2),
        .ACTIVE_LOW_IN(1),
        .ACTIVE_LOW_OUT(1)
    ) u_reset_sync (
        .clk(CLOCK_50),
        .async_rst_in(KEY[0]),
        .sync_rst_out(sys_reset_n)
    );

    // -------------------------------------------------------------------------
    // Pushbutton Debounce
    // -------------------------------------------------------------------------
    localparam integer DB_CLK_FREQ = (SIMULATION) ? 10_000 : CLK_FREQ_HZ;
    wire btn_reinit_pulse, btn_tone_pulse;

    button_debounce #(
        .CLK_FREQ_HZ(DB_CLK_FREQ), .DEBOUNCE_MS(SIMULATION ? 1 : 20), .ACTIVE_LOW_IN(1)
    ) u_db_key1 (
        .clk(CLOCK_50), .rst(!sys_reset_n), .btn_in(KEY[1]), .debounced_state(),
        .pressed_pulse(btn_reinit_pulse), .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(DB_CLK_FREQ), .DEBOUNCE_MS(SIMULATION ? 1 : 20), .ACTIVE_LOW_IN(1)
    ) u_db_key2 (
        .clk(CLOCK_50), .rst(!sys_reset_n), .btn_in(KEY[2]), .debounced_state(),
        .pressed_pulse(btn_tone_pulse), .released_pulse()
    );

    // -------------------------------------------------------------------------
    // Periodic Timers (1-Second Tick and 100ms Tick)
    // -------------------------------------------------------------------------
    wire tick_1sec, tick_100ms;
    periodic_timer #(.PERIOD(SIMULATION ? 50_000 : CLK_FREQ_HZ), .WIDTH(32)) u_timer_1s (
        .clk(CLOCK_50), .rst(!sys_reset_n), .enable(1'b1), .tick_in(1'b1), .tick_out(tick_1sec), .count_val()
    );
    periodic_timer #(.PERIOD(SIMULATION ? 5_000 : (CLK_FREQ_HZ / 10)), .WIDTH(32)) u_timer_100ms (
        .clk(CLOCK_50), .rst(!sys_reset_n), .enable(1'b1), .tick_in(1'b1), .tick_out(tick_100ms), .count_val()
    );

    // -------------------------------------------------------------------------
    // WM8731 Master Clock Generator (50 MHz / 4 = 12.5 MHz)
    // -------------------------------------------------------------------------
    reg [1:0] xck_div;
    always @(posedge CLOCK_50 or negedge sys_reset_n) begin
        if (!sys_reset_n)
            xck_div <= 2'b00;
        else
            xck_div <= xck_div + 1'b1;
    end
    assign AUD_XCK = xck_div[1]; // 12.5 MHz MCLK for WM8731

    // Unused DAC outputs tied off safely
    assign AUD_DACLRCK = AUD_ADCLRCK;
    assign AUD_DACDAT  = 1'b0;

    // -------------------------------------------------------------------------
    // WM8731 I2C Codec Configurator
    // -------------------------------------------------------------------------
    wire codec_config_done;
    wire codec_config_err;

    wm8731_configurator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(SIMULATION ? 400_000 : 100_000)
    ) u_wm8731_cfg (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .start(btn_reinit_pulse),
        .config_done(codec_config_done),
        .config_error(codec_config_err),
        .i2c_scl(I2C_SCLK),
        .i2c_sda(I2C_SDAT)
    );

    // -------------------------------------------------------------------------
    // Philips I2S Audio Streaming Receiver
    // -------------------------------------------------------------------------
    wire signed [15:0] i2s_left_pcm, i2s_right_pcm;
    wire               i2s_sample_valid;

    i2s_receiver #(
        .AUDIO_WIDTH(16)
    ) u_i2s_rx (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .i2s_bclk(AUD_BCLK),
        .i2s_lrclk(AUD_ADCLRCK),
        .i2s_sdata(AUD_ADCDAT),
        .left_data(i2s_left_pcm),
        .right_data(i2s_right_pcm),
        .sample_valid(i2s_sample_valid)
    );

    // -------------------------------------------------------------------------
    // Synthetic DDS Tone & Noise Generator for Bench Verification
    // -------------------------------------------------------------------------
    reg [2:0] tone_sel_reg;
    always @(posedge CLOCK_50 or negedge sys_reset_n) begin
        if (!sys_reset_n)
            tone_sel_reg <= 3'd1; // Default 1 kHz test tone
        else if (btn_tone_pulse)
            tone_sel_reg <= (tone_sel_reg >= 3'd4) ? 3'd0 : (tone_sel_reg + 1'b1);
        else if (SW[17])
            tone_sel_reg <= SW[16:14];
    end

    wire [2:0] active_tone_sel = tone_sel_reg;
    wire signed [15:0] dds_sample;
    wire               dds_sample_tick;

    sine_lut_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SAMPLE_RATE(SIMULATION ? 2_500_000 : 48_000),
        .SIMULATION(SIMULATION)
    ) u_dds_gen (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .tone_select(active_tone_sel),
        .audio_sample(dds_sample),
        .sample_tick(dds_sample_tick)
    );

    // Audio Input Multiplexer (Physical I2S vs Synthetic DDS)
    wire synth_audio_mode = SW[17];
    wire signed [15:0] eff_audio_sample = synth_audio_mode ? dds_sample : i2s_left_pcm;
    wire               eff_sample_valid = synth_audio_mode ? dds_sample_tick : i2s_sample_valid;

    // -------------------------------------------------------------------------
    // Dual-Bank Ping-Pong Sample Buffer
    // -------------------------------------------------------------------------
    wire [$clog2(FFT_POINTS)-1:0] pp_rd_addr;
    wire signed [15:0]            pp_rd_data;
    wire                          pp_buffer_ready;
    wire                          pp_active_bank;

    audio_pingpong_buffer #(
        .BUFFER_SIZE(FFT_POINTS),
        .DATA_WIDTH(16)
    ) u_pingpong (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .sample_in(eff_audio_sample),
        .sample_valid(eff_sample_valid),
        .rd_addr(pp_rd_addr),
        .rd_data(pp_rd_data),
        .buffer_ready_pulse(pp_buffer_ready),
        .active_bank(pp_active_bank)
    );

    // -------------------------------------------------------------------------
    // Hanning Spectral Windowing Unit
    // -------------------------------------------------------------------------
    wire [$clog2(FFT_POINTS)-1:0] win_out_idx;
    wire signed [15:0]            win_sample_out;
    wire                          win_out_valid;

    hanning_window #(
        .BUFFER_SIZE(FFT_POINTS),
        .DATA_WIDTH(16)
    ) u_window (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .in_valid(1'b1), // Continuous window lookup for read data
        .sample_idx(pp_rd_addr),
        .sample_in(pp_rd_data),
        .out_valid(win_out_valid),
        .out_idx(win_out_idx),
        .sample_out(win_sample_out)
    );

    // -------------------------------------------------------------------------
    // Radix-2 Fast Fourier Transform (FFT) Core
    // -------------------------------------------------------------------------
    wire                          fft_busy;
    wire                          fft_done;
    wire [$clog2(FFT_POINTS)-1:0] fft_sample_addr;
    wire [$clog2(FFT_POINTS/2)-1:0] fft_bin_index;
    wire signed [15:0]            fft_real_out;
    wire signed [15:0]            fft_imag_out;
    wire                          fft_bin_valid;

    assign pp_rd_addr = fft_sample_addr;

    fft_radix2_core #(
        .FFT_POINTS(FFT_POINTS),
        .DATA_WIDTH(16)
    ) u_fft_core (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .start_frame(pp_buffer_ready),
        .busy(fft_busy),
        .fft_done(fft_done),
        .sample_addr(fft_sample_addr),
        .sample_data(win_sample_out), // Windowed sample data
        .bin_index(fft_bin_index),
        .real_out(fft_real_out),
        .imag_out(fft_imag_out),
        .bin_valid(fft_bin_valid)
    );

    // -------------------------------------------------------------------------
    // Alpha-Max Beta-Min Magnitude Approximator
    // -------------------------------------------------------------------------
    wire                          mag_valid;
    wire [$clog2(FFT_POINTS/2)-1:0] mag_bin_idx;
    wire [15:0]                   magnitude_val;

    magnitude_approximator #(
        .DATA_WIDTH(16),
        .BIN_WIDTH($clog2(FFT_POINTS/2))
    ) u_mag_approx (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .bin_valid(fft_bin_valid),
        .bin_index(fft_bin_index),
        .real_in(fft_real_out),
        .imag_in(fft_imag_out),
        .mag_valid(mag_valid),
        .mag_bin_index(mag_bin_idx),
        .magnitude_out(magnitude_val)
    );

    // -------------------------------------------------------------------------
    // 6-Band Psychoacoustic Spectral Energy Extractor
    // -------------------------------------------------------------------------
    wire [23:0] b0_eng, b1_eng, b2_eng, b3_eng, b4_eng, b5_eng;
    wire [27:0] total_energy;
    wire [$clog2(FFT_POINTS/2)-1:0] peak_bin_index;
    wire [15:0] peak_magnitude;
    wire        frame_valid_pulse;

    spectral_band_extractor #(
        .FFT_POINTS(FFT_POINTS),
        .DATA_WIDTH(16)
    ) u_band_extractor (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .mag_valid(mag_valid),
        .bin_index(mag_bin_idx),
        .magnitude(magnitude_val),
        .fft_done(fft_done),
        .band0_energy(b0_eng),
        .band1_energy(b1_eng),
        .band2_energy(b2_eng),
        .band3_energy(b3_eng),
        .band4_energy(b4_eng),
        .band5_energy(b5_eng),
        .total_energy(total_energy),
        .peak_bin_index(peak_bin_index),
        .peak_magnitude(peak_magnitude),
        .frame_valid_pulse(frame_valid_pulse)
    );

    // -------------------------------------------------------------------------
    // Deterministic Spectral Noise Classifier
    // -------------------------------------------------------------------------
    wire [2:0]  class_code;
    wire [31:0] class_ascii;
    wire [7:0]  confidence_pct;
    wire        class_valid_pulse;

    noise_classifier #(
        .QUIET_THRESHOLD(50)
    ) u_classifier (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .frame_valid_pulse(frame_valid_pulse),
        .total_energy(total_energy),
        .band0_energy(b0_eng),
        .band1_energy(b1_eng),
        .band2_energy(b2_eng),
        .band3_energy(b3_eng),
        .band4_energy(b4_eng),
        .band5_energy(b5_eng),
        .peak_bin_index({{(8-$clog2(FFT_POINTS/2)){1'b0}}, peak_bin_index}),
        .class_code(class_code),
        .class_ascii(class_ascii),
        .confidence_pct(confidence_pct),
        .class_valid_pulse(class_valid_pulse)
    );

    // -------------------------------------------------------------------------
    // 640x480 @ 60Hz Graphical VGA Display
    // -------------------------------------------------------------------------
    vga_spectrum_display u_vga_disp (
        .clk_50(CLOCK_50),
        .reset_n(sys_reset_n),
        .band0_energy(b0_eng),
        .band1_energy(b1_eng),
        .band2_energy(b2_eng),
        .band3_energy(b3_eng),
        .band4_energy(b4_eng),
        .band5_energy(b5_eng),
        .total_energy(total_energy),
        .peak_bin_index({{(8-$clog2(FFT_POINTS/2)){1'b0}}, peak_bin_index}),
        .peak_magnitude(peak_magnitude),
        .class_code(class_code),
        .class_ascii(class_ascii),
        .confidence_pct(confidence_pct),
        .vga_clk(VGA_CLK),
        .vga_hs(VGA_HS),
        .vga_vs(VGA_VS),
        .vga_blank_n(VGA_BLANK_N),
        .vga_sync_n(VGA_SYNC_N),
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B)
    );

    // -------------------------------------------------------------------------
    // HD44780 16x2 Character LCD Driver
    // -------------------------------------------------------------------------
    function [7:0] dec_char;
        input [3:0] d;
        begin
            dec_char = 8'h30 + d;
        end
    endfunction

    reg [127:0] lcd_line1, lcd_line2;
    always @(*) begin
        // Line 1: "CLS:XXXX CONF:XX%"
        lcd_line1 = {"C", "L", "S", ":", class_ascii, " ", "C", "F", ":",
                     dec_char((confidence_pct / 10) % 10),
                     dec_char(confidence_pct % 10), "%", "  "};
        // Line 2: "PK:xxx MAG:xxxxx"
        lcd_line2 = {"P", "K", ":", dec_char((peak_bin_index / 100) % 10),
                                  dec_char((peak_bin_index / 10) % 10),
                                  dec_char(peak_bin_index % 10), " ",
                     "M", "G", ":", dec_char((peak_magnitude / 10000) % 10),
                                  dec_char((peak_magnitude / 1000) % 10),
                                  dec_char((peak_magnitude / 100) % 10),
                                  dec_char((peak_magnitude / 10) % 10),
                                  dec_char(peak_magnitude % 10)};
    end

    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk(CLOCK_50),
        .rst(!sys_reset_n),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .refresh_strobe(tick_100ms),
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // -------------------------------------------------------------------------
    // 115200 Baud ASCII Telemetry Logger
    // -------------------------------------------------------------------------
    wire uart_tx_active;
    audio_uart_logger #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(115200)
    ) u_uart_logger (
        .clk(CLOCK_50),
        .reset_n(sys_reset_n),
        .frame_valid(frame_valid_pulse),
        .class_code(class_code),
        .class_ascii(class_ascii),
        .peak_bin_index({{(8-$clog2(FFT_POINTS/2)){1'b0}}, peak_bin_index}),
        .peak_magnitude(peak_magnitude),
        .total_energy(total_energy),
        .tick_1sec(tick_1sec),
        .uart_txd(UART_TXD),
        .tx_active_led(uart_tx_active)
    );

    // -------------------------------------------------------------------------
    // 8x 7-Segment Displays
    // -------------------------------------------------------------------------
    // HEX7: Classification Code (0..4)
    seven_seg_hex u_hex7 (.hex_digit({1'b0, class_code}), .blank(1'b0), .seg_out(HEX7));
    // HEX6: Audio Mode (1: Synthetic DDS, 0: Physical I2S)
    seven_seg_hex u_hex6 (.hex_digit({3'b000, synth_audio_mode}), .blank(1'b0), .seg_out(HEX6));
    // HEX5-4: Peak Frequency Bin (00 - 99)
    wire [3:0] dec_bin_tens      = (peak_bin_index / 10) % 10;
    wire [3:0] dec_bin_ones      = peak_bin_index % 10;
    wire [3:0] dec_eng_thousands = (total_energy / 1000) % 10;
    wire [3:0] dec_eng_hundreds  = (total_energy / 100) % 10;
    wire [3:0] dec_eng_tens      = (total_energy / 10) % 10;
    wire [3:0] dec_eng_ones      = total_energy % 10;

    seven_seg_dec u_hex5 (.dec_digit(dec_bin_tens),      .blank(1'b0), .show_dash(1'b0), .seg_out(HEX5));
    seven_seg_dec u_hex4 (.dec_digit(dec_bin_ones),      .blank(1'b0), .show_dash(1'b0), .seg_out(HEX4));
    // HEX3-0: Total Energy
    seven_seg_dec u_hex3 (.dec_digit(dec_eng_thousands), .blank(1'b0), .show_dash(1'b0), .seg_out(HEX3));
    seven_seg_dec u_hex2 (.dec_digit(dec_eng_hundreds),  .blank(1'b0), .show_dash(1'b0), .seg_out(HEX2));
    seven_seg_dec u_hex1 (.dec_digit(dec_eng_tens),      .blank(1'b0), .show_dash(1'b0), .seg_out(HEX1));
    seven_seg_dec u_hex0 (.dec_digit(dec_eng_ones),      .blank(1'b0), .show_dash(1'b0), .seg_out(HEX0));

    // -------------------------------------------------------------------------
    // Status LEDs
    // -------------------------------------------------------------------------
    // LEDG:
    // [0]: Codec Init Done, [1]: I2S/Audio Active, [2]: FFT Busy, [3]: UART Active
    // [8:4]: One-Hot Classification (0:Quiet, 1:Speech, 2:Low, 3:High, 4:Noise)
    assign LEDG[0]   = codec_config_done;
    assign LEDG[1]   = eff_sample_valid;
    assign LEDG[2]   = fft_busy;
    assign LEDG[3]   = uart_tx_active;
    assign LEDG[4]   = (class_code == 3'd0); // QUIET
    assign LEDG[5]   = (class_code == 3'd1); // SPEECH
    assign LEDG[6]   = (class_code == 3'd2); // LOW-FREQ
    assign LEDG[7]   = (class_code == 3'd3); // HIGH-FREQ
    assign LEDG[8]   = (class_code == 3'd4); // NOISE

    // LEDR:
    // [5:0]: 6-Band Equalizer Activity
    // [16]: Codec I2C Error, [17]: Synthetic Mode Active
    assign LEDR[0]    = (b0_eng > 24'd100);
    assign LEDR[1]    = (b1_eng > 24'd100);
    assign LEDR[2]    = (b2_eng > 24'd100);
    assign LEDR[3]    = (b3_eng > 24'd100);
    assign LEDR[4]    = (b4_eng > 24'd100);
    assign LEDR[5]    = (b5_eng > 24'd100);
    assign LEDR[15:6] = 10'd0;
    assign LEDR[16]   = codec_config_err;
    assign LEDR[17]   = synth_audio_mode;

endmodule
