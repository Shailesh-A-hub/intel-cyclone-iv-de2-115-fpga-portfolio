//=============================================================================
// Module: inter9_uart_logger
// Project: Project 4 / Intermediate #9 — Gesture-Based Menu Navigation Interface
// Target: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
// Description: Streams human-readable ASCII telemetry logs to a PC terminal
//              over UART (9600 baud, 8N1) whenever gestures or menu transitions occur.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module inter9_uart_logger #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 9600
)(
    input  wire        clk,
    input  wire        rst,

    // Trigger Pulses
    input  wire        gesture_select_pulse,
    input  wire        gesture_back_pulse,
    input  wire        gesture_confirm_pulse,
    input  wire        menu_event_pulse,
    input  wire [2:0]  menu_event_type,        // 1: Cursor, 2: Submenu, 3: Home
    input  wire [1:0]  cursor_pos,

    // UART Physical Output to CP2101 RX
    output wire        uart_txd
);

    // UART Transmitter IP instantiation
    reg        uart_tx_start;
    reg  [7:0] uart_tx_data;
    wire       uart_tx_busy;
    wire       uart_tx_done;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx_line(uart_txd),
        .tx_busy(uart_tx_busy),
        .tx_done(uart_tx_done)
    );

    // String Buffer: Max 36 characters
    reg [7:0] msg_buffer [0:35];
    reg [5:0] msg_len;
    reg [5:0] send_idx;
    reg       sending;

    // Trigger latching queue (simple priority arbiter)
    reg trig_ready;
    reg trig_select, trig_back, trig_confirm, trig_submenu, trig_home;

    // Ready message sent on power-up
    reg powerup_sent;

    always @(posedge clk) begin
        if (rst) begin
            trig_ready    <= 1'b1;
            trig_select   <= 1'b0;
            trig_back     <= 1'b0;
            trig_confirm  <= 1'b0;
            trig_submenu  <= 1'b0;
            trig_home     <= 1'b0;
        end else begin
            if (gesture_select_pulse)  trig_select  <= 1'b1;
            if (gesture_back_pulse)    trig_back    <= 1'b1;
            if (gesture_confirm_pulse) trig_confirm <= 1'b1;
            if (menu_event_pulse && menu_event_type == 3'd2) trig_submenu <= 1'b1;
            if (menu_event_pulse && menu_event_type == 3'd3) trig_home    <= 1'b1;

            // Clear triggers once handled
            if (!sending && !uart_tx_busy) begin
                if (trig_ready && !powerup_sent) trig_ready <= 1'b0;
                else if (trig_select)   trig_select  <= 1'b0;
                else if (trig_back)     trig_back    <= 1'b0;
                else if (trig_confirm)  trig_confirm <= 1'b0;
                else if (trig_submenu)  trig_submenu <= 1'b0;
                else if (trig_home)     trig_home    <= 1'b0;
            end
        end
    end

    // FSM to load and stream messages
    localparam [1:0]
        S_IDLE = 2'd0,
        S_SEND = 2'd1,
        S_WAIT = 2'd2;

    reg [1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            sending       <= 1'b0;
            send_idx      <= 0;
            uart_tx_start <= 1'b0;
            uart_tx_data  <= 8'h00;
            powerup_sent  <= 1'b0;
        end else begin
            uart_tx_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    send_idx <= 0;
                    if (trig_ready && !powerup_sent) begin
                        powerup_sent <= 1'b1;
                        // "[SYSTEM] Ready\r\n" (16 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "S"; msg_buffer[2]  <= "Y";
                        msg_buffer[3]  <= "S"; msg_buffer[4]  <= "T"; msg_buffer[5]  <= "E";
                        msg_buffer[6]  <= "M"; msg_buffer[7]  <= "]"; msg_buffer[8]  <= " ";
                        msg_buffer[9]  <= "R"; msg_buffer[10] <= "e"; msg_buffer[11] <= "a";
                        msg_buffer[12] <= "d"; msg_buffer[13] <= "y"; msg_buffer[14] <= 8'h0D;
                        msg_buffer[15] <= 8'h0A;
                        msg_len  <= 16;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else if (trig_select) begin
                        // "[GESTURE] Left->Center : SELECT\r\n" (33 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "G"; msg_buffer[2]  <= "E";
                        msg_buffer[3]  <= "S"; msg_buffer[4]  <= "T"; msg_buffer[5]  <= "U";
                        msg_buffer[6]  <= "R"; msg_buffer[7]  <= "E"; msg_buffer[8]  <= "]";
                        msg_buffer[9]  <= " "; msg_buffer[10] <= "L"; msg_buffer[11] <= "e";
                        msg_buffer[12] <= "f"; msg_buffer[13] <= "t"; msg_buffer[14] <= "-";
                        msg_buffer[15] <= ">"; msg_buffer[16] <= "C"; msg_buffer[17] <= "e";
                        msg_buffer[18] <= "n"; msg_buffer[19] <= "t"; msg_buffer[20] <= "e";
                        msg_buffer[21] <= "r"; msg_buffer[22] <= " "; msg_buffer[23] <= ":";
                        msg_buffer[24] <= " "; msg_buffer[25] <= "S"; msg_buffer[26] <= "E";
                        msg_buffer[27] <= "L"; msg_buffer[28] <= "E"; msg_buffer[29] <= "C";
                        msg_buffer[30] <= "T"; msg_buffer[31] <= 8'h0D; msg_buffer[32] <= 8'h0A;
                        msg_len  <= 33;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else if (trig_back) begin
                        // "[GESTURE] Right->Center : BACK\r\n" (32 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "G"; msg_buffer[2]  <= "E";
                        msg_buffer[3]  <= "S"; msg_buffer[4]  <= "T"; msg_buffer[5]  <= "U";
                        msg_buffer[6]  <= "R"; msg_buffer[7]  <= "E"; msg_buffer[8]  <= "]";
                        msg_buffer[9]  <= " "; msg_buffer[10] <= "R"; msg_buffer[11] <= "i";
                        msg_buffer[12] <= "g"; msg_buffer[13] <= "h"; msg_buffer[14] <= "t";
                        msg_buffer[15] <= "-"; msg_buffer[16] <= ">"; msg_buffer[17] <= "C";
                        msg_buffer[18] <= "e"; msg_buffer[19] <= "n"; msg_buffer[20] <= "t";
                        msg_buffer[21] <= "e"; msg_buffer[22] <= "r"; msg_buffer[23] <= " ";
                        msg_buffer[24] <= ":"; msg_buffer[25] <= " "; msg_buffer[26] <= "B";
                        msg_buffer[27] <= "A"; msg_buffer[28] <= "C"; msg_buffer[29] <= "K";
                        msg_buffer[30] <= 8'h0D; msg_buffer[31] <= 8'h0A;
                        msg_len  <= 32;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else if (trig_confirm) begin
                        // "[GESTURE] Center->Confirm : CONFIRM\r\n" (36 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "G"; msg_buffer[2]  <= "E";
                        msg_buffer[3]  <= "S"; msg_buffer[4]  <= "T"; msg_buffer[5]  <= "U";
                        msg_buffer[6]  <= "R"; msg_buffer[7]  <= "E"; msg_buffer[8]  <= "]";
                        msg_buffer[9]  <= " "; msg_buffer[10] <= "C"; msg_buffer[11] <= "e";
                        msg_buffer[12] <= "n"; msg_buffer[13] <= "t"; msg_buffer[14] <= "e";
                        msg_buffer[15] <= "r"; msg_buffer[16] <= "-"; msg_buffer[17] <= ">";
                        msg_buffer[18] <= "C"; msg_buffer[19] <= "o"; msg_buffer[20] <= "n";
                        msg_buffer[21] <= "f"; msg_buffer[22] <= "i"; msg_buffer[23] <= "r";
                        msg_buffer[24] <= "m"; msg_buffer[25] <= " "; msg_buffer[26] <= ":";
                        msg_buffer[27] <= " "; msg_buffer[28] <= "C"; msg_buffer[29] <= "O";
                        msg_buffer[30] <= "N"; msg_buffer[31] <= "F"; msg_buffer[32] <= "I";
                        msg_buffer[33] <= "R"; msg_buffer[34] <= 8'h0D; msg_buffer[35] <= 8'h0A;
                        msg_len  <= 36;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else if (trig_submenu) begin
                        // "[ACTION] Displaying Submenu\r\n" (28 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "A"; msg_buffer[2]  <= "C";
                        msg_buffer[3]  <= "T"; msg_buffer[4]  <= "I"; msg_buffer[5]  <= "O";
                        msg_buffer[6]  <= "N"; msg_buffer[7]  <= "]"; msg_buffer[8]  <= " ";
                        msg_buffer[9]  <= "D"; msg_buffer[10] <= "i"; msg_buffer[11] <= "s";
                        msg_buffer[12] <= "p"; msg_buffer[13] <= "l"; msg_buffer[14] <= "a";
                        msg_buffer[15] <= "y"; msg_buffer[16] <= "i"; msg_buffer[17] <= "n";
                        msg_buffer[18] <= "g"; msg_buffer[19] <= " "; msg_buffer[20] <= "S";
                        msg_buffer[21] <= "u"; msg_buffer[22] <= "b"; msg_buffer[23] <= "m";
                        msg_buffer[24] <= "e"; msg_buffer[25] <= "n"; msg_buffer[26] <= "u";
                        msg_buffer[27] <= 8'h0D; msg_buffer[28] <= 8'h0A;
                        msg_len  <= 29;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else if (trig_home) begin
                        // "[MENU] Returned Home\r\n" (22 bytes)
                        msg_buffer[0]  <= "["; msg_buffer[1]  <= "M"; msg_buffer[2]  <= "E";
                        msg_buffer[3]  <= "N"; msg_buffer[4]  <= "U"; msg_buffer[5]  <= "]";
                        msg_buffer[6]  <= " "; msg_buffer[7]  <= "R"; msg_buffer[8]  <= "e";
                        msg_buffer[9]  <= "t"; msg_buffer[10] <= "u"; msg_buffer[11] <= "r";
                        msg_buffer[12] <= "n"; msg_buffer[13] <= "e"; msg_buffer[14] <= "d";
                        msg_buffer[15] <= " "; msg_buffer[16] <= "H"; msg_buffer[17] <= "o";
                        msg_buffer[18] <= "m"; msg_buffer[19] <= "e"; msg_buffer[20] <= 8'h0D;
                        msg_buffer[21] <= 8'h0A;
                        msg_len  <= 22;
                        sending  <= 1'b1;
                        state    <= S_SEND;
                    end else begin
                        sending <= 1'b0;
                    end
                end

                S_SEND: begin
                    if (!uart_tx_busy) begin
                        uart_tx_data  <= msg_buffer[send_idx];
                        uart_tx_start <= 1'b1;
                        state         <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (uart_tx_done) begin
                        if (send_idx + 1 < msg_len) begin
                            send_idx <= send_idx + 1'b1;
                            state    <= S_SEND;
                        end else begin
                            state   <= S_IDLE;
                            sending <= 1'b0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
