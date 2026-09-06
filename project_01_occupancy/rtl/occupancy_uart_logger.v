//=============================================================================
// Module: occupancy_uart_logger
// Project: Project 1 - Multi-Zone Occupancy & Energy-Saving Engine
// Description: Serial telemetry formatter. Transmits periodic status frames
//              and state transition events over UART at 115200 baud.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module occupancy_uart_logger #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        send_trigger,      // Pulse to trigger telemetry transmission
    input  wire [3:0]  zone_occupied,     // Zone occupancy vector
    input  wire [1:0]  hvac_level,        // Current HVAC level (0-3)
    input  wire [15:0] energy_wh,         // Energy saved in Watt-hours
    output wire        uart_txd           // Serial physical line
);

    // Instantiate Common Platform UART TX
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire       tx_done;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8),
        .STOP_BITS(1)
    ) u_uart_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_line(uart_txd),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // Hex to ASCII converter function
    function [7:0] hex_to_ascii(input [3:0] nibble);
        begin
            hex_to_ascii = (nibble < 4'd10) ? (8'h30 + {4'h0, nibble}) : (8'h41 + {4'h0, (nibble - 4'd10)});
        end
    endfunction

    // Message frame length: 28 characters
    // Example: "[P1] Z:1000 H:2 E:0014Wh\r\n"
    localparam TOTAL_CHARS = 28;
    reg [4:0] char_idx;
    reg       transmitting;

    always @(posedge clk) begin
        if (rst) begin
            char_idx     <= 5'd0;
            transmitting <= 1'b0;
            tx_start     <= 1'b0;
            tx_data      <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            if (!transmitting) begin
                if (send_trigger && !tx_busy) begin
                    transmitting <= 1'b1;
                    char_idx     <= 5'd0;
                end
            end else begin
                if (!tx_busy && !tx_start) begin
                    case (char_idx)
                        5'd0:  tx_data <= "[";
                        5'd1:  tx_data <= "P";
                        5'd2:  tx_data <= "1";
                        5'd3:  tx_data <= "]";
                        5'd4:  tx_data <= " ";
                        5'd5:  tx_data <= "Z";
                        5'd6:  tx_data <= ":";
                        5'd7:  tx_data <= zone_occupied[3] ? "1" : "0";
                        5'd8:  tx_data <= zone_occupied[2] ? "1" : "0";
                        5'd9:  tx_data <= zone_occupied[1] ? "1" : "0";
                        5'd10: tx_data <= zone_occupied[0] ? "1" : "0";
                        5'd11: tx_data <= " ";
                        5'd12: tx_data <= "H";
                        5'd13: tx_data <= ":";
                        5'd14: tx_data <= hex_to_ascii({2'b00, hvac_level});
                        5'd15: tx_data <= " ";
                        5'd16: tx_data <= "E";
                        5'd17: tx_data <= ":";
                        5'd18: tx_data <= hex_to_ascii(energy_wh[15:12]);
                        5'd19: tx_data <= hex_to_ascii(energy_wh[11:8]);
                        5'd20: tx_data <= hex_to_ascii(energy_wh[7:4]);
                        5'd21: tx_data <= hex_to_ascii(energy_wh[3:0]);
                        5'd22: tx_data <= "W";
                        5'd23: tx_data <= "h";
                        5'd24: tx_data <= "\r";
                        5'd25: tx_data <= "\n";
                        default: tx_data <= " ";
                    endcase
                    tx_start <= 1'b1;

                    if (char_idx == 5'd25) begin
                        transmitting <= 1'b0;
                    end else begin
                        char_idx <= char_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
