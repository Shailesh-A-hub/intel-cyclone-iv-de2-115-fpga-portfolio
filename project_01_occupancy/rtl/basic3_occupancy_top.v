//=============================================================================
// Module: basic3_occupancy_top
// Project: Project 1 / Basic #3 — IR-Based Occupancy / Entry-Exit Counter
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Direct hardware implementation of Basic #3:
//              - 2x Optical IR obstacle / break-beam sensors on GPIO_0[0] & [1]
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

module basic3_occupancy_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer ACTIVE_LOW  = 1,          // 1 = IR sensor pulls low on beam break
    parameter integer SIMULATION  = 0
)(
    // System Clock and Master Reset
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0] = Reset count (active low)

    // External IR Sensor Inputs (e.g. JP5 / GPIO_0[1:0])
    input  wire [1:0]  GPIO_0,          // [0] = IR_A (Outer), [1] = IR_B (Inner)

    // 7-Segment Displays (Active-Low)
    output wire [6:0]  HEX0,            // Units digit
    output wire [6:0]  HEX1,            // Tens digit

    // Green LEDs
    output wire [3:0]  LEDG,            // [0]=IR_A, [1]=IR_B, [2]=Entry, [3]=Exit

    // HD44780 16x2 Character LCD
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_EN,
    output wire        LCD_RW,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    // 1. Synchronized Active-High Reset (rst = 1 when KEY[0] is pressed)
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

    // 2. Debounce Modules (for IR_A and IR_B)
    wire debounced_ir_a;
    wire debounced_ir_b;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW)
    ) u_db_a (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(GPIO_0[0]),
        .debounced_state(debounced_ir_a),
        .pressed_pulse(),
        .released_pulse()
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(SIMULATION ? 1 : 20),
        .ACTIVE_LOW_IN(ACTIVE_LOW)
    ) u_db_b (
        .clk(CLOCK_50),
        .rst(rst),
        .btn_in(GPIO_0[1]),
        .debounced_state(debounced_ir_b),
        .pressed_pulse(),
        .released_pulse()
    );

    // 3. Direction Detection FSM
    wire entry_pulse;
    wire exit_pulse;

    ir_direction_fsm #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .TIMEOUT_MS(1000),
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

    // 4. Saturating Up/Down Occupancy Counter (0 to 99)
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

    // 5. Binary to BCD Conversion for 7-Segment Readout
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

    // 6. Pulse Stretchers for Event LEDs (~300ms)
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

    assign LEDG[0] = debounced_ir_a;
    assign LEDG[1] = debounced_ir_b;
    assign LEDG[2] = (entry_stretch_cnt > 0);
    assign LEDG[3] = (exit_stretch_cnt > 0);

    // 7. Status Logic & 16x2 HD44780 Character LCD
    wire is_empty = (occupancy_count == 8'd0);
    wire [7:0] ascii_tens = 8'h30 + bcd_tens;
    wire [7:0] ascii_ones = 8'h30 + bcd_ones;

    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;

    always @(*) begin
        // Line 1: "Zone Status:    "
        lcd_line1 = "Zone Status:    ";

        // Line 2: "EMPTY           " vs "OCCUPIED (XX)   "
        if (is_empty) begin
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

endmodule
