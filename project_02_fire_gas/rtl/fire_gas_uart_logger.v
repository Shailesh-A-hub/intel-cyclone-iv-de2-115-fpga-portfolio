// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   fire_gas_uart_logger.v
// Description: Real-time ASCII telemetry packet formatter and UART transmitter.
//              Outputs live telemetry strings at 115200 baud:
//              "[FIRE_GAS] G:xx% T:xxC F:xx% H:xx% | RISK:xxx [SAFE  ] FLT:x\r\n"
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module fire_gas_uart_logger #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 115_200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Telemetry Trigger
    input  wire        trigger_tx,

    // Sensor & Risk Values
    input  wire [6:0]  gas_pct,
    input  wire [6:0]  temp_c,
    input  wire [6:0]  flame_pct,
    input  wire [6:0]  hum_pct,
    input  wire [6:0]  risk_score,
    input  wire [1:0]  risk_level,
    input  wire [4:0]  fault_code,

    // UART Physical Output
    output wire        uart_txd,
    output reg         tx_busy
);

    // ------------------------------------------------------------------------
    // UART TX Module Instance
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
    function [7:0] to_ascii_dec_tens;
        input [6:0] val;
        begin
            to_ascii_dec_tens = 8'd48 + ((val / 10) % 10);
        end
    endfunction

    function [7:0] to_ascii_dec_ones;
        input [6:0] val;
        begin
            to_ascii_dec_ones = 8'd48 + (val % 10);
        end
    endfunction

    function [7:0] to_ascii_dec_hundreds;
        input [6:0] val;
        begin
            to_ascii_dec_hundreds = (val >= 100) ? 8'd49 : 8'd48;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Packet Sequencer
    // Total string length = 64 characters:
    // "[FIRE_GAS] G:xx% T:xxC F:xx% H:xx% | RISK:xxx [SAFE  ] FLT:xx\r\n"
    // ------------------------------------------------------------------------
    localparam TOTAL_CHARS = 64;

    reg [5:0] char_idx;
    reg [2:0] state;

    localparam [2:0]
        ST_IDLE      = 3'd0,
        ST_LOAD_BYTE = 3'd1,
        ST_START_TX  = 3'd2,
        ST_WAIT_TX   = 3'd3,
        ST_NEXT_CHAR = 3'd4;

    // Snapshot registers to prevent telemetry jitter during print
    reg [6:0] snap_gas;
    reg [6:0] snap_temp;
    reg [6:0] snap_flame;
    reg [6:0] snap_hum;
    reg [6:0] snap_risk;
    reg [1:0] snap_level;
    reg [4:0] snap_fault;

    reg [7:0] curr_char;

    always @(*) begin
        case (char_idx)
            // "[FIRE_GAS] " (11 chars: 0..10)
            6'd0:  curr_char = "[";
            6'd1:  curr_char = "F";
            6'd2:  curr_char = "I";
            6'd3:  curr_char = "R";
            6'd4:  curr_char = "E";
            6'd5:  curr_char = "_";
            6'd6:  curr_char = "G";
            6'd7:  curr_char = "A";
            6'd8:  curr_char = "S";
            6'd9:  curr_char = "]";
            6'd10: curr_char = " ";

            // "G:xx% " (6 chars: 11..16)
            6'd11: curr_char = "G";
            6'd12: curr_char = ":";
            6'd13: curr_char = to_ascii_dec_tens(snap_gas);
            6'd14: curr_char = to_ascii_dec_ones(snap_gas);
            6'd15: curr_char = "%";
            6'd16: curr_char = " ";

            // "T:xxC " (6 chars: 17..22)
            6'd17: curr_char = "T";
            6'd18: curr_char = ":";
            6'd19: curr_char = to_ascii_dec_tens(snap_temp);
            6'd20: curr_char = to_ascii_dec_ones(snap_temp);
            6'd21: curr_char = "C";
            6'd22: curr_char = " ";

            // "F:xx% " (6 chars: 23..28)
            6'd23: curr_char = "F";
            6'd24: curr_char = ":";
            6'd25: curr_char = to_ascii_dec_tens(snap_flame);
            6'd26: curr_char = to_ascii_dec_ones(snap_flame);
            6'd27: curr_char = "%";
            6'd28: curr_char = " ";

            // "H:xx% | " (8 chars: 29..36)
            6'd29: curr_char = "H";
            6'd30: curr_char = ":";
            6'd31: curr_char = to_ascii_dec_tens(snap_hum);
            6'd32: curr_char = to_ascii_dec_ones(snap_hum);
            6'd33: curr_char = "%";
            6'd34: curr_char = " ";
            6'd35: curr_char = "|";
            6'd36: curr_char = " ";

            // "RISK:xxx " (9 chars: 37..45)
            6'd37: curr_char = "R";
            6'd38: curr_char = "I";
            6'd39: curr_char = "S";
            6'd40: curr_char = "K";
            6'd41: curr_char = ":";
            6'd42: curr_char = to_ascii_dec_hundreds(snap_risk);
            6'd43: curr_char = to_ascii_dec_tens(snap_risk);
            6'd44: curr_char = to_ascii_dec_ones(snap_risk);
            6'd45: curr_char = " ";

            // "[SAFE  ] " (9 chars: 46..54)
            6'd46: curr_char = "[";
            6'd47: curr_char = (snap_level == 2'b00) ? "S" : (snap_level == 2'b01) ? "C" : (snap_level == 2'b10) ? "D" : "F";
            6'd48: curr_char = (snap_level == 2'b00) ? "A" : (snap_level == 2'b01) ? "A" : (snap_level == 2'b10) ? "A" : "A";
            6'd49: curr_char = (snap_level == 2'b00) ? "F" : (snap_level == 2'b01) ? "U" : (snap_level == 2'b10) ? "N" : "U";
            6'd50: curr_char = (snap_level == 2'b00) ? "E" : (snap_level == 2'b01) ? "T" : (snap_level == 2'b10) ? "G" : "L";
            6'd51: curr_char = (snap_level == 2'b10) ? "E" : (snap_level == 2'b11) ? "T" : " ";
            6'd52: curr_char = (snap_level == 2'b10) ? "R" : " ";
            6'd53: curr_char = "]";
            6'd54: curr_char = " ";

            // "FLT:xx\r\n" (9 chars: 55..63)
            6'd55: curr_char = "F";
            6'd56: curr_char = "L";
            6'd57: curr_char = "T";
            6'd58: curr_char = ":";
            6'd59: curr_char = 8'd48 + {3'b000, snap_fault[4]};
            6'd60: curr_char = (snap_fault[3:0] < 4'd10) ? (8'd48 + {4'd0, snap_fault[3:0]}) : (8'd55 + {4'd0, snap_fault[3:0]});
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
            snap_gas     <= 7'd0;
            snap_temp    <= 7'd0;
            snap_flame   <= 7'd0;
            snap_hum     <= 7'd0;
            snap_risk    <= 7'd0;
            snap_level   <= 2'd0;
            snap_fault   <= 5'd0;
        end else begin
            uart_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_busy  <= 1'b0;
                    char_idx <= 6'd0;
                    if (trigger_tx && !uart_tx_busy) begin
                        snap_gas   <= gas_pct;
                        snap_temp  <= temp_c;
                        snap_flame <= flame_pct;
                        snap_hum   <= hum_pct;
                        snap_risk  <= risk_score;
                        snap_level <= risk_level;
                        snap_fault <= fault_code;
                        tx_busy    <= 1'b1;
                        state      <= ST_LOAD_BYTE;
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
                    if (uart_done) begin
                        state <= ST_NEXT_CHAR;
                    end
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
