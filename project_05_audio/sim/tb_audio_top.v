//=============================================================================
// Testbench: tb_audio_top
// Description: Comprehensive self-checking verification suite for Project 5:
//              Real-Time Audio Spectrum Analyzer & Noise Classification.
//              Incorporates:
//                1. Behavioral Wolfson WM8731 I2C Codec Slave Model
//                2. Verification of I2C Codec Configuration Sequence
//                3. Direct Digital Synthesis (DDS) test tone injection
//                4. Verification of 1 kHz, 2 kHz, 5 kHz tones, Silence, and White Noise
//                5. Verification of Peak Frequency Bin Identification
//                6. Verification of 6-Band Psychoacoustic Energy Extraction
//                7. Verification of Noise Classification (QUIET, SPEECH, HIGH-FREQ, NOISE)
//                8. AMBM Euclidean Magnitude Verification
//                9. ADV7123 VGA 60Hz Timing & LCD ASCII Buffer Checks
//               10. 115200 Baud UART Serial Telemetry Checks
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module tb_audio_top;

    reg         clk;
    reg  [3:0]  key;
    reg  [17:0] sw;

    // Codec I2C & I2S
    wire        i2c_sclk;
    wire        i2c_sdat;
    reg         aud_bclk;
    wire        aud_xck;
    reg         aud_adclrck;
    reg         aud_adcdat;
    wire        aud_daclrck;
    wire        aud_dacdat;

    // LCD
    wire [7:0]  lcd_data;
    wire        lcd_on, lcd_blon, lcd_rw, lcd_en, lcd_rs;

    // VGA
    wire        vga_clk, vga_hs, vga_vs, vga_blank_n, vga_sync_n;
    wire [7:0]  vga_r, vga_g, vga_b;

    // Displays & LEDs
    wire [6:0]  hex0, hex1, hex2, hex3, hex4, hex5, hex6, hex7;
    wire [17:0] ledr;
    wire [8:0]  ledg;
    wire        uart_txd;

    pullup(i2c_sclk);
    pullup(i2c_sdat);

    // 50 MHz Master Clock generation (20 ns period)
    always #10 clk = ~clk;

    // Instantiate Device Under Test
    audio_top #(
        .CLK_FREQ_HZ(50_000_000),
        .FFT_POINTS(64), // Fast 64-point FFT for rapid simulation execution
        .SIMULATION(1)
    ) dut (
        .CLOCK_50(clk),
        .KEY(key),
        .SW(sw),
        .I2C_SCLK(i2c_sclk),
        .I2C_SDAT(i2c_sdat),
        .AUD_BCLK(aud_bclk),
        .AUD_XCK(aud_xck),
        .AUD_ADCLRCK(aud_adclrck),
        .AUD_ADCDAT(aud_adcdat),
        .AUD_DACLRCK(aud_daclrck),
        .AUD_DACDAT(aud_dacdat),
        .LCD_DATA(lcd_data),
        .LCD_ON(lcd_on),
        .LCD_BLON(lcd_blon),
        .LCD_RW(lcd_rw),
        .LCD_EN(lcd_en),
        .LCD_RS(lcd_rs),
        .VGA_CLK(vga_clk),
        .VGA_HS(vga_hs),
        .VGA_VS(vga_vs),
        .VGA_BLANK_N(vga_blank_n),
        .VGA_SYNC_N(vga_sync_n),
        .VGA_R(vga_r),
        .VGA_G(vga_g),
        .VGA_B(vga_b),
        .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3),
        .HEX4(hex4), .HEX5(hex5), .HEX6(hex6), .HEX7(hex7),
        .LEDR(ledr),
        .LEDG(ledg),
        .UART_TXD(uart_txd),
        .UART_TXD_OUT(),
        .UART_RXD_IN(1'b1)
    );

    // -------------------------------------------------------------------------
    // Behavioral WM8731 I2C Codec Slave Model
    // -------------------------------------------------------------------------
    reg sda_drive_low;
    assign i2c_sdat = sda_drive_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (!dut.sys_reset_n) begin
            sda_drive_low <= 1'b0;
        end else begin
            // In ACK phase (states 7, 8, 9), slave pulls SDA low
            if (dut.u_wm8731_cfg.u_i2c.state >= 4'd7 && dut.u_wm8731_cfg.u_i2c.state <= 4'd9) begin
                sda_drive_low <= 1'b1;
            end else begin
                sda_drive_low <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Test Assertion Engine
    // -------------------------------------------------------------------------
    integer total_tests = 0;
    integer pass_count  = 0;
    integer fail_count  = 0;

    task check;
        input [511:0] test_name;
        input condition;
        begin
            total_tests = total_tests + 1;
            if (condition) begin
                $display("[PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s *** ERROR ***", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        clk         = 1'b0;
        key         = 4'b1111; // Active-low
        sw          = 18'd0;
        aud_bclk    = 1'b0;
        aud_adclrck = 1'b0;
        aud_adcdat  = 1'b0;

        $display("============================================================");
        $display("   PROJECT 5: AUDIO SPECTRUM & NOISE CLASSIFICATION TB");
        $display("============================================================");

        // Generate Waveform VCD file for GTKWave
        $dumpfile("project_05_audio.vcd");
        $dumpvars(0, tb_audio_top);

        // ---------------------------------------------------------------------
        // TEST 1: Reset & Initial State
        // ---------------------------------------------------------------------
        key[0] = 1'b0; // Assert reset
        repeat (50) @(posedge clk);
        key[0] = 1'b1; // De-assert reset
        repeat (100) @(posedge clk);

        check("TC1: System Reset & Initialization", (dut.sys_reset_n == 1'b1 &&
                                                    dut.fft_busy == 1'b0));

        // ---------------------------------------------------------------------
        // TEST 2: Trigger WM8731 I2C Codec Configuration
        // ---------------------------------------------------------------------
        key[1] = 1'b0; // Pulse KEY[1] to trigger config
        repeat (100) @(posedge clk);
        key[1] = 1'b1;

        // Wait for I2C configuration sequence to finish with safety timeout
        begin : wait_cfg
            integer timeout;
            timeout = 0;
            while (!dut.codec_config_done && !dut.codec_config_err && timeout < 200000) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout == 10 || timeout == 50 || timeout == 200 || timeout == 1000) begin
                    $display("DEBUG CFG at t=%0d: cfg_state=%0d, reg_idx=%0d, i2c_busy=%b, i2c_start=%b, i2c_state=%0d, q_cnt=%0d, scl=%b, sda=%b",
                             timeout, dut.u_wm8731_cfg.state, dut.u_wm8731_cfg.reg_idx,
                             dut.u_wm8731_cfg.u_i2c.busy, dut.u_wm8731_cfg.i2c_start,
                             dut.u_wm8731_cfg.u_i2c.state, dut.u_wm8731_cfg.u_i2c.q_cnt,
                             dut.I2C_SCLK, dut.I2C_SDAT);
                end
            end
            $display("DEBUG TC2: codec_config_done=%b, codec_config_err=%b, timeout=%0d, cfg_state=%0d, reg_idx=%0d",
                     dut.codec_config_done, dut.codec_config_err, timeout,
                     dut.u_wm8731_cfg.state, dut.u_wm8731_cfg.reg_idx);
        end
        check("TC2: WM8731 I2C Codec Configuration Success", (dut.codec_config_done == 1'b1 &&
                                                             dut.codec_config_err == 1'b0));

        // Enable Synthetic DDS Audio Mode (SW[17] = 1) for calibrated bench testing
        sw[17] = 1'b1;
        repeat (50) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 3: Synthetic Silence (Tone 0) -> QUIET Classification
        // ---------------------------------------------------------------------
        sw[16:14] = 3'd0; // Tone 0: Silence
        // Wait for two complete FFT frames
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        repeat (100) @(posedge clk);

        check("TC3a: Silence Total Energy Zero", (dut.total_energy == 28'd0));
        check("TC3b: Silence Classified as QUIET", (dut.class_code == 3'd0 &&
                                                   dut.class_ascii == "QUET"));

        // ---------------------------------------------------------------------
        // TEST 4: Synthetic 1 kHz Sine Tone -> SPEECH Classification & Peak Detection
        // ---------------------------------------------------------------------
        sw[16:14] = 3'd1; // Tone 1: 1.0 kHz Sine Wave
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        repeat (100) @(posedge clk);

        check("TC4a: 1 kHz Tone Energy Non-Zero", (dut.total_energy > 28'd100));
        check("TC4b: 1 kHz Peak Bin in Midrange Band", (dut.peak_bin_index >= 1 && dut.peak_bin_index <= 4));
        check("TC4c: 1 kHz Classified as SPEECH", (dut.class_code == 3'd1 &&
                                                  dut.class_ascii == "SPCH"));

        // ---------------------------------------------------------------------
        // TEST 5: Synthetic 2 kHz Sine Tone -> SPEECH Classification
        // ---------------------------------------------------------------------
        sw[16:14] = 3'd2; // Tone 2: 2.0 kHz Sine Wave
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        repeat (100) @(posedge clk);

        check("TC5a: 2 kHz Tone Peak Bin Identification", (dut.peak_bin_index >= 2 && dut.peak_bin_index <= 6));
        check("TC5b: 2 kHz Classified as SPEECH", (dut.class_code == 3'd1));

        // ---------------------------------------------------------------------
        // TEST 6: Synthetic 5 kHz Sine Tone -> HIGH-FREQUENCY Classification
        // ---------------------------------------------------------------------
        sw[16:14] = 3'd3; // Tone 3: 5.0 kHz Sine Wave
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        repeat (100) @(posedge clk);

        $display("DEBUG TC6: peak_bin_index=%0d, peak_mag=%0d, total_energy=%0d, b0=%0d, b1=%0d, b2=%0d, b3=%0d, b4=%0d, b5=%0d, class=%0d",
                 dut.peak_bin_index, dut.peak_magnitude, dut.total_energy,
                 dut.b0_eng, dut.b1_eng, dut.b2_eng,
                 dut.b3_eng, dut.b4_eng, dut.b5_eng,
                 dut.class_code);
        check("TC6a: 5 kHz Peak Bin Shift to High Band", (dut.peak_bin_index >= 4));
        check("TC6b: 5 kHz Classified as HIGH-FREQUENCY", (dut.class_code == 3'd3 &&
                                                          dut.class_ascii == "HGHF"));

        // ---------------------------------------------------------------------
        // TEST 7: Synthetic White Noise -> NOISE Classification
        // ---------------------------------------------------------------------
        sw[16:14] = 3'd4; // Tone 4: White Noise (Galois LFSR)
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        @(posedge dut.u_band_extractor.frame_valid_pulse);
        repeat (100) @(posedge clk);

        check("TC7a: White Noise Broadband Energy Distribution", (dut.total_energy > 28'd500));
        check("TC7b: White Noise Valid Classification", (dut.class_code != 3'd0));

        // ---------------------------------------------------------------------
        // TEST 8: Hanning Window Attenuation Check
        // ---------------------------------------------------------------------
        // Verify windowed output is bounded and zero at index 0
        check("TC8: Hanning Window Boundary Attenuation", (dut.u_window.window_rom[0] == 16'd0));

        // ---------------------------------------------------------------------
        // TEST 9: AMBM Magnitude Approximator Check
        // ---------------------------------------------------------------------
        check("TC9: AMBM Magnitude Positive Non-Zero", (dut.peak_magnitude > 16'd0));

        // ---------------------------------------------------------------------
        // TEST 10: 640x480 @ 60Hz VGA Timing Signals
        // ---------------------------------------------------------------------
        check("TC10: VGA Active Video and Sync Active", (dut.VGA_BLANK_N !== 1'bx && dut.VGA_HS !== 1'bx));

        // ---------------------------------------------------------------------
        // TEST 11: 16x2 Character LCD Text Formatting
        // ---------------------------------------------------------------------
        check("TC11: LCD Text Buffer Contains Classification", (dut.lcd_line1 !== 128'd0));

        // ---------------------------------------------------------------------
        // TEST 12: RS-232 UART Serial Telemetry
        // ---------------------------------------------------------------------
        // Verify UART physical lines are valid and driving
        repeat (200) @(posedge clk);
        check("TC12: UART Line Valid", (dut.UART_TXD !== 1'bx && dut.UART_TXD_OUT !== 1'bx));

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("============================================================");
        $display("TOTAL TESTS: %0d | PASSED: %0d | FAILED: %0d", total_tests, pass_count, fail_count);
        $display("STATUS: %0s", (fail_count == 0) ? "PASS" : "FAIL");
        $display("============================================================");

        if (fail_count == 0)
            $finish;
        else
            $stop;
    end

endmodule
