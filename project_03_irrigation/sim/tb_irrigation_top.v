// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   tb_irrigation_top.v
// Description: Comprehensive self-checking verification testbench for Project 3.
//              Verifies all 12 required test scenarios:
//                1. Dry Soil Irrigation Trigger (Moisture < Threshold - Hys -> Pump ON)
//                2. Wet Soil Shutoff (Moisture >= Threshold + Hys -> Pump OFF)
//                3. Rising Temperature Adaptive Threshold Boost
//                4. Falling Humidity Evaporation Compensation
//                5. Rain Sensor Lockout Precedence
//                6. Manual Override Prioritization
//                7. Threshold Crossing Deadband Hold
//                8. Hysteresis Anti-Chatter Immunity
//                9. Sensor Disconnection / Communication Timeout Diagnostics
//                10. DHT11 Checksum Error Detection
//                11. Minimum ON Time Runtime Protection
//                12. Minimum OFF Rest Time Protection
// Standard:    Verilog-2001 / SystemVerilog Compatible
// ============================================================================

`timescale 1ns / 1ps

module tb_irrigation_top;

    // Simulation Parameters
    parameter CLK_FREQ_HZ     = 1_000_000; // 1 MHz clock for fast simulation
    parameter SPI_CLK_HZ      = 50_000;    // 50 kHz SPI clock
    parameter BAUD_RATE       = 115_200;
    parameter MIN_ON_SECONDS  = 2;         // 2 seconds min ON for test speed
    parameter MIN_OFF_SECONDS = 3;         // 3 seconds min OFF for test speed

    reg         clk;
    reg  [3:0]  key;
    reg  [17:0] sw;

    wire        gpio_0;  // Relay Pump Control Output
    wire        gpio_1;  // ADC CS_N
    wire        gpio_3;  // ADC SCLK
    wire        gpio_5;  // ADC MOSI
    reg         gpio_7;  // ADC MISO
    wire        gpio_9;  // DHT11 1-Wire Bidirectional
    reg         gpio_11; // Rain Sensor Input

    wire [6:0]  hex0, hex1, hex2, hex3, hex4, hex5, hex6, hex7;
    wire [8:0]  ledg;
    wire [17:0] ledr;
    wire [7:0]  lcd_data;
    wire        lcd_rw, lcd_en, lcd_rs, lcd_on, lcd_blon;
    wire        uart_txd;

    integer pass_count = 0;
    integer fail_count = 0;

    // ------------------------------------------------------------------------
    // Device Under Test (DUT)
    // ------------------------------------------------------------------------
    irrigation_top #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SPI_CLK_HZ     (SPI_CLK_HZ),
        .BAUD_RATE      (BAUD_RATE),
        .MIN_ON_SECONDS (MIN_ON_SECONDS),
        .MIN_OFF_SECONDS(MIN_OFF_SECONDS),
        .SIM_SPEEDUP    (1),
        .DEFAULT_DIRECT_DO_MODE (0)
    ) dut (
        .CLOCK_50       (clk),
        .KEY            (key),
        .SW             (sw),
        .GPIO_0         (gpio_0),
        .GPIO_1         (gpio_1),
        .GPIO_3         (gpio_3),
        .GPIO_5         (gpio_5),
        .GPIO_7         (gpio_7),
        .GPIO_9         (gpio_9),
        .GPIO_11        (gpio_11),
        .HEX0           (hex0),
        .HEX1           (hex1),
        .HEX2           (hex2),
        .HEX3           (hex3),
        .HEX4           (hex4),
        .HEX5           (hex5),
        .HEX6           (hex6),
        .HEX7           (hex7),
        .LEDG           (ledg),
        .LEDR           (ledr),
        .LCD_DATA       (lcd_data),
        .LCD_RW         (lcd_rw),
        .LCD_EN         (lcd_en),
        .LCD_RS         (lcd_rs),
        .LCD_ON         (lcd_on),
        .LCD_BLON       (lcd_blon),
        .UART_TXD       (uart_txd)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (1 MHz = 1000ns period)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #500 clk = ~clk;

    // Pull-up resistor on 1-wire DHT11 line
    pullup(gpio_9);

    // ------------------------------------------------------------------------
    // Behavioral MCP3008 SPI ADC Model (Channel 0: Soil Moisture)
    // ------------------------------------------------------------------------
    reg [4:0] spi_bit_cnt;
    reg [9:0] slave_soil_adc_val;

    initial begin
        gpio_7             = 1'bz;
        slave_soil_adc_val = 10'd600; // Moderate moisture (~53%)
        spi_bit_cnt        = 0;
    end

    always @(negedge gpio_1) begin
        spi_bit_cnt <= 5'd0;
        gpio_7      <= 1'b0;
    end

    always @(posedge gpio_1) begin
        gpio_7 <= 1'bz;
    end

    always @(posedge gpio_3) begin
        if (!gpio_1) begin
            spi_bit_cnt <= spi_bit_cnt + 1'b1;
        end
    end

    always @(negedge gpio_3) begin
        if (!gpio_1) begin
            case (spi_bit_cnt)
                5'd14: gpio_7 <= slave_soil_adc_val[9];
                5'd15: gpio_7 <= slave_soil_adc_val[8];
                5'd16: gpio_7 <= slave_soil_adc_val[7];
                5'd17: gpio_7 <= slave_soil_adc_val[6];
                5'd18: gpio_7 <= slave_soil_adc_val[5];
                5'd19: gpio_7 <= slave_soil_adc_val[4];
                5'd20: gpio_7 <= slave_soil_adc_val[3];
                5'd21: gpio_7 <= slave_soil_adc_val[2];
                5'd22: gpio_7 <= slave_soil_adc_val[1];
                5'd23: gpio_7 <= slave_soil_adc_val[0];
                default: gpio_7 <= 1'b0;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Behavioral DHT11 Single-Wire Slave Model
    // ------------------------------------------------------------------------
    reg dht_slave_drive;
    assign gpio_9 = (dht_slave_drive) ? 1'b0 : 1'bz;

    reg [7:0] dht_hum_byte;
    reg [7:0] dht_temp_byte;
    reg       dht_corrupt_chk;

    initial begin
        dht_slave_drive = 1'b0;
        dht_hum_byte    = 8'd55;
        dht_temp_byte   = 8'd24;
        dht_corrupt_chk = 1'b0;
    end

    // Monitor DHT11 master start pulse
    integer low_us_count;
    integer bit_idx;
    reg [39:0] dht_packet;

    always begin
        // Wait for master to pull line LOW
        @(negedge gpio_9);
        low_us_count = 0;
        while (gpio_9 == 1'b0) begin
            #1000; // 1 us step
            low_us_count = low_us_count + 1;
        end

        // Check if master issued start signal (>100 us in fast sim)
        if (low_us_count >= 100) begin
            // Assemble 40-bit packet
            // Byte 0: Humidity, Byte 1: 0, Byte 2: Temp, Byte 3: 0, Byte 4: Checksum
            dht_packet[39:32] = dht_hum_byte;
            dht_packet[31:24] = 8'd0;
            dht_packet[23:16] = dht_temp_byte;
            dht_packet[15:8]  = 8'd0;
            if (dht_corrupt_chk)
                dht_packet[7:0] = 8'hFF; // Corrupted checksum
            else
                dht_packet[7:0] = dht_hum_byte + dht_temp_byte; // Valid checksum

            // Master released line. Wait 20 us
            #20000;

            // DHT11 responds: Pull LOW for 80 us
            dht_slave_drive = 1'b1;
            #80000;
            // Pull HIGH for 80 us (release to pullup)
            dht_slave_drive = 1'b0;
            #80000;

            // Send 40 bits
            for (bit_idx = 39; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                // 50 us LOW
                dht_slave_drive = 1'b1;
                #50000;
                // HIGH: 28 us for '0', 70 us for '1'
                dht_slave_drive = 1'b0;
                if (dht_packet[bit_idx] == 1'b1)
                    #70000;
                else
                    #28000;
            end

            // Final 50 us LOW end pulse
            dht_slave_drive = 1'b1;
            #50000;
            dht_slave_drive = 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task wait_cycles;
        input integer cycles;
        repeat (cycles) @(posedge clk);
    endtask

    task set_soil_adc;
        input [9:0] raw_val;
        begin
            slave_soil_adc_val = raw_val;
            // Also set synthetic registers
            sw[14:13] = 2'b00;
            sw[9:0]   = raw_val;
            wait_cycles(5000); // Allow SPI conversion & normalizer pipeline
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Verification Process
    // ------------------------------------------------------------------------
    initial begin
        $display("======================================================================");
        $display(" PROJECT 3: SMART ADAPTIVE IRRIGATION - INTEGRATION TESTBENCH");
        $display("======================================================================");

        // Initialization
        key     = 4'b1111;
        sw      = 18'd0;
        gpio_11 = 1'b0; // No rain
        wait_cycles(50);

        // Master Reset
        key[0] = 1'b0;
        wait_cycles(50);
        key[0] = 1'b1;
        wait_cycles(100);

        // --------------------------------------------------------------------
        // TEST 1: Dry Soil Irrigation Trigger (Moisture < Turn-On Threshold)
        // --------------------------------------------------------------------
        $display("[*] TEST 1: Dry Soil Irrigation Trigger");
        // Base TH = 40%, Turn-On = 35%. Set raw ADC = 850 (~20% moisture)
        set_soil_adc(10'd850);
        wait_cycles(2000);
        $display("    Moisture = %d%%, TurnOnTH = %d%%, Relay = %b, PumpRunning = %b",
                 dut.soil_moisture_pct, dut.turn_on_th, dut.GPIO_0, dut.pump_running);
        if (dut.GPIO_0 == 1'b1 && dut.pump_running == 1'b1) begin
            $display("    [PASS] Dry soil automatically triggered pump actuation.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Pump failed to turn ON for dry soil.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 2: Wet Soil Shutoff (Moisture >= Turn-Off Threshold)
        // --------------------------------------------------------------------
        $display("[*] TEST 2: Wet Soil Shutoff after Min ON Time");
        // Soil gets soaked: raw ADC = 200 (~100% moisture)
        set_soil_adc(10'd200);
        // Wait for MIN_ON_SECONDS (in sim_speedup, 1 sec = 100 ticks of CLK_FREQ / 100)
        // Wait 30000 cycles (> MIN_ON_SECONDS * 10000)
        wait_cycles(35000);
        $display("    Moisture = %d%%, TurnOffTH = %d%%, Relay = %b, PumpRunning = %b",
                 dut.soil_moisture_pct, dut.turn_off_th, dut.GPIO_0, dut.pump_running);
        if (dut.GPIO_0 == 1'b0 && dut.pump_running == 1'b0) begin
            $display("    [PASS] Saturated soil turned OFF pump after minimum ON duration.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Pump remained ON despite saturated soil.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 3: Rising Temperature Adaptive Threshold Boost
        // --------------------------------------------------------------------
        $display("[*] TEST 3: Rising Temperature Adaptive Threshold Boost");
        // In synthetic mode, set Temp = 35°C (35 - 25 = +10% boost)
        sw[17]    = 1'b1; // Synthetic mode
        sw[14:13] = 2'b01; // Select Temp
        sw[6:0]   = 7'd35; // Temp = 35°C
        wait_cycles(1000);
        $display("    Base TH = %d%%, Temp = %d°C, TempAdj = +%d%%, Adaptive TH = %d%%",
                 dut.base_threshold_reg, dut.cur_temp, dut.temp_adj, dut.adaptive_th);
        if (dut.adaptive_th == 7'd50 && dut.temp_adj == 5'd10) begin
            $display("    [PASS] Rising temperature increased adaptive threshold by +10%%.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Temperature threshold boost calculation failed.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 4: Falling Humidity Evaporation Compensation
        // --------------------------------------------------------------------
        $display("[*] TEST 4: Falling Humidity Evaporation Compensation");
        // Set Humidity = 30% RH -> (50 - 30)/2 = +10% boost
        sw[14:13] = 2'b10; // Select Humidity
        sw[6:0]   = 7'd30; // Hum = 30%
        wait_cycles(1000);
        $display("    Temp = %d°C, Hum = %d%%, HumAdj = +%d%%, Composite Adaptive TH = %d%%",
                 dut.cur_temp, dut.cur_hum, dut.hum_adj, dut.adaptive_th);
        // Base 40 + Temp 10 + Hum 10 = 60%
        if (dut.adaptive_th == 7'd60 && dut.hum_adj == 5'd10) begin
            $display("    [PASS] Low humidity further boosted adaptive threshold to 60%%.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Humidity threshold compensation failed.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 5: Rain Sensor Lockout Precedence
        // --------------------------------------------------------------------
        $display("[*] TEST 5: Rain Sensor Lockout Precedence");
        // Even with dry soil (e.g. moisture 20%), rain must force pump OFF
        sw[14:13] = 2'b00; sw[9:0] = 10'd850; // Dry soil
        wait_cycles(2000);
        gpio_11 = 1'b1; // Rain detected!
        wait_cycles(1000);
        $display("    Rain Active = %b, Relay = %b, Lockout Flag = %b",
                 dut.eff_rain_detected, dut.GPIO_0, dut.rain_lockout);
        if (dut.GPIO_0 == 1'b0 && dut.rain_lockout == 1'b1) begin
            $display("    [PASS] Rain sensor immediately locked out pump.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Rain sensor did not override irrigation.");
            fail_count = fail_count + 1;
        end
        gpio_11 = 1'b0; // Clear rain
        wait_cycles(5000);

        // --------------------------------------------------------------------
        // TEST 6: Manual Override Prioritization
        // --------------------------------------------------------------------
        $display("[*] TEST 6: Manual Override Prioritization");
        sw[15] = 1'b1; // Assert manual override switch
        wait_cycles(2000);
        $display("    Manual Override Switch = 1 -> Relay = %b, PumpRunning = %b",
                 dut.GPIO_0, dut.pump_running);
        if (dut.GPIO_0 == 1'b1 && dut.pump_running == 1'b1) begin
            $display("    [PASS] Manual override forced pump ON.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Manual override failed to energize pump.");
            fail_count = fail_count + 1;
        end
        sw[15] = 1'b0; // Release manual override
        wait_cycles(2000);

        // --------------------------------------------------------------------
        // TEST 7: Threshold Crossing & Deadband Hold
        // --------------------------------------------------------------------
        $display("[*] TEST 7: Hysteresis Deadband Hold Behavior");
        // Set parameters back to normal: Temp 24°C, Hum 55% -> TH = 40% (Turn-On=35%, Turn-Off=45%)
        sw[14:13] = 2'b01; sw[6:0] = 7'd24;
        sw[14:13] = 2'b10; sw[6:0] = 7'd55;
        wait_cycles(2000);
        // Set soil moisture in deadband: 40% moisture (between 35% and 45%)
        // 40% moisture -> raw ADC ~ 700
        set_soil_adc(10'd700);
        wait_cycles(2000);
        $display("    Moisture = %d%% in Deadband [35%%, 45%%], Pump = %b",
                 dut.soil_moisture_pct, dut.pump_running);
        if (dut.pump_running == 1'b0) begin
            $display("    [PASS] Pump correctly remains OFF inside deadband when previously OFF.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Deadband violated.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 8: Hysteresis Anti-Chatter Protection
        // --------------------------------------------------------------------
        $display("[*] TEST 8: Anti-Chatter Hysteresis Verification");
        // Rapidly toggle moisture around boundary (36% <-> 34%)
        set_soil_adc(10'd730); wait_cycles(500); // 36%
        set_soil_adc(10'd745); wait_cycles(500); // 34% (starts pump)
        $display("    Started Pump at 34%% moisture: Pump = %b", dut.pump_running);
        set_soil_adc(10'd730); wait_cycles(500); // 36% (inside deadband, must NOT chatter off)
        $display("    Moisture rose to 36%% (Deadband): Pump = %b", dut.pump_running);
        if (dut.pump_running == 1'b1) begin
            $display("    [PASS] Anti-chatter hysteresis successfully prevented motor oscillation.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Chattering occurred inside deadband.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 9: Sensor Timeout & Disconnection Fault
        // --------------------------------------------------------------------
        $display("[*] TEST 9: Soil ADC Disconnection Fault Detection");
        // Inject soil ADC fault (open circuit raw = 1023)
        set_soil_adc(10'd1023);
        wait_cycles(2000);
        $display("    Soil Raw = %d -> Fault Flag = %b", dut.raw_soil_adc, dut.soil_adc_fault);
        if (dut.soil_adc_fault == 1'b1) begin
            $display("    [PASS] Open-circuit soil sensor fault detected.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Soil sensor fault not asserted.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 10: DHT11 Checksum Error Detection
        // --------------------------------------------------------------------
        $display("[*] TEST 10: DHT11 Checksum Error Detection");
        // Switch to synthetic mode with DHT fault injection
        sw[17]    = 1'b1;
        sw[14:13] = 2'b11;
        sw[0]     = 1'b1; // Inject DHT checksum error
        wait_cycles(2000);
        $display("    DHT Checksum Error Flag = %b", dut.u_dht11.checksum_error);
        if (dut.u_dht11.checksum_error == 1'b1) begin
            $display("    [PASS] DHT11 checksum failure correctly identified and flagged.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Checksum error flag not asserted.");
            fail_count = fail_count + 1;
        end
        sw[0] = 1'b0; // Clear fault
        wait_cycles(2000);

        // --------------------------------------------------------------------
        // TEST 11: Minimum ON Time Runtime Protection
        // --------------------------------------------------------------------
        $display("[*] TEST 11: Minimum ON Time Enforcement");
        sw[17]    = 1'b0; // Physical mode
        sw[14:13] = 2'b00;
        // Wait until pump FSM finishes any pending rest period and enters ST_OFF_READY
        while (dut.pump_fsm_state != 3'd0) wait_cycles(100);
        $display("    FSM ready in ST_OFF_READY (State = %d)", dut.pump_fsm_state);
        set_soil_adc(10'd850); // Trigger pump ON (moisture ~20%)
        wait_cycles(2000);
        $display("    Pump started: Pump = %b, State = %d (1=MIN_ON)", dut.pump_running, dut.pump_fsm_state);
        // Immediately make soil saturated (raw = 200)
        slave_soil_adc_val = 10'd200;
        wait_cycles(5000); // 5000 cycles is well before MIN_ON_SECONDS (20,000 cycles)
        $display("    Soil wet immediately, but inside Min ON window: Pump = %b, State = %d",
                 dut.pump_running, dut.pump_fsm_state);
        if (dut.pump_running == 1'b1 && dut.pump_fsm_state == 3'd1) begin
            $display("    [PASS] Minimum ON timer prevents premature shutoff.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Pump shut off prematurely before Min ON expired.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 12: Minimum OFF Rest Time Protection
        // --------------------------------------------------------------------
        $display("[*] TEST 12: Minimum OFF Rest Duration Enforcement");
        // Wait for Min ON to expire and pump to transition to ST_MIN_OFF_WAIT (state 3)
        while (dut.pump_fsm_state != 3'd3) wait_cycles(100);
        $display("    Pump entered rest period: Pump = %b, State = %d (3=MIN_OFF_WAIT)",
                 dut.pump_running, dut.pump_fsm_state);
        // Immediately make soil dry again (raw = 850)
        slave_soil_adc_val = 10'd850;
        wait_cycles(5000); // Inside MIN_OFF window (5,000 < 30,000 cycles)
        $display("    Soil dry again, but inside Min OFF rest period: Pump = %b, State = %d",
                 dut.pump_running, dut.pump_fsm_state);
        if (dut.pump_running == 1'b0 && dut.pump_fsm_state == 3'd3) begin
            $display("    [PASS] Minimum OFF timer prevents rapid motor restart.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Pump restarted before Min OFF period elapsed.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 13: Direct Digital LM393 DO Sensor Mode Verification
        // --------------------------------------------------------------------
        $display("[*] TEST 13: Direct Digital LM393 DO Sensor Mode Verification");
        // Enable Direct LM393 DO mode via sw[12]
        sw[12] = 1'b1;
        // Case A: DO = 1 (Dry soil -> 20% moisture)
        gpio_7 = 1'b1;
        wait_cycles(15000); // Allow sample interval (10,000 cycles) to update
        $display("    Direct DO=1 (Dry): Moisture = %d%%, LEDR[12] = %b",
                 dut.soil_moisture_pct, dut.LEDR[12]);
        if (dut.soil_moisture_pct == 7'd20 && dut.LEDR[12] == 1'b1) begin
            $display("    [PASS] Direct LM393 DO dry state correctly latched 20%% moisture.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Direct LM393 DO dry state failed.");
            fail_count = fail_count + 1;
        end

        // Case B: DO = 0 (Wet soil -> 65% moisture)
        gpio_7 = 1'b0;
        wait_cycles(15000); // Allow sample interval to update
        $display("    Direct DO=0 (Wet): Moisture = %d%%", dut.soil_moisture_pct);
        if (dut.soil_moisture_pct >= 7'd60) begin
            $display("    [PASS] Direct LM393 DO wet state correctly latched moist level.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Direct LM393 DO wet state failed.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("======================================================================");
        $display(" TEST RESULTS SUMMARY: PASS = %0d, FAIL = %0d", pass_count, fail_count);
        $display("======================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL PROJECT 3 TEST SCENARIOS PASSED SUCCESSFULLY! <<<");
            $finish;
        end else begin
            $display(">>> SOME PROJECT 3 TESTS FAILED! Inspect logs above. <<<");
            $stop;
        end
    end

endmodule
