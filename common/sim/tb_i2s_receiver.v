//=============================================================================
// Testbench: tb_i2s_receiver
// Description: Self-checking testbench for standard Philips I2S receiver.
//=============================================================================

`timescale 1ns / 1ps

module tb_i2s_receiver;

    reg clk;
    reg rst;

    reg i2s_bclk;
    reg i2s_lrclk;
    reg i2s_sdata;

    wire signed [15:0] left_data;
    wire signed [15:0] right_data;
    wire sample_valid;

    i2s_receiver #(.AUDIO_WIDTH(16)) dut (
        .clk(clk),
        .rst(rst),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdata(i2s_sdata),
        .left_data(left_data),
        .right_data(right_data),
        .sample_valid(sample_valid)
    );

    // 50 MHz system clock
    always #10 clk = ~clk;

    // Task to transmit 16-bit word over I2S with Philips 1-bit delay
    task send_i2s_channel(input [15:0] data_word, input lr_val);
        integer b;
        begin
            i2s_lrclk = lr_val;

            // BCLK cycle 0: 1-bit delay in Philips I2S
            i2s_bclk = 0; #160;
            i2s_bclk = 1; #160;

            // BCLK cycles 1 to 16: transmit data MSB to LSB
            for (b = 15; b >= 0; b = b - 1) begin
                i2s_bclk  = 0;
                i2s_sdata = data_word[b];
                #160;
                i2s_bclk  = 1;
                #160;
            end

            // Extra padding BCLK cycles per frame (e.g. 15 cycles)
            repeat (15) begin
                i2s_bclk  = 0;
                i2s_sdata = 0;
                #160;
                i2s_bclk  = 1;
                #160;
            end
        end
    endtask

    integer errors = 0;

    initial begin
        clk = 0;
        rst = 1;
        i2s_bclk  = 0;
        i2s_lrclk = 1;
        i2s_sdata = 0;
        #95;
        rst = 0;
        #200;

        // Send stereo frame: Left = 0x3A5C, Right = 0x7E19
        fork
            begin
                send_i2s_channel(16'h3A5C, 1'b0); // Left channel (LRCLK = 0)
                send_i2s_channel(16'h7E19, 1'b1); // Right channel (LRCLK = 1)
            end
            begin
                wait (sample_valid == 1'b1);
                if (left_data !== 16'h3A5C) begin
                    $display("ERROR: Left channel mismatch! Expected 0x3A5C, got 0x%04X", left_data);
                    errors = errors + 1;
                end
                if (right_data !== 16'h7E19) begin
                    $display("ERROR: Right channel mismatch! Expected 0x7E19, got 0x%04X", right_data);
                    errors = errors + 1;
                end
                if (left_data === 16'h3A5C && right_data === 16'h7E19) begin
                    $display("INFO: I2S frame verified: Left=0x%04X, Right=0x%04X", left_data, right_data);
                end
            end
        join

        #500;
        if (errors == 0) begin
            $display("=== TB_I2S_RECEIVER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_I2S_RECEIVER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
