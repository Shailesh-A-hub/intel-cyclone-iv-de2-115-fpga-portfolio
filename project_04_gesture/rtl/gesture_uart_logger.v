//=============================================================================
// Module: gesture_uart_logger
// Description: Real-time 115200 baud ASCII serial telemetry logger for the
//              Gesture Menu System. Streams structured log packets upon every
//              detected gesture event and emits periodic status heartbeats.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module gesture_uart_logger #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire        clk,
    input  wire        reset_n,

    // Gesture and navigation events
    input  wire        gesture_valid,
    input  wire [2:0]  gesture_code,
    input  wire [31:0] gesture_ascii,
    input  wire [15:0] gesture_counter,
    input  wire [1:0]  current_menu,
    input  wire        in_submenu,
    input  wire [1:0]  submenu_page,

    // Hardware status
    input  wire        device_ready,
    input  wire        i2c_error,
    input  wire        tick_1sec,

    // Serial physical TX output
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

    // Telemetry Buffer (Maximum 48 bytes)
    reg [7:0] log_buffer [0:47];
    reg [5:0] log_len;
    reg [5:0] tx_idx;

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

    // Buffer population
    reg pending_event, pending_periodic;

    always @(posedge clk) begin
        if (!reset_n) begin
            state            <= ST_IDLE;
            tx_start         <= 1'b0;
            tx_data          <= 8'd0;
            tx_idx           <= 6'd0;
            log_len          <= 6'd0;
            tx_active_led    <= 1'b0;
            pending_event    <= 1'b0;
            pending_periodic <= 1'b0;
        end else begin
            tx_start <= 1'b0; // Default pulse

            if (gesture_valid)
                pending_event <= 1'b1;
            else if (tick_1sec && state == ST_IDLE && !pending_event)
                pending_periodic <= 1'b1;

            case (state)
                ST_IDLE: begin
                    tx_idx <= 6'd0;
                    if (pending_event) begin
                        pending_event <= 1'b0;
                        tx_active_led <= 1'b1;
                        // Format: "[GESTURE] EVT=XXXX MN=X SUB=X CNT=XXXXX\r\n" (38 chars)
                        log_buffer[0]  <= "["; log_buffer[1]  <= "G"; log_buffer[2]  <= "E"; log_buffer[3]  <= "S";
                        log_buffer[4]  <= "T"; log_buffer[5]  <= "U"; log_buffer[6]  <= "R"; log_buffer[7]  <= "E";
                        log_buffer[8]  <= "]"; log_buffer[9]  <= " "; log_buffer[10] <= "E"; log_buffer[11] <= "V";
                        log_buffer[12] <= "T"; log_buffer[13] <= "=";
                        log_buffer[14] <= gesture_ascii[31:24];
                        log_buffer[15] <= gesture_ascii[23:16];
                        log_buffer[16] <= gesture_ascii[15:8];
                        log_buffer[17] <= gesture_ascii[7:0];
                        log_buffer[18] <= " "; log_buffer[19] <= "M"; log_buffer[20] <= "N"; log_buffer[21] <= "=";
                        log_buffer[22] <= dec_char({2'b00, current_menu});
                        log_buffer[23] <= " "; log_buffer[24] <= "S"; log_buffer[25] <= "U"; log_buffer[26] <= "B";
                        log_buffer[27] <= "="; log_buffer[28] <= in_submenu ? "1" : "0";
                        log_buffer[29] <= " "; log_buffer[30] <= "C"; log_buffer[31] <= "N"; log_buffer[32] <= "T";
                        log_buffer[33] <= "=";
                        log_buffer[34] <= dec_char((gesture_counter / 1000) % 10);
                        log_buffer[35] <= dec_char((gesture_counter / 100) % 10);
                        log_buffer[36] <= dec_char((gesture_counter / 10) % 10);
                        log_buffer[37] <= dec_char(gesture_counter % 10);
                        log_buffer[38] <= 8'h0D; // \r
                        log_buffer[39] <= 8'h0A; // \n
                        log_len        <= 6'd40;
                        state          <= ST_SEND;
                    end else if (pending_periodic) begin
                        pending_periodic <= 1'b0;
                        // Format: "[STATUS] APDS=OK MN=X\r\n" (22 chars)
                        log_buffer[0]  <= "["; log_buffer[1]  <= "S"; log_buffer[2]  <= "T"; log_buffer[3]  <= "A";
                        log_buffer[4]  <= "T"; log_buffer[5]  <= "U"; log_buffer[6]  <= "S"; log_buffer[7]  <= "]";
                        log_buffer[8]  <= " "; log_buffer[9]  <= "A"; log_buffer[10] <= "P"; log_buffer[11] <= "D";
                        log_buffer[12] <= "S"; log_buffer[13] <= "=";
                        log_buffer[14] <= i2c_error ? "E" : (device_ready ? "O" : "W");
                        log_buffer[15] <= i2c_error ? "R" : (device_ready ? "K" : "T");
                        log_buffer[16] <= " "; log_buffer[17] <= "M"; log_buffer[18] <= "N"; log_buffer[19] <= "=";
                        log_buffer[20] <= dec_char({2'b00, current_menu});
                        log_buffer[21] <= 8'h0D;
                        log_buffer[22] <= 8'h0A;
                        log_len        <= 6'd23;
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
