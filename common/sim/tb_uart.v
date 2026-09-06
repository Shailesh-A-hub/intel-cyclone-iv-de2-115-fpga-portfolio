//=============================================================================
// Testbench: tb_uart
// Description: Full duplex loopback testbench connecting uart_tx to uart_rx.
//=============================================================================

`timescale 1ns / 1ps

module tb_uart;

    reg clk;
    reg rst;

    // Simulation parameters: 16 MHz clock, 100 kBaud -> exactly 160 cycles/bit, 10 cycles/oversample tick
    localparam CLK_FREQ_HZ = 16_000_000;
    localparam BAUD_RATE   = 100_000;

    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_line;
    wire       tx_busy;
    wire       tx_done;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_error;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8),
        .STOP_BITS(1)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_line(tx_line),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8)
    ) u_rx (
        .clk(clk),
        .rst(rst),
        .rx_line(tx_line), // Loopback connection
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_error(rx_error)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    reg [7:0] test_bytes [0:4];
    integer i;

    initial begin
        clk = 0;
        rst = 1;
        tx_start = 0;
        tx_data = 8'h00;

        test_bytes[0] = 8'hA5;
        test_bytes[1] = 8'h5A;
        test_bytes[2] = 8'h00;
        test_bytes[3] = 8'hFF;
        test_bytes[4] = 8'h7E;

        #40;
        @(posedge clk);
        rst = 0;
        #200;

        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            tx_data  = test_bytes[i];
            tx_start = 1;
            @(posedge clk);
            tx_start = 0;

            // Wait for receiver valid strobe
            wait (rx_valid == 1'b1);
            @(posedge clk);
            #1;
            if (rx_data !== test_bytes[i]) begin
                $display("ERROR: Byte %0d mismatch! Expected 0x%02X, got 0x%02X", i, test_bytes[i], rx_data);
                errors = errors + 1;
            end else begin
                $display("INFO: Successfully transmitted and verified byte %0d: 0x%02X", i, rx_data);
            end

            wait (tx_done == 1'b1);
            #200;
        end

        #500;
        if (errors == 0) begin
            $display("=== TB_UART: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_UART: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
