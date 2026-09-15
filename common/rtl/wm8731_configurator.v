//=============================================================================
// Module: wm8731_configurator
// Description: Automated I2C sequencer that initializes the Wolfson WM8731
//              audio codec on the DE2-115 board into 48 kHz, 16-bit I2S mode.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module wm8731_configurator #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000
)(
    input  wire clk,
    input  wire rst,
    input  wire start,           // Pulse high to trigger configuration sequence
    output reg  config_done,     // High once all 10 registers are written
    output reg  config_error,    // High if any I2C write was NACKed
    inout  wire i2c_scl,         // Physical I2C SCL (PIN_B7)
    inout  wire i2c_sda          // Physical I2C SDA (PIN_A8)
);

    localparam [6:0] WM8731_I2C_ADDR = 7'h1A; // 0011010b

    // Configuration Register ROM (Address [6:0] + 9-bit Data = 16 bits)
    // WM8731 expects 2 bytes after device address:
    // Byte 1: {Reg_Addr[6:0], Data[8]}
    // Byte 2: Data[7:0]
    localparam TOTAL_REGS = 10;
    wire [15:0] config_rom [0:TOTAL_REGS-1];
    assign config_rom[0] = {7'd0, 9'h01F}; // Left Line In: +12dB boost, unmute (optimized for laptop/phone output)
    assign config_rom[1] = {7'd1, 9'h01F}; // Right Line In: +12dB boost, unmute (optimized for laptop/phone output)
    assign config_rom[2] = {7'd2, 9'h079}; // Left HP: 0dB
    assign config_rom[3] = {7'd3, 9'h079}; // Right HP: 0dB
    assign config_rom[4] = {7'd4, 9'h012}; // Analogue path: Line to ADC, DAC unmute
    assign config_rom[5] = {7'd5, 9'h000}; // Digital path: Clear mute, normal filter
    assign config_rom[6] = {7'd6, 9'h000}; // Power down: Power on all blocks
    assign config_rom[7] = {7'd7, 9'h042}; // Format: I2S mode, 16-bit, slave
    assign config_rom[8] = {7'd8, 9'h000}; // Sample rate: Normal mode, 256fs (48kHz)
    assign config_rom[9] = {7'd9, 9'h001}; // Active: Activate interface

    // I2C Master Instantiation
    reg        i2c_start;
    reg  [2:0] i2c_cmd;
    reg  [7:0] i2c_din;
    wire [7:0] i2c_dout;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_nack;

    i2c_master #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(I2C_FREQ_HZ)
    ) u_i2c (
        .clk(clk),
        .rst(rst),
        .cmd_start(i2c_start),
        .cmd_type(i2c_cmd),
        .din(i2c_din),
        .dout(i2c_dout),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_nack),
        .scl(i2c_scl),
        .sda(i2c_sda)
    );

    // State machine to write (ADDR, BYTE1, BYTE2, STOP) for each of the 10 registers
    localparam [3:0]
        S_IDLE           = 4'd0,
        S_START_DEV_CMD  = 4'd1,
        S_START_DEV_WAIT = 4'd2,
        S_WRITE_B1_CMD   = 4'd3,
        S_WRITE_B1_WAIT  = 4'd4,
        S_WRITE_B2_CMD   = 4'd5,
        S_WRITE_B2_WAIT  = 4'd6,
        S_STOP_CMD       = 4'd7,
        S_STOP_WAIT      = 4'd8,
        S_DONE           = 4'd9;

    reg [3:0] state;
    reg [3:0] reg_idx;
    wire [15:0] cur_reg = config_rom[reg_idx];

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            reg_idx      <= 4'd0;
            config_done  <= 1'b0;
            config_error <= 1'b0;
            i2c_start    <= 1'b0;
            i2c_cmd      <= 3'd0;
            i2c_din      <= 8'd0;
        end else begin
            i2c_start <= 1'b0; // Default pulse low

            case (state)
                S_IDLE: begin
                    config_done  <= 1'b0;
                    config_error <= 1'b0;
                    reg_idx      <= 4'd0;
                    if (start) begin
                        state <= S_START_DEV_CMD;
                    end
                end

                S_START_DEV_CMD: begin
                    i2c_cmd   <= 3'b000; // CMD_START_W
                    i2c_din   <= {WM8731_I2C_ADDR, 1'b0};
                    i2c_start <= 1'b1;
                    state     <= S_START_DEV_WAIT;
                end

                S_START_DEV_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            config_error <= 1'b1;
                            state        <= S_STOP_CMD;
                        end else begin
                            state <= S_WRITE_B1_CMD;
                        end
                    end
                end

                S_WRITE_B1_CMD: begin
                    i2c_cmd   <= 3'b010; // CMD_WRITE
                    i2c_din   <= cur_reg[15:8];
                    i2c_start <= 1'b1;
                    state     <= S_WRITE_B1_WAIT;
                end

                S_WRITE_B1_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            config_error <= 1'b1;
                            state        <= S_STOP_CMD;
                        end else begin
                            state <= S_WRITE_B2_CMD;
                        end
                    end
                end

                S_WRITE_B2_CMD: begin
                    i2c_cmd   <= 3'b010; // CMD_WRITE
                    i2c_din   <= cur_reg[7:0];
                    i2c_start <= 1'b1;
                    state     <= S_WRITE_B2_WAIT;
                end

                S_WRITE_B2_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            config_error <= 1'b1;
                        end
                        state <= S_STOP_CMD;
                    end
                end

                S_STOP_CMD: begin
                    i2c_cmd   <= 3'b101; // CMD_STOP
                    i2c_start <= 1'b1;
                    state     <= S_STOP_WAIT;
                end

                S_STOP_WAIT: begin
                    if (i2c_done) begin
                        if (config_error) begin
                            state <= S_IDLE; // Stop on error
                        end else if (reg_idx == TOTAL_REGS - 1) begin
                            state <= S_DONE;
                        end else begin
                            reg_idx <= reg_idx + 1'b1;
                            state   <= S_START_DEV_CMD;
                        end
                    end
                end

                S_DONE: begin
                    config_done <= 1'b1;
                    if (start) begin
                        state        <= S_START_DEV_CMD;
                        reg_idx      <= 4'd0;
                        config_done  <= 1'b0;
                        config_error <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
