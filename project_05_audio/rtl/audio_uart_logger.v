//=============================================================================
// Module: audio_uart_logger
// Project: Project 5 — Real-Time Audio Voice Spectrum Analyzer
// Description: Real-time 115200 baud ASCII serial telemetry logger for the
//              Audio Spectrum Analyzer. Outputs live audio classification,
//              dominant frequency bin index, peak magnitude, and a 16-segment
//              animated ASCII VU/equalizer meter:
//              "[AUDIO] CLS=VOIC BIN=012 MAG=04820 [######..........]\r\n"
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module audio_uart_logger #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire        clk,
    input  wire        reset_n,

    // Latched audio metrics from extractor & classifier
    input  wire        frame_valid,
    input  wire [2:0]  class_code,
    input  wire [31:0] class_ascii,
    input  wire [7:0]  peak_bin_index,
    input  wire [15:0] peak_magnitude,
    input  wire [27:0] total_energy,
    input  wire        tick_log,           // Periodic rate ticker (e.g. 100ms / 10Hz)

    // Serial physical line
    output wire        uart_txd,
    output reg         tx_active_led
);

    // UART TX Master instantiation
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire       tx_done;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk(clk),
        .rst(!reset_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx_line(uart_txd)
    );

    // Telemetry Buffer (64 bytes)
    reg [7:0] log_buffer [0:63];
    reg [6:0] log_len;
    reg [6:0] tx_idx;

    // FSM States
    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_SEND = 2'd1,
        ST_WAIT = 2'd2;

    reg [1:0] state;

    function [7:0] dec_char;
        input [3:0] d;
        begin
            dec_char = 8'h30 + d;
        end
    endfunction

    // 16-level audio bar graph calculator
    wire [4:0] bar_fill = (peak_magnitude >= 16'd32000) ? 5'd16 : 
                          (peak_magnitude[15:11] + (|peak_magnitude[10:8]));

    reg pending_log;

    always @(posedge clk) begin
        if (!reset_n) begin
            state         <= ST_IDLE;
            tx_start      <= 1'b0;
            tx_data       <= 8'd0;
            tx_idx        <= 7'd0;
            log_len       <= 7'd0;
            tx_active_led <= 1'b0;
            pending_log   <= 1'b0;
        end else begin
            tx_start <= 1'b0; // Default pulse

            if (tick_log)
                pending_log <= 1'b1;

            case (state)
                ST_IDLE: begin
                    tx_idx <= 7'd0;
                    if (pending_log && !tx_busy) begin
                        pending_log   <= 1'b0;
                        tx_active_led <= 1'b1;

                        // Format: "[AUDIO] CLS=XXXX BIN=XXX MAG=XXXXX [################]\r\n" (55 chars)
                        log_buffer[0]  <= "["; log_buffer[1]  <= "A"; log_buffer[2]  <= "U"; log_buffer[3]  <= "D";
                        log_buffer[4]  <= "I"; log_buffer[5]  <= "O"; log_buffer[6]  <= "]"; log_buffer[7]  <= " ";
                        log_buffer[8]  <= "C"; log_buffer[9]  <= "L"; log_buffer[10] <= "S"; log_buffer[11] <= "=";
                        log_buffer[12] <= class_ascii[31:24];
                        log_buffer[13] <= class_ascii[23:16];
                        log_buffer[14] <= class_ascii[15:8];
                        log_buffer[15] <= class_ascii[7:0];
                        log_buffer[16] <= " "; log_buffer[17] <= "B"; log_buffer[18] <= "I"; log_buffer[19] <= "N";
                        log_buffer[20] <= "=";
                        log_buffer[21] <= dec_char((peak_bin_index / 100) % 10);
                        log_buffer[22] <= dec_char((peak_bin_index / 10) % 10);
                        log_buffer[23] <= dec_char(peak_bin_index % 10);
                        log_buffer[24] <= " "; log_buffer[25] <= "M"; log_buffer[26] <= "A"; log_buffer[27] <= "G";
                        log_buffer[28] <= "=";
                        log_buffer[29] <= dec_char((peak_magnitude / 10000) % 10);
                        log_buffer[30] <= dec_char((peak_magnitude / 1000) % 10);
                        log_buffer[31] <= dec_char((peak_magnitude / 100) % 10);
                        log_buffer[32] <= dec_char((peak_magnitude / 10) % 10);
                        log_buffer[33] <= dec_char(peak_magnitude % 10);
                        log_buffer[34] <= " "; log_buffer[35] <= "[";
                        log_buffer[36] <= (bar_fill > 5'd0)  ? "#" : ".";
                        log_buffer[37] <= (bar_fill > 5'd1)  ? "#" : ".";
                        log_buffer[38] <= (bar_fill > 5'd2)  ? "#" : ".";
                        log_buffer[39] <= (bar_fill > 5'd3)  ? "#" : ".";
                        log_buffer[40] <= (bar_fill > 5'd4)  ? "#" : ".";
                        log_buffer[41] <= (bar_fill > 5'd5)  ? "#" : ".";
                        log_buffer[42] <= (bar_fill > 5'd6)  ? "#" : ".";
                        log_buffer[43] <= (bar_fill > 5'd7)  ? "#" : ".";
                        log_buffer[44] <= (bar_fill > 5'd8)  ? "#" : ".";
                        log_buffer[45] <= (bar_fill > 5'd9)  ? "#" : ".";
                        log_buffer[46] <= (bar_fill > 5'd10) ? "#" : ".";
                        log_buffer[47] <= (bar_fill > 5'd11) ? "#" : ".";
                        log_buffer[48] <= (bar_fill > 5'd12) ? "#" : ".";
                        log_buffer[49] <= (bar_fill > 5'd13) ? "#" : ".";
                        log_buffer[50] <= (bar_fill > 5'd14) ? "#" : ".";
                        log_buffer[51] <= (bar_fill > 5'd15) ? "#" : ".";
                        log_buffer[52] <= "]";
                        log_buffer[53] <= 8'h0D; // \r
                        log_buffer[54] <= 8'h0A; // \n
                        log_len        <= 7'd55;
                        state          <= ST_SEND;
                    end else begin
                        tx_active_led <= 1'b0;
                    end
                end

                ST_SEND: begin
                    if (!tx_busy && tx_idx < log_len) begin
                        tx_data  <= log_buffer[tx_idx];
                        tx_start <= 1'b1;
                        state    <= ST_WAIT;
                    end else if (tx_idx >= log_len) begin
                        state <= ST_IDLE;
                    end
                end

                ST_WAIT: begin
                    if (tx_done) begin
                        tx_idx <= tx_idx + 1'b1;
                        state  <= ST_SEND;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
