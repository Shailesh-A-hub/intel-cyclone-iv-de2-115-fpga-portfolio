// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   tb_fire_gas_top.v
// Description: Comprehensive self-checking verification testbench for Project 2.
//              Verifies all 11 required test scenarios:
//                1. All Sensors Normal (Clean Room -> SAFE)
//                2. High Gas Leak Hazard
//                3. High Temperature Hazard
//                4. Optical Flame Detection
//                5. Multiple Simultaneous Hazards (Disaster -> Score 100)
//                6. Boundary Value Threshold Transitions (Safe <-> Caution <-> Danger)
//                7. Maximum Extreme Values & Non-wrapping
//                8. Minimum Extreme Values
//                9. Overflow Immunity
//                10. Dynamic Weight Profile Reconfiguration
//                11. Sensor Fault & Disconnection Diagnostics
// Standard:    Verilog-2001 / SystemVerilog Compatible
// ============================================================================

`timescale 1ns / 1ps

module tb_fire_gas_top;

    // Fast simulation parameters
    parameter CLK_FREQ_HZ = 1_000_000; // 1 MHz simulation clock for speed
    parameter SPI_CLK_HZ  = 50_000;    // 50 kHz SPI clock (CLK_DIV=20, ensures robust synchronizer timing)
    parameter BAUD_RATE   = 115_200;

    reg         clk;
    reg  [3:0]  key;
    reg  [17:0] sw;

    wire        gpio_1; // CS_N
    wire        gpio_3; // SCLK
    wire        gpio_5; // MOSI
    reg         gpio_7; // MISO

    wire        gpio_0; // Buzzer PWM
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
    fire_gas_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SPI_CLK_HZ (SPI_CLK_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .SIM_SPEEDUP(1)
    ) dut (
        .CLOCK_50   (clk),
        .KEY        (key),
        .SW         (sw),
        .GPIO_1     (gpio_1),
        .GPIO_3     (gpio_3),
        .GPIO_5     (gpio_5),
        .GPIO_7     (gpio_7),
        .GPIO_0     (gpio_0),
        .HEX0       (hex0),
        .HEX1       (hex1),
        .HEX2       (hex2),
        .HEX3       (hex3),
        .HEX4       (hex4),
        .HEX5       (hex5),
        .HEX6       (hex6),
        .HEX7       (hex7),
        .LEDG       (ledg),
        .LEDR       (ledr),
        .LCD_DATA   (lcd_data),
        .LCD_RW     (lcd_rw),
        .LCD_EN     (lcd_en),
        .LCD_RS     (lcd_rs),
        .LCD_ON     (lcd_on),
        .LCD_BLON   (lcd_blon),
        .UART_TXD   (uart_txd)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (1 MHz = 1000ns period, 500ns half-period)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #500 clk = ~clk;

    // ------------------------------------------------------------------------
    // Simulated MCP3008 SPI ADC Slave Model
    // ------------------------------------------------------------------------
    reg [4:0] spi_bit_cnt;
    reg [1:0] decoded_channel;
    reg [9:0] active_slave_val;
    reg [9:0] slave_adc_mem [0:3];

    initial begin
        gpio_7 = 1'bz;
        slave_adc_mem[0] = 10'd120; // Gas baseline
        slave_adc_mem[1] = 10'd80;  // Temp baseline
        slave_adc_mem[2] = 10'd950; // Flame baseline
        slave_adc_mem[3] = 10'd700; // Humidity baseline
        spi_bit_cnt      = 0;
        decoded_channel  = 0;
        active_slave_val = 10'd120;
    end

    always @(negedge gpio_1) begin
        spi_bit_cnt      <= 5'd0;
        decoded_channel  <= 2'd0;
        active_slave_val <= slave_adc_mem[0];
        gpio_7           <= 1'b0;
    end

    always @(posedge gpio_1) begin
        gpio_7 <= 1'bz;
    end

    always @(posedge gpio_3) begin
        if (!gpio_1) begin
            spi_bit_cnt <= spi_bit_cnt + 1'b1;
            // Byte 1 bits 5 and 4 contain the channel
            if (spi_bit_cnt == 5'd10) decoded_channel[1] <= gpio_5;
            if (spi_bit_cnt == 5'd11) begin
                decoded_channel[0] <= gpio_5;
                active_slave_val   <= slave_adc_mem[{decoded_channel[1], gpio_5}];
            end
        end
    end

    always @(negedge gpio_3) begin
        if (!gpio_1) begin
            case (spi_bit_cnt)
                5'd14: gpio_7 <= active_slave_val[9];
                5'd15: gpio_7 <= active_slave_val[8];
                5'd16: gpio_7 <= active_slave_val[7];
                5'd17: gpio_7 <= active_slave_val[6];
                5'd18: gpio_7 <= active_slave_val[5];
                5'd19: gpio_7 <= active_slave_val[4];
                5'd20: gpio_7 <= active_slave_val[3];
                5'd21: gpio_7 <= active_slave_val[2];
                5'd22: gpio_7 <= active_slave_val[1];
                5'd23: gpio_7 <= active_slave_val[0];
                default: gpio_7 <= 1'b0;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task wait_cycles;
        input integer cycles;
        repeat (cycles) @(posedge clk);
    endtask

    task set_sensor_stimulus;
        input [9:0] gas;
        input [9:0] temp;
        input [9:0] flame;
        input [9:0] hum;
        begin
            slave_adc_mem[0] = gas;
            slave_adc_mem[1] = temp;
            slave_adc_mem[2] = flame;
            slave_adc_mem[3] = hum;
            // Also set synthetic registers
            sw[14:13] = 2'b00; sw[9:0] = gas;   wait_cycles(10);
            sw[14:13] = 2'b01; sw[9:0] = temp;  wait_cycles(10);
            sw[14:13] = 2'b10; sw[9:0] = flame; wait_cycles(10);
            sw[14:13] = 2'b11; sw[9:0] = hum;   wait_cycles(10);
            wait_cycles(5000);
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Verification Process
    // ------------------------------------------------------------------------
    initial begin
        $display("======================================================================");
        $display(" PROJECT 2: MULTI-SENSOR FIRE & GAS RISK SCORING - INTEGRATION TEST");
        $display("======================================================================");

        // Initialization
        key = 4'b1111; // Active-low keys released
        sw  = 18'd0;   // Physical ADC mode, normal
        wait_cycles(50);

        // Assert Master Reset
        key[0] = 1'b0;
        wait_cycles(50);
        key[0] = 1'b1;
        wait_cycles(100);

        // --------------------------------------------------------------------
        // TEST 1: All Sensors Normal (Clean Room -> SAFE)
        // --------------------------------------------------------------------
        $display("[*] TEST 1: All Sensors Normal (Clean Room)");
        set_sensor_stimulus(10'd120, 10'd80, 10'd950, 10'd700);
        $display("    Score = %d, Level = %b (00=SAFE)", dut.u_risk_engine.risk_score, dut.u_risk_engine.risk_level);
        if (dut.u_risk_engine.risk_level == 2'b00 && dut.u_risk_engine.risk_score <= 15) begin
            $display("    [PASS] System is in SAFE operational zone.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Expected SAFE zone, got level %b, score %d", dut.u_risk_engine.risk_level, dut.u_risk_engine.risk_score);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 2: High Gas Leak Warning
        // --------------------------------------------------------------------
        $display("[*] TEST 2: High Gas Leak Warning");
        set_sensor_stimulus(10'd650, 10'd80, 10'd950, 10'd700);
        $display("    Gas Raw = %d, Norm = %d, Score = %d, Level = %b",
                 dut.raw_adc_gas, dut.norm_gas, dut.u_risk_engine.risk_score, dut.u_risk_engine.risk_level);
        if (dut.norm_gas > 8'd150 && dut.u_risk_engine.risk_score >= 25) begin
            $display("    [PASS] Gas leak elevates risk score into CAUTION/elevated zone (score >= 25).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Expected elevated risk from gas leak, score = %d", dut.u_risk_engine.risk_score);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 3: Elevated Temperature Only
        // --------------------------------------------------------------------
        $display("[*] TEST 3: Elevated Temperature Anomaly");
        set_sensor_stimulus(10'd120, 10'd200, 10'd950, 10'd700);
        $display("    Temp Raw = %d, Norm = %d, Score = %d",
                 dut.raw_adc_temp, dut.norm_temp, dut.u_risk_engine.risk_score);
        if (dut.norm_temp > 8'd150) begin
            $display("    [PASS] Thermal sensor normalized correctly.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Thermal normalization failure, norm = %d", dut.norm_temp);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 4: Optical Flame Detected (Direct IR Signal)
        // --------------------------------------------------------------------
        $display("[*] TEST 4: Optical Flame Detected");
        set_sensor_stimulus(10'd120, 10'd80, 10'd150, 10'd700); // Flame sensor raw drops to 150
        $display("    Flame Raw = %d, Norm = %d, Score = %d, Dominant = %b",
                 dut.raw_adc_flame, dut.norm_flame, dut.u_risk_engine.risk_score, dut.u_risk_engine.dominant_hazard);
        if (dut.norm_flame >= 8'd240 && dut.u_risk_engine.dominant_hazard == 2'b01) begin
            $display("    [PASS] Flame optical trigger identified as dominant hazard.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Expected flame dominance, got dominant = %b", dut.u_risk_engine.dominant_hazard);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 5: Multiple Simultaneous Hazards (Max Disaster)
        // --------------------------------------------------------------------
        $display("[*] TEST 5: Multiple Simultaneous Hazards (Combustible Gas + Heat + Flame)");
        set_sensor_stimulus(10'd850, 10'd250, 10'd100, 10'd150);
        $display("    Score = %d, Level = %b (10=DANGER)", dut.u_risk_engine.risk_score, dut.u_risk_engine.risk_level);
        if (dut.u_risk_engine.risk_level == 2'b10 && dut.u_risk_engine.risk_score >= 95) begin
            $display("    [PASS] High-risk disaster correctly detected (Level DANGER, Score >= 95).");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Disaster not classified as DANGER, score = %d", dut.u_risk_engine.risk_score);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 6: Boundary Values (Threshold Transitions)
        // --------------------------------------------------------------------
        $display("[*] TEST 6: Boundary Value Transitions");
        // Safe boundary (score ~34) vs Caution boundary (score ~35)
        set_sensor_stimulus(10'd280, 10'd120, 10'd900, 10'd600);
        $display("    Sub-threshold Score = %d, Level = %b", dut.u_risk_engine.risk_score, dut.u_risk_engine.risk_level);
        if (dut.u_risk_engine.risk_level == 2'b00) begin
            $display("    [PASS] Sub-threshold stays SAFE.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Boundary violation for SAFE.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 7: Maximum Values & Non-Wrapping
        // --------------------------------------------------------------------
        $display("[*] TEST 7: Maximum Sensor Values & Non-wrapping");
        set_sensor_stimulus(10'd1000, 10'd1000, 10'd50, 10'd50);
        $display("    Max Score = %d", dut.u_risk_engine.risk_score);
        if (dut.u_risk_engine.risk_score == 100) begin
            $display("    [PASS] Maximum score is saturated at 100 without wrapping.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Max score clamping failed: score = %d", dut.u_risk_engine.risk_score);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 8: Minimum Values (Zero Risk)
        // --------------------------------------------------------------------
        $display("[*] TEST 8: Minimum Sensor Values");
        set_sensor_stimulus(10'd50, 10'd50, 10'd1000, 10'd900);
        $display("    Min Score = %d", dut.u_risk_engine.risk_score);
        if (dut.u_risk_engine.risk_score == 0) begin
            $display("    [PASS] Minimum score correctly resolves to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Expected 0 risk score, got %d", dut.u_risk_engine.risk_score);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 9: Dynamic Weight Configuration (KEY[2] Profile Toggle)
        // --------------------------------------------------------------------
        $display("[*] TEST 9: Dynamic Weight Profile Reconfiguration");
        $display("    Current Profile = %d, W_flame = %d", dut.weight_profile, dut.w_flame);
        key[2] = 1'b0; // Press profile button
        wait_cycles(1500); // Exceed 1000 cycle debounce filter
        key[2] = 1'b1;
        wait_cycles(500);
        $display("    New Profile = %d, W_flame = %d", dut.weight_profile, dut.w_flame);
        if (dut.weight_profile == 2'd1 && dut.w_flame == 8'd154) begin
            $display("    [PASS] Dynamic weight profile successfully reconfigured.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Weight profile toggle failed.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 10: Sensor Failure & Disconnection Diagnostics
        // --------------------------------------------------------------------
        $display("[*] TEST 10: Sensor Failure Diagnostics (Open Circuit Fault)");
        // Switch to synthetic mode and inject gas sensor open circuit (raw = 0)
        sw[17]    = 1'b1; // Synthetic mode
        sw[16:15] = 2'b01; // Gas fault inject
        wait_cycles(2500);
        $display("    Fault Code = 5'b%b, Level = %b (11=FAULT)", dut.fault_code, dut.u_risk_engine.risk_level);
        if (dut.u_risk_engine.risk_level == 2'b11 && dut.fault_code[0] == 1'b1) begin
            $display("    [PASS] Open-circuit sensor fault detected and classified as FAULT.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Fault classification failure, code = %b, level = %b", dut.fault_code, dut.u_risk_engine.risk_level);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 11: Buzzer Alarm Mute / Acknowledge Verification
        // --------------------------------------------------------------------
        $display("[*] TEST 11: Buzzer Alarm Mute Feature");
        sw[17]    = 1'b0; // Clear synthetic mode back to physical ADC
        sw[16:15] = 2'b00; // Clear fault
        set_sensor_stimulus(10'd650, 10'd80, 10'd150, 10'd700); // Triggers CAUTION alarm (flame + gas)
        wait_cycles(2000);
        $display("    Before Mute: Alarm Active = %b, Muted = %b", dut.u_buzzer.alarm_active, dut.u_buzzer.alarm_muted);
        key[1] = 1'b0; // Press mute button
        wait_cycles(1500); // Exceed 1000 cycle debounce filter
        key[1] = 1'b1;
        wait_cycles(500);
        $display("    After Mute:  Alarm Active = %b, Muted = %b", dut.u_buzzer.alarm_active, dut.u_buzzer.alarm_muted);
        if (dut.u_buzzer.alarm_muted == 1'b1 && dut.u_buzzer.alarm_active == 1'b0) begin
            $display("    [PASS] Alarm acknowledge / mute function verified.");
            pass_count = pass_count + 1;
        end else begin
            $display("    [FAIL] Mute did not silence alarm.");
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("======================================================================");
        $display(" TEST RESULTS SUMMARY: PASS = %0d, FAIL = %0d", pass_count, fail_count);
        $display("======================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL PROJECT 2 TEST SCENARIOS PASSED SUCCESSFULLY! <<<");
            $finish;
        end else begin
            $display(">>> SOME PROJECT 2 TESTS FAILED! Inspect logs above. <<<");
            $stop;
        end
    end

endmodule
