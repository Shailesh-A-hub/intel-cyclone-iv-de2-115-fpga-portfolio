// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 3: Smart Adaptive Irrigation System
// File Name:   irrigation_uart_logger.v
// Description: Real-time ASCII telemetry string packetizer and UART transmitter.
//              Outputs live telemetry packets at 115200 baud:
//              "[IRRIG] SOIL:xx% (TH:xx%) | T:xxC H:xx% | PUMP:ON  | RAIN:0 CYC:xxx\r\n"
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module irrigation_uart_logger #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 115_200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Trigger Pulse
    input  wire        trigger_tx,

    // Telemetry Payload
    input  wire [6:0]  soil_moist_pct,
    input  wire [6:0]  adaptive_th_pct,
    input  wire [6:0]  temp_c,
    input  wire [6:0]  hum_pct,
    input  wire        pump_on,
    input  wire        rain_active,
    input  wire [15:0] cycle_count,

    // UART Physical Output
    output wire        uart_txd,
    output reg         tx_busy
);

    // ------------------------------------------------------------------------
    // UART Transmitter Instance
    // ------------------------------------------------------------------------
    reg        uart_start;
    reg  [7:0] uart_tx_byte;
    wire       uart_done;
    wire       uart_tx_busy;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .DATA_BITS  (8),
        .STOP_BITS  (1)
    ) u_tx (
        .clk        (clk),
        .rst        (~rst_n),
        .tx_data    (uart_tx_byte),
        .tx_start   (uart_start),
        .tx_busy    (uart_tx_busy),
        .tx_done    (uart_done),
        .tx_line    (uart_txd)
    );

    // ------------------------------------------------------------------------
    // ASCII Decimal Helpers
    // ------------------------------------------------------------------------
    function [7:0] f_tens;
        input [6:0] val;
        begin
            f_tens = 8'd48 + ((val / 10) % 10);
        end
    endfunction

    function [7:0] f_ones;
        input [6:0] val;
        begin
            f_ones = 8'd48 + (val % 10);
        end
    endfunction

    // ------------------------------------------------------------------------
    // Packet Character Sequencer
    // Total 64 Characters:
    // "[IRRIG] SOIL:xx% (TH:xx%) | T:xxC H:xx% | PUMP:ON  | RAIN:0 CYC:xxx\r\n"
    // ------------------------------------------------------------------------
    reg [5:0] char_idx;
    reg [2:0] state;

    localparam [2:0]
        ST_IDLE      = 3'd0,
        ST_LOAD_BYTE = 3'd1,
        ST_START_TX  = 3'd2,
        ST_WAIT_TX   = 3'd3,
        ST_NEXT_CHAR = 3'd4;

    reg [6:0]  snap_soil;
    reg [6:0]  snap_th;
    reg [6:0]  snap_temp;
    reg [6:0]  snap_hum;
    reg        snap_pump;
    reg        snap_rain;
    reg [15:0] snap_cycles;

    reg [7:0] curr_char;

    always @(*) begin
        case (char_idx)
            // "[IRRIG] " (8 chars: 0..7)
            6'd0:  curr_char = "[";
            6'd1:  curr_char = "I";
            6'd2:  curr_char = "R";
            6'd3:  curr_char = "R";
            6'd4:  curr_char = "I";
            6'd5:  curr_char = "G";
            6'd6:  curr_char = "]";
            6'd7:  curr_char = " ";

            // "SOIL:xx% " (8 chars: 8..15)
            6'd8:  curr_char = "S";
            6'd9:  curr_char = "O";
            6'd10: curr_char = "I";
            6'd11: curr_char = "L";
            6'd12: curr_char = ":";
            6'd13: curr_char = f_tens(snap_soil);
            6'd14: curr_char = f_ones(snap_soil);
            6'd15: curr_char = "%";

            // " (TH:xx%) | " (11 chars: 16..26)
            6'd16: curr_char = " ";
            6'd17: curr_char = "(";
            6'd18: curr_char = "T";
            6'd19: curr_char = "H";
            6'd20: curr_char = ":";
            6'd21: curr_char = f_tens(snap_th);
            6'd22: curr_char = f_ones(snap_th);
            6'd23: curr_char = "%";
            6'd24: curr_char = ")";
            6'd25: curr_char = " ";
            6'd26: curr_char = "|";

            // " T:xxC H:xx% | " (13 chars: 27..39)
            6'd27: curr_char = " ";
            6'd28: curr_char = "T";
            6'd29: curr_char = ":";
            6'd30: curr_char = f_tens(snap_temp);
            6'd31: curr_char = f_ones(snap_temp);
            6'd32: curr_char = "C";
            6'd33: curr_char = " ";
            6'd34: curr_char = "H";
            6'd35: curr_char = ":";
            6'd36: curr_char = f_tens(snap_hum);
            6'd37: curr_char = f_ones(snap_hum);
            6'd38: curr_char = "%";
            6'd39: curr_char = " ";

            // "PUMP:ON  | " (10 chars: 40..49)
            6'd40: curr_char = "|";
            6'd41: curr_char = " ";
            6'd42: curr_char = "P";
            6'd43: curr_char = "U";
            6'd44: curr_char = "M";
            6'd45: curr_char = "P";
            6'd46: curr_char = ":";
            6'd47: curr_char = (snap_pump) ? "O" : "O";
            6'd48: curr_char = (snap_pump) ? "N" : "F";
            6'd49: curr_char = (snap_pump) ? " " : "F";

            // " | RAIN:x " (9 chars: 50..58)
            6'd50: curr_char = " ";
            6'd51: curr_char = "|";
            6'd52: curr_char = " ";
            6'd53: curr_char = "R";
            6'd54: curr_char = "A";
            6'd55: curr_char = "I";
            6'd56: curr_char = "N";
            6'd57: curr_char = ":";
            6'd58: curr_char = (snap_rain) ? "1" : "0";

            // " \r\n" (4 chars: 59..62)
            6'd59: curr_char = " ";
            6'd60: curr_char = " ";
            6'd61: curr_char = "\r";
            6'd62: curr_char = "\n";
            default: curr_char = " ";
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            char_idx     <= 6'd0;
            uart_start   <= 1'b0;
            uart_tx_byte <= 8'h00;
            tx_busy      <= 1'b0;
            snap_soil    <= 7'd0;
            snap_th      <= 7'd0;
            snap_temp    <= 7'd0;
            snap_hum     <= 7'd0;
            snap_pump    <= 1'b0;
            snap_rain    <= 1'b0;
            snap_cycles  <= 16'd0;
        end else begin
            uart_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_busy  <= 1'b0;
                    char_idx <= 6'd0;
                    if (trigger_tx && !uart_tx_busy) begin
                        snap_soil   <= soil_moist_pct;
                        snap_th     <= adaptive_th_pct;
                        snap_temp   <= temp_c;
                        snap_hum    <= hum_pct;
                        snap_pump   <= pump_on;
                        snap_rain   <= rain_active;
                        snap_cycles <= cycle_count;
                        tx_busy     <= 1'b1;
                        state       <= ST_LOAD_BYTE;
                    end
                end

                ST_LOAD_BYTE: begin
                    uart_tx_byte <= curr_char;
                    state        <= ST_START_TX;
                end

                ST_START_TX: begin
                    uart_start <= 1'b1;
                    state      <= ST_WAIT_TX;
                end

                ST_WAIT_TX: begin
                    if (uart_done) state <= ST_NEXT_CHAR;
                end

                ST_NEXT_CHAR: begin
                    if (char_idx >= 6'd62) begin
                        state   <= ST_IDLE;
                        tx_busy <= 1'b0;
                    end else begin
                        char_idx <= char_idx + 1'b1;
                        state    <= ST_LOAD_BYTE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
