//=============================================================================
// Module: lcd_hd44780_controller
// Description: Complete hardware controller for the DE2-115 on-board 16x2
//              HD44780 LCD. Handles power-on reset timing, 8-bit mode initialization,
//              and accepts streaming character writes or screen-buffer updates.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module lcd_hd44780_controller #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst,
    // High-level text buffer interface (16 chars for Line 1, 16 chars for Line 2)
    input  wire [127:0] line1_text,     // 16 ASCII characters (Line 1, char 0 = MSB)
    input  wire [127:0] line2_text,     // 16 ASCII characters (Line 2, char 0 = MSB)
    input  wire         refresh_strobe, // Pulse high to force a full display update
    output reg          busy,           // High while updating or initializing
    // Physical HD44780 LCD Pins on DE2-115
    output reg  [7:0]   lcd_data,
    output reg          lcd_rw,         // 0 = Write, 1 = Read
    output reg          lcd_en,         // Strobe enable
    output reg          lcd_rs,         // 0 = Command, 1 = Data
    output wire         lcd_on,         // Power control (always 1)
    output wire         lcd_blon        // Backlight control (always 1)
);

    assign lcd_on   = 1'b1;
    assign lcd_blon = 1'b1;

    // Microsecond tick generator (50 cycles of 50 MHz = 1 us)
    localparam integer CYCLES_1US = CLK_FREQ_HZ / 1_000_000;
    reg [$clog2(CYCLES_1US)-1:0] us_cnt;
    reg tick_1us;

    always @(posedge clk) begin
        if (rst) begin
            us_cnt   <= 0;
            tick_1us <= 1'b0;
        end else begin
            if (us_cnt >= CYCLES_1US - 1) begin
                us_cnt   <= 0;
                tick_1us <= 1'b1;
            end else begin
                us_cnt   <= us_cnt + 1'b1;
                tick_1us <= 1'b0;
            end
        end
    end

    // High-level state machine
    localparam [4:0]
        S_POWERON_WAIT = 5'd0,
        S_INIT_FUNC_1  = 5'd1,
        S_INIT_FUNC_2  = 5'd2,
        S_INIT_FUNC_3  = 5'd3,
        S_INIT_CONFIG  = 5'd4,
        S_INIT_DISPON  = 5'd5,
        S_INIT_CLEAR   = 5'd6,
        S_INIT_ENTRY   = 5'd7,
        S_IDLE         = 5'd8,
        S_SET_LINE1    = 5'd9,
        S_WRITE_LINE1  = 5'd10,
        S_SET_LINE2    = 5'd11,
        S_WRITE_LINE2  = 5'd12,
        S_EXEC_CYCLE   = 5'd13,
        S_DELAY_CYCLE  = 5'd14;

    reg [4:0] state, return_state;
    reg [19:0] delay_us;
    reg [3:0] char_idx;

    // Sub-strobe generator for LCD_EN (Setup -> Strobe High -> Hold -> Low)
    reg [2:0] exec_step;
    reg [7:0] cmd_byte;
    reg       cmd_rs;

    reg [127:0] prev_line1, prev_line2;
    reg [19:0]  auto_refresh_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state            <= S_POWERON_WAIT;
            return_state     <= S_IDLE;
            busy             <= 1'b1;
            lcd_rw           <= 1'b0;
            lcd_en           <= 1'b0;
            lcd_rs           <= 1'b0;
            lcd_data         <= 8'h00;
            delay_us         <= 20'd50_000; // 50 ms power-on delay
            char_idx         <= 4'd0;
            exec_step        <= 3'd0;
            cmd_byte         <= 8'h00;
            cmd_rs           <= 1'b0;
            prev_line1       <= 128'd0;
            prev_line2       <= 128'd0;
            auto_refresh_cnt <= 20'd0;
        end else if (tick_1us) begin
            case (state)
                S_POWERON_WAIT: begin
                    busy <= 1'b1;
                    if (delay_us == 0) begin
                        // Function Set 8-bit mode (0x38)
                        cmd_byte     <= 8'h38;
                        cmd_rs       <= 1'b0;
                        delay_us     <= 20'd5_000; // 5 ms wait
                        return_state <= S_INIT_FUNC_2;
                        state        <= S_EXEC_CYCLE;
                    end else begin
                        delay_us <= delay_us - 1'b1;
                    end
                end

                S_INIT_FUNC_2: begin
                    cmd_byte     <= 8'h38;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd150; // 150 us wait
                    return_state <= S_INIT_FUNC_3;
                    state        <= S_EXEC_CYCLE;
                end

                S_INIT_FUNC_3: begin
                    cmd_byte     <= 8'h38;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    return_state <= S_INIT_CONFIG;
                    state        <= S_EXEC_CYCLE;
                end

                S_INIT_CONFIG: begin
                    // Function set: 2-line, 5x8 font (0x38)
                    cmd_byte     <= 8'h38;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    return_state <= S_INIT_DISPON;
                    state        <= S_EXEC_CYCLE;
                end

                S_INIT_DISPON: begin
                    // Display ON, Cursor OFF, Blink OFF (0x0C)
                    cmd_byte     <= 8'h0C;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    return_state <= S_INIT_CLEAR;
                    state        <= S_EXEC_CYCLE;
                end

                S_INIT_CLEAR: begin
                    // Clear display (0x01)
                    cmd_byte     <= 8'h01;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd2_000; // 2 ms delay required for clear
                    return_state <= S_INIT_ENTRY;
                    state        <= S_EXEC_CYCLE;
                end

                S_INIT_ENTRY: begin
                    // Entry mode: auto-increment, no shift (0x06)
                    cmd_byte     <= 8'h06;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    // Immediately transition to writing lines as soon as init completes!
                    return_state <= S_SET_LINE1;
                    state        <= S_EXEC_CYCLE;
                end

                S_IDLE: begin
                    busy <= 1'b0;
                    // Auto-refresh when text changes, on external strobe, or periodically every 50ms
                    if (refresh_strobe || (line1_text != prev_line1) || (line2_text != prev_line2) || (auto_refresh_cnt >= 20'd50_000)) begin
                        busy             <= 1'b1;
                        char_idx         <= 4'd0;
                        prev_line1       <= line1_text;
                        prev_line2       <= line2_text;
                        auto_refresh_cnt <= 20'd0;
                        state            <= S_SET_LINE1;
                    end else begin
                        auto_refresh_cnt <= auto_refresh_cnt + 1'b1;
                    end
                end

                S_SET_LINE1: begin
                    // Set DDRAM address to 0x00 (Line 1 column 0: 0x80)
                    cmd_byte     <= 8'h80;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    return_state <= S_WRITE_LINE1;
                    state        <= S_EXEC_CYCLE;
                end

                S_WRITE_LINE1: begin
                    // Write ASCII character from line1_text
                    cmd_byte     <= line1_text[(15 - char_idx)*8 +: 8];
                    cmd_rs       <= 1'b1; // Data mode
                    delay_us     <= 20'd50;
                    if (char_idx == 4'd15) begin
                        char_idx     <= 4'd0;
                        return_state <= S_SET_LINE2;
                    end else begin
                        char_idx     <= char_idx + 1'b1;
                        return_state <= S_WRITE_LINE1;
                    end
                    state <= S_EXEC_CYCLE;
                end

                S_SET_LINE2: begin
                    // Set DDRAM address to 0x40 (Line 2 column 0: 0xC0)
                    cmd_byte     <= 8'hC0;
                    cmd_rs       <= 1'b0;
                    delay_us     <= 20'd50;
                    return_state <= S_WRITE_LINE2;
                    state        <= S_EXEC_CYCLE;
                end

                S_WRITE_LINE2: begin
                    // Write ASCII character from line2_text
                    cmd_byte     <= line2_text[(15 - char_idx)*8 +: 8];
                    cmd_rs       <= 1'b1; // Data mode
                    delay_us     <= 20'd50;
                    if (char_idx == 4'd15) begin
                        char_idx     <= 4'd0;
                        return_state <= S_IDLE;
                    end else begin
                        char_idx     <= char_idx + 1'b1;
                        return_state <= S_WRITE_LINE2;
                    end
                    state <= S_EXEC_CYCLE;
                end

                // Strobe execution cycle (meets setup, pulse width > 450ns, hold > 10ns)
                S_EXEC_CYCLE: begin
                    case (exec_step)
                        3'd0: begin
                            lcd_rs   <= cmd_rs;
                            lcd_rw   <= 1'b0;
                            lcd_data <= cmd_byte;
                            exec_step <= 3'd1;
                        end
                        3'd1: begin
                            lcd_en   <= 1'b1; // Strobe high
                            exec_step <= 3'd2;
                        end
                        3'd2: begin
                            lcd_en   <= 1'b1; // Hold high (>450ns)
                            exec_step <= 3'd3;
                        end
                        3'd3: begin
                            lcd_en   <= 1'b0; // Strobe low
                            exec_step <= 3'd0;
                            state    <= S_DELAY_CYCLE;
                        end
                    endcase
                end

                S_DELAY_CYCLE: begin
                    if (delay_us == 0) begin
                        state <= return_state;
                    end else begin
                        delay_us <= delay_us - 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
