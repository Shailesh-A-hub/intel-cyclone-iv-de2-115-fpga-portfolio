//=============================================================================
// Testbench: tb_spi_master
// Description: Self-checking testbench for spi_master verifying Mode 0.
//=============================================================================

`timescale 1ns / 1ps

module tb_spi_master;

    reg clk;
    reg rst;
    reg start;
    reg [7:0] tx_data;
    wire [7:0] rx_data;
    wire busy;
    wire done;

    wire spi_sclk;
    wire spi_mosi;
    reg  spi_miso;
    wire spi_cs_n;

    spi_master #(
        .DATA_WIDTH(8),
        .CPOL(0),
        .CPHA(0),
        .CLK_DIV(8) // 8 clock cycles per SCLK period
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .busy(busy),
        .done(done),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n)
    );

    always #10 clk = ~clk;

    // Standard SPI Mode 0 Slave:
    // Responds with 0xAA (10101010b) when addressed
    reg [7:0] slave_shift;

    always @(spi_cs_n) begin
        if (spi_cs_n) begin
            spi_miso    <= 1'b0;
            slave_shift <= 8'h00;
        end else begin
            // Upon CS assertion, immediately output MSB of response (0xAA)
            slave_shift <= 8'hAA;
            spi_miso    <= 1'b1; // MSB of 0xAA is 1
        end
    end

    always @(negedge spi_sclk) begin
        if (!spi_cs_n) begin
            // Shift next bit out on trailing falling edge
            spi_miso    <= slave_shift[6];
            slave_shift <= {slave_shift[6:0], 1'b0};
        end
    end

    integer errors = 0;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        tx_data = 8'h00;
        spi_miso = 0;
        #40;
        @(posedge clk); #1;
        rst = 0;
        #50;

        // Transmit 0x55
        @(posedge clk); #1;
        tx_data = 8'h55;
        start   = 1;
        @(posedge clk); #1;
        start   = 0;

        wait (done == 1'b1);
        @(posedge clk); #1;

        if (rx_data !== 8'hAA) begin
            $display("ERROR: SPI transfer failed! Expected 0xAA, got 0x%02X", rx_data);
            errors = errors + 1;
        end else begin
            $display("INFO: SPI transfer verified: sent 0x55, received expected 0xAA");
        end

        #100;
        if (errors == 0) begin
            $display("=== TB_SPI_MASTER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_SPI_MASTER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
