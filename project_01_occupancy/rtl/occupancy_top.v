//=============================================================================
// Module: occupancy_top
// Project: Project 1 / Basic #3 — IR-Based Occupancy / Entry-Exit Counter
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Direct hardware implementation of Basic #3:
//              - 2x Optical IR obstacle / break-beam sensors on GPIO_PIR_IN[1:0]
//              - 20ms hardware debounce filtering
//              - Direction detection FSM (1.0s timeout, entry vs exit)
//              - Saturating Up/Down counter (00 to 99, never goes below 0)
//              - HEX0 & HEX1 dual-digit BCD 7-segment display
//              - Status logic (EMPTY vs OCCUPIED)
//              - HD44780 16x2 Character LCD driver
//              - LEDG trigger indicators (raw active, entry pulse, exit pulse)
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module occupancy_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer SIMULATION  = 0
)(
    // Clocks and Resets
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0] = Reset count (active low)
    // Slide Switches
    input  wire [17:0] SW,              // SW[0]=Sim A, SW[1]=Sim B, SW[5]=Active-Low Invert
    // External GPIO JP5 inputs
    input  wire [3:0]  GPIO_PIR_IN,     // [0] = IR_A (Outer), [1] = IR_B (Inner)
    // Actuator Outputs
    output wire        RELAY_LIGHTS,    // JP5 Pin 6 (Active when occupied)
    output wire        RELAY_HVAC,      // JP5 Pin 7
    output wire        RELAY_FANS,      // JP5 Pin 8
    // LEDs
    output wire [17:0] LEDR,            // Raw Motion / Status
    output wire [8:0]  LEDG,            // [0]=IR_A, [1]=IR_B, [2]=Entry, [3]=Exit, [4]=Occupied
    // 7-Segment Displays (Active-Low)
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    // 16x2 HD44780 LCD
    inout  wire [7:0]  LCD_DATA,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    // RS-232 UART
    output wire        UART_TXD
);

    // 1. Reset Synchronizer (KEY[0] is active-low master reset)
    wire rst;
    reset_synchronizer #(
        .STAGES(2),
        .ACTIVE_LOW_IN(1),
        .ACTIVE_LOW_OUT(0)
    ) u_rst_sync (
        .clk(CLOCK_50),
        .async_rst_in(KEY[0]),
        .sync_rst_out(rst)
    );

    // 2. IR Sensor Input Selection & Polarity Normalization
    // Standard IR obstacle sensors pull LOW when obstacle/beam is broken.
    // Default active-low (SW[5]=0: Active-Low, SW[5]=1: Active-High)
    wire ir_raw_a = (SW[5]) ? GPIO_PIR_IN[0] : ~GPIO_PIR_IN[0];
    wire ir_raw_b = (SW[5]) ? GPIO_PIR_IN[1] : ~GPIO_PIR_IN[1];

    // Combine with manual slide switches for bench simulation (SW[0] and SW[1])
    wire eff_ir_a = ir_raw_a | SW[0];
    wire eff_ir_b = ir_raw_b | SW[1];

    // 3. Debounce Modules (for IR_A and IR_B)
    wire debounced_ir_a;
    wire debounced_ir_b;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(0) // Already normalized to active-high
    ) u_db_a (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(eff_ir_a),
        .debounced_state(debounced_ir_a),
        .pressed_pulse(),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(0)
    ) u_db_b (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(eff_ir_b),
        .debounced_state(debounced_ir_b),
        .pressed_pulse(),
        .released_pulse()
    );

    // 4. Direction Detection FSM
    wire entry_pulse;
    wire exit_pulse;

    ir_direction_fsm #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .TIMEOUT_MS(SIMULATION ? 10 : 1000),
        .SIMULATION(SIMULATION)
    ) u_dir_fsm (
        .clk(CLOCK_50),
        .rst_n(!rst),
        .ir_a_active(debounced_ir_a),
        .ir_b_active(debounced_ir_b),
        .entry_pulse(entry_pulse),
        .exit_pulse(exit_pulse),
        .state_out()
    );

    // 5. Saturating Up/Down Occupancy Counter (0 to 99)
    reg [7:0] occupancy_count;

    always @(posedge CLOCK_50 or posedge rst) begin
        if (rst) begin
            occupancy_count <= 8'd0;
        end else begin
            if (entry_pulse && !exit_pulse) begin
                if (occupancy_count < 8'd99)
                    occupancy_count <= occupancy_count + 1'b1;
            end else if (exit_pulse && !entry_pulse) begin
                if (occupancy_count > 8'd0)
                    occupancy_count <= occupancy_count - 1'b1;
                // Saturates at 0: never wraps to negative/255
            end
        end
    end

    // 6. Binary to BCD Conversion for 7-Segment Readout
    wire [3:0] bcd_tens = occupancy_count / 10;
    wire [3:0] bcd_ones = occupancy_count % 10;

    seven_seg_dec u_seg_ones (
        .dec_digit(bcd_ones),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX0)
    );

    seven_seg_dec u_seg_tens (
        .dec_digit(bcd_tens),
        .blank(1'b0),
        .show_dash(1'b0),
        .seg_out(HEX1)
    );

    // Blank unused 7-segment displays (Active-Low: 7'b111_1111)
    assign HEX2 = 7'b111_1111;
    assign HEX3 = 7'b111_1111;
    assign HEX4 = 7'b111_1111;
    assign HEX5 = 7'b111_1111;
    assign HEX6 = 7'b111_1111;
    assign HEX7 = 7'b111_1111;

    // 7. Pulse Stretchers for Event LEDs (~300ms)
    localparam integer STRETCH_CYCLES = (SIMULATION) ? 500 : (CLK_FREQ_HZ / 3);
    reg [$clog2(STRETCH_CYCLES):0] entry_stretch_cnt, exit_stretch_cnt;

    always @(posedge CLOCK_50 or posedge rst) begin
        if (rst) begin
            entry_stretch_cnt <= 0;
            exit_stretch_cnt  <= 0;
        end else begin
            if (entry_pulse) entry_stretch_cnt <= STRETCH_CYCLES;
            else if (entry_stretch_cnt > 0) entry_stretch_cnt <= entry_stretch_cnt - 1'b1;

            if (exit_pulse) exit_stretch_cnt <= STRETCH_CYCLES;
            else if (exit_stretch_cnt > 0) exit_stretch_cnt <= exit_stretch_cnt - 1'b1;
        end
    end

    wire is_occupied = (occupancy_count > 8'd0);

    assign LEDG[0]   = debounced_ir_a;
    assign LEDG[1]   = debounced_ir_b;
    assign LEDG[2]   = (entry_stretch_cnt > 0);
    assign LEDG[3]   = (exit_stretch_cnt > 0);
    assign LEDG[4]   = is_occupied;
    assign LEDG[8:5] = 4'b0000;

    assign LEDR[0]    = debounced_ir_a;
    assign LEDR[1]    = debounced_ir_b;
    assign LEDR[17:2] = 16'd0;

    assign RELAY_LIGHTS = is_occupied;
    assign RELAY_HVAC   = is_occupied;
    assign RELAY_FANS   = is_occupied;

    // 8. Status Logic & 16x2 HD44780 Character LCD
    wire [7:0] ascii_tens = 8'h30 + bcd_tens;
    wire [7:0] ascii_ones = 8'h30 + bcd_ones;

    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;

    always @(*) begin
        // Line 1: "Zone Status:    "
        lcd_line1 = "Zone Status:    ";

        // Line 2: "EMPTY           " vs "OCCUPIED (XX)   "
        if (!is_occupied) begin
            lcd_line2 = "EMPTY           ";
        end else begin
            lcd_line2 = {"OCCUPIED (", ascii_tens, ascii_ones, ")   "};
        end
    end

    lcd_hd44780_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_lcd (
        .clk(CLOCK_50),
        .rst(rst),
        .line1_text(lcd_line1),
        .line2_text(lcd_line2),
        .refresh_strobe(1'b0),
        .busy(),
        .lcd_data(LCD_DATA),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_rs(LCD_RS),
        .lcd_on(LCD_ON),
        .lcd_blon(LCD_BLON)
    );

    // 9. UART Telemetry (Idle High)
    assign UART_TXD = 1'b1;

endmodule
