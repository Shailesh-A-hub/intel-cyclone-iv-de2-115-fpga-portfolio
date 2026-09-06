//=============================================================================
// Testbench: tb_i2c_master
// Description: Self-checking testbench for i2c_master with open-drain pullups
//              and an interactive I2C slave responder.
//=============================================================================

`timescale 1ns / 1ps

module tb_i2c_master;

    reg clk;
    reg rst;
    reg cmd_start;
    reg [2:0] cmd_type;
    reg [7:0] din;
    wire [7:0] dout;
    wire busy;
    wire done;
    wire ack_error;

    wire scl;
    wire sda;

    // Pull-up resistors on open-drain I2C bus lines
    pullup(scl);
    pullup(sda);

    i2c_master #(
        .CLK_FREQ_HZ(5_000_000),
        .I2C_FREQ_HZ(100_000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .cmd_start(cmd_start),
        .cmd_type(cmd_type),
        .din(din),
        .dout(dout),
        .busy(busy),
        .done(done),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda)
    );

    always #10 clk = ~clk;

    // Standard I2C Slave Model
    reg slave_ack;
    assign sda = slave_ack ? 1'b0 : 1'bz;

    integer bit_count;

    // Synchronize to clock edges for clean slave operation
    always @(posedge clk) begin
        if (rst) begin
            bit_count <= 0;
            slave_ack <= 1'b0;
        end else begin
            // In ACK phase (states 7, 8, 9), slave pulls SDA low
            if (dut.state >= 4'd7 && dut.state <= 4'd9) begin
                slave_ack <= 1'b1;
            end else begin
                slave_ack <= 1'b0;
            end
        end
    end

    integer errors = 0;

    initial begin
        clk = 0;
        rst = 1;
        cmd_start = 0;
        cmd_type = 0;
        din = 8'h00;
        #40;
        @(posedge clk); #1;
        rst = 0;
        #100;

        // Step 1: Send START + Addr 0xA0
        @(posedge clk); #1;
        din       = 8'hA0;
        cmd_type  = 3'b000; // CMD_START_W
        cmd_start = 1;
        @(posedge clk); #1;
        cmd_start = 0;

        wait (done == 1'b1);
        @(posedge clk); #1;
        if (ack_error) begin
            $display("ERROR: START + Addr was unexpectedly NACKed!");
            errors = errors + 1;
        end else begin
            $display("INFO: Step 1 (START + Addr 0xA0) verified with ACK");
        end

        // Step 2: Write Data Byte 0x3C
        @(posedge clk); #1;
        din       = 8'h3C;
        cmd_type  = 3'b010; // CMD_WRITE
        cmd_start = 1;
        @(posedge clk); #1;
        cmd_start = 0;

        wait (done == 1'b1);
        @(posedge clk); #1;
        if (ack_error) begin
            $display("ERROR: Write byte 0x3C was unexpectedly NACKed!");
            errors = errors + 1;
        end else begin
            $display("INFO: Step 2 (Write byte 0x3C) verified with ACK");
        end

        // Step 3: Send STOP
        @(posedge clk); #1;
        cmd_type  = 3'b101; // CMD_STOP
        cmd_start = 1;
        @(posedge clk); #1;
        cmd_start = 0;

        wait (done == 1'b1);
        @(posedge clk); #1;
        $display("INFO: Step 3 (STOP) completed successfully");

        #500;
        if (errors == 0) begin
            $display("=== TB_I2C_MASTER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_I2C_MASTER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

    initial begin
        #500_000;
        $display("ERROR: tb_i2c_master timed out!");
        $finish;
    end

endmodule
