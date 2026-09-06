//=============================================================================
// Module: apds9960_i2c_driver
// Description: Hardware I2C driver for Broadcom / Avago APDS-9960 RGB and
//              gesture sensor. Performs power-up sequencing, device ID check,
//              gesture engine register configuration, and continuous FIFO
//              polling to stream directional photodiode datasets (U, D, L, R).
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module apds9960_i2c_driver #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000,
    parameter integer SIMULATION  = 0
)(
    input  wire        clk,
    input  wire        reset_n,

    // Hardware status & diagnostics
    output reg         init_done,
    output reg         device_ready,
    output reg  [7:0]  device_id,
    output reg         i2c_error,
    output reg  [3:0]  state_dbg,

    // Continuous gesture sample stream
    output reg  [7:0]  raw_u,
    output reg  [7:0]  raw_d,
    output reg  [7:0]  raw_l,
    output reg  [7:0]  raw_r,
    output reg         sample_valid,

    // External interrupt pin (optional active-low)
    input  wire        apds_int_n,

    // Physical I2C open-drain lines
    inout  wire        scl,
    inout  wire        sda
);

    // APDS-9960 7-bit I2C Address = 0x39
    localparam [6:0] APDS_I2C_ADDR = 7'h39;
    localparam [7:0] I2C_ADDR_W    = {APDS_I2C_ADDR, 1'b0}; // 0x72
    localparam [7:0] I2C_ADDR_R    = {APDS_I2C_ADDR, 1'b1}; // 0x73

    // Sub-commands for i2c_master
    localparam [2:0]
        CMD_START_W   = 3'b000,
        CMD_START_R   = 3'b001,
        CMD_WRITE     = 3'b010,
        CMD_READ_ACK  = 3'b011,
        CMD_READ_NACK = 3'b100,
        CMD_STOP      = 3'b101;

    // Registers in APDS-9960
    localparam [7:0] REG_ENABLE  = 8'h80;
    localparam [7:0] REG_ID      = 8'h92;
    localparam [7:0] REG_GPENTH  = 8'hA0;
    localparam [7:0] REG_GEXTH   = 8'hA1;
    localparam [7:0] REG_GCONF2  = 8'hA2;
    localparam [7:0] REG_GPULSE  = 8'hA9;
    localparam [7:0] REG_GCONF3  = 8'hAA;
    localparam [7:0] REG_GCONF4  = 8'hAB;
    localparam [7:0] REG_GSTATUS = 8'hAF;
    localparam [7:0] REG_GFIFO_U = 8'hFC;

    // Wait timers
    localparam integer DELAY_PWR_CYCLES = (SIMULATION) ? 1_000 : (CLK_FREQ_HZ / 100); // 10ms
    localparam integer POLL_INTERVAL    = (SIMULATION) ? 500   : (CLK_FREQ_HZ / 200); // 5ms (200 Hz)

    // FSM States
    localparam [3:0]
        ST_RESET         = 4'd0,
        ST_DELAY_START   = 4'd1,
        ST_READ_ID_CMD   = 4'd2,
        ST_CONFIG_STEP   = 4'd3,
        ST_POLL_WAIT     = 4'd4,
        ST_READ_STATUS   = 4'd5,
        ST_READ_FIFO     = 4'd6,
        ST_SAMPLE_LATCH  = 4'd7,
        ST_ERROR_HOLD    = 4'd8;

    reg [3:0] state;
    reg [2:0] sub_step;
    reg [3:0] config_idx;
    reg [23:0] timer_cnt;

    // Micro-sequence registers for I2C Master control
    reg        i2c_start;
    reg  [2:0] i2c_cmd;
    reg  [7:0] i2c_din;
    wire [7:0] i2c_dout;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_ack_err;

    // Instantiate common I2C Master
    i2c_master #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(I2C_FREQ_HZ)
    ) u_i2c_master (
        .clk(clk),
        .rst(!reset_n),
        .cmd_start(i2c_start),
        .cmd_type(i2c_cmd),
        .din(i2c_din),
        .dout(i2c_dout),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_ack_err),
        .scl(scl),
        .sda(sda)
    );

    // Initialization Table: {Register Address, Write Value}
    reg [7:0] reg_addr_lut [0:8];
    reg [7:0] reg_val_lut  [0:8];

    initial begin
        reg_addr_lut[0] = REG_ENABLE; reg_val_lut[0] = 8'h01; // PON = 1
        reg_addr_lut[1] = REG_GPENTH; reg_val_lut[1] = 8'h28; // Gesture Enter Threshold = 40
        reg_addr_lut[2] = REG_GEXTH;  reg_val_lut[2] = 8'h1E; // Gesture Exit Threshold = 30
        reg_addr_lut[3] = REG_GCONF2; reg_val_lut[3] = 8'h40; // GGAIN = 4x, GLDRIVE = 100mA
        reg_addr_lut[4] = REG_GPULSE; reg_val_lut[4] = 8'hC9; // 32us length, 10 pulses
        reg_addr_lut[5] = REG_GCONF3; reg_val_lut[5] = 8'h00; // All 4 photodiodes enabled
        reg_addr_lut[6] = REG_GCONF4; reg_val_lut[6] = 8'h01; // GMODE = 1
        reg_addr_lut[7] = REG_ENABLE; reg_val_lut[7] = 8'h45; // PON | PEN | GEN = 1
        reg_addr_lut[8] = 8'h00;      reg_val_lut[8] = 8'h00; // Terminator
    end

    // Buffer for 4 bytes read from FIFO
    reg [7:0] byte_u, byte_d, byte_l, byte_r;
    reg [7:0] gstatus_reg;

    always @(posedge clk) begin
        if (!reset_n) begin
            state           <= ST_RESET;
            sub_step        <= 3'd0;
            config_idx      <= 4'd0;
            timer_cnt       <= 24'd0;
            init_done       <= 1'b0;
            device_ready    <= 1'b0;
            device_id       <= 8'h00;
            i2c_error       <= 1'b0;
            state_dbg       <= 4'd0;
            raw_u           <= 8'd0;
            raw_d           <= 8'd0;
            raw_l           <= 8'd0;
            raw_r           <= 8'd0;
            sample_valid    <= 1'b0;
            i2c_start       <= 1'b0;
            i2c_cmd         <= 3'd0;
            i2c_din         <= 8'd0;
            byte_u          <= 8'd0;
            byte_d          <= 8'd0;
            byte_l          <= 8'd0;
            byte_r          <= 8'd0;
            gstatus_reg     <= 8'd0;
        end else begin
            sample_valid <= 1'b0; // Default pulse
            i2c_start    <= 1'b0; // Default pulse
            state_dbg    <= state;

            case (state)
                ST_RESET: begin
                    timer_cnt    <= 24'd0;
                    init_done    <= 1'b0;
                    device_ready <= 1'b0;
                    i2c_error    <= 1'b0;
                    sub_step     <= 3'd0;
                    config_idx   <= 4'd0;
                    state        <= ST_DELAY_START;
                end

                ST_DELAY_START: begin
                    if (timer_cnt >= DELAY_PWR_CYCLES) begin
                        timer_cnt <= 24'd0;
                        state     <= ST_READ_ID_CMD;
                        sub_step  <= 3'd0;
                    end else begin
                        timer_cnt <= timer_cnt + 1'b1;
                    end
                end

                // Step 1: Read Device ID (Reg 0x92)
                ST_READ_ID_CMD: begin
                    case (sub_step)
                        3'd0: begin // START + ADDR_W
                            if (!i2c_busy) begin
                                i2c_cmd   <= CMD_START_W;
                                i2c_din   <= I2C_ADDR_W;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd1;
                            end
                        end
                        3'd1: begin
                            if (i2c_done) begin
                                if (i2c_ack_err) begin
                                    i2c_error <= 1'b1;
                                    state     <= ST_ERROR_HOLD;
                                end else begin
                                    // Send Register Pointer (0x92)
                                    i2c_cmd   <= CMD_WRITE;
                                    i2c_din   <= REG_ID;
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd2;
                                end
                            end
                        end
                        3'd2: begin
                            if (i2c_done) begin
                                if (i2c_ack_err) begin
                                    i2c_error <= 1'b1;
                                    state     <= ST_ERROR_HOLD;
                                end else begin
                                    // RESTART + ADDR_R
                                    i2c_cmd   <= CMD_START_R;
                                    i2c_din   <= I2C_ADDR_R;
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd3;
                                end
                            end
                        end
                        3'd3: begin
                            if (i2c_done) begin
                                // Read Data with NACK
                                i2c_cmd   <= CMD_READ_NACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd4;
                            end
                        end
                        3'd4: begin
                            if (i2c_done) begin
                                device_id <= i2c_dout;
                                // STOP condition
                                i2c_cmd   <= CMD_STOP;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd5;
                            end
                        end
                        3'd5: begin
                            if (i2c_done) begin
                                // Validate APDS-9960 ID (0xAB, 0x9C, 0xA8 are common silicon revisions)
                                // In simulation accept any non-zero or 0xAB
                                if (device_id == 8'hAB || device_id == 8'h9C || device_id == 8'hA8 || SIMULATION) begin
                                    device_ready <= 1'b1;
                                    config_idx   <= 4'd0;
                                    sub_step     <= 3'd0;
                                    state        <= ST_CONFIG_STEP;
                                end else begin
                                    i2c_error <= 1'b1;
                                    state     <= ST_ERROR_HOLD;
                                end
                            end
                        end
                        default: sub_step <= 3'd0;
                    endcase
                end

                // Step 2: Configure All Registers in Sequence
                ST_CONFIG_STEP: begin
                    if (config_idx >= 4'd8) begin
                        init_done <= 1'b1;
                        state     <= ST_POLL_WAIT;
                        timer_cnt <= 24'd0;
                        sub_step  <= 3'd0;
                    end else begin
                        case (sub_step)
                            3'd0: begin // START + ADDR_W
                                if (!i2c_busy) begin
                                    i2c_cmd   <= CMD_START_W;
                                    i2c_din   <= I2C_ADDR_W;
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd1;
                                end
                            end
                            3'd1: begin // Register Address
                                if (i2c_done) begin
                                    i2c_cmd   <= CMD_WRITE;
                                    i2c_din   <= reg_addr_lut[config_idx];
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd2;
                                end
                            end
                            3'd2: begin // Register Data
                                if (i2c_done) begin
                                    i2c_cmd   <= CMD_WRITE;
                                    i2c_din   <= reg_val_lut[config_idx];
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd3;
                                end
                            end
                            3'd3: begin // STOP
                                if (i2c_done) begin
                                    i2c_cmd   <= CMD_STOP;
                                    i2c_start <= 1'b1;
                                    sub_step  <= 3'd4;
                                end
                            end
                            3'd4: begin
                                if (i2c_done) begin
                                    config_idx <= config_idx + 1'b1;
                                    sub_step   <= 3'd0;
                                end
                            end
                            default: sub_step <= 3'd0;
                        endcase
                    end
                end

                // Step 3: Wait Poll Period
                ST_POLL_WAIT: begin
                    if (timer_cnt >= POLL_INTERVAL) begin
                        timer_cnt <= 24'd0;
                        sub_step  <= 3'd0;
                        state     <= ST_READ_STATUS;
                    end else begin
                        timer_cnt <= timer_cnt + 1'b1;
                    end
                end

                // Step 4: Query GSTATUS (0xAF) to see if FIFO has valid gesture data
                ST_READ_STATUS: begin
                    case (sub_step)
                        3'd0: begin
                            if (!i2c_busy) begin
                                i2c_cmd   <= CMD_START_W;
                                i2c_din   <= I2C_ADDR_W;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd1;
                            end
                        end
                        3'd1: begin
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_WRITE;
                                i2c_din   <= REG_GSTATUS;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd2;
                            end
                        end
                        3'd2: begin
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_START_R;
                                i2c_din   <= I2C_ADDR_R;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd3;
                            end
                        end
                        3'd3: begin
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_READ_NACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd4;
                            end
                        end
                        3'd4: begin
                            if (i2c_done) begin
                                gstatus_reg <= i2c_dout;
                                i2c_cmd     <= CMD_STOP;
                                i2c_start   <= 1'b1;
                                sub_step    <= 3'd5;
                            end
                        end
                        3'd5: begin
                            if (i2c_done) begin
                                // GVALID is bit 0 of GSTATUS
                                if (gstatus_reg[0] || (SIMULATION && gstatus_reg != 8'h00)) begin
                                    sub_step <= 3'd0;
                                    state    <= ST_READ_FIFO;
                                end else begin
                                    state <= ST_POLL_WAIT;
                                end
                            end
                        end
                        default: sub_step <= 3'd0;
                    endcase
                end

                // Step 5: Read 4 consecutive bytes from FIFO (U, D, L, R)
                ST_READ_FIFO: begin
                    case (sub_step)
                        3'd0: begin // START + ADDR_W
                            if (!i2c_busy) begin
                                i2c_cmd   <= CMD_START_W;
                                i2c_din   <= I2C_ADDR_W;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd1;
                            end
                        end
                        3'd1: begin // Pointer to GFIFO_U (0xFC)
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_WRITE;
                                i2c_din   <= REG_GFIFO_U;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd2;
                            end
                        end
                        3'd2: begin // RESTART + ADDR_R
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_START_R;
                                i2c_din   <= I2C_ADDR_R;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd3;
                            end
                        end
                        3'd3: begin // Read Byte 0: U (ACK)
                            if (i2c_done) begin
                                i2c_cmd   <= CMD_READ_ACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd4;
                            end
                        end
                        3'd4: begin // Store U, Read Byte 1: D (ACK)
                            if (i2c_done) begin
                                byte_u    <= i2c_dout;
                                i2c_cmd   <= CMD_READ_ACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd5;
                            end
                        end
                        3'd5: begin // Store D, Read Byte 2: L (ACK)
                            if (i2c_done) begin
                                byte_d    <= i2c_dout;
                                i2c_cmd   <= CMD_READ_ACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd6;
                            end
                        end
                        3'd6: begin // Store L, Read Byte 3: R (NACK)
                            if (i2c_done) begin
                                byte_l    <= i2c_dout;
                                i2c_cmd   <= CMD_READ_NACK;
                                i2c_start <= 1'b1;
                                sub_step  <= 3'd7;
                            end
                        end
                        3'd7: begin // Store R, issue STOP
                            if (i2c_done) begin
                                byte_r    <= i2c_dout;
                                i2c_cmd   <= CMD_STOP;
                                i2c_start <= 1'b1;
                                state     <= ST_SAMPLE_LATCH;
                            end
                        end
                        default: sub_step <= 3'd0;
                    endcase
                end

                // Step 6: Latch samples and emit strobe
                ST_SAMPLE_LATCH: begin
                    if (i2c_done) begin
                        raw_u        <= byte_u;
                        raw_d        <= byte_d;
                        raw_l        <= byte_l;
                        raw_r        <= byte_r;
                        sample_valid <= 1'b1;
                        state        <= ST_POLL_WAIT;
                        timer_cnt    <= 24'd0;
                    end
                end

                // Error hold: retry after delay
                ST_ERROR_HOLD: begin
                    if (timer_cnt >= (DELAY_PWR_CYCLES * 2)) begin
                        state     <= ST_RESET;
                        timer_cnt <= 24'd0;
                    end else begin
                        timer_cnt <= timer_cnt + 1'b1;
                    end
                end

                default: state <= ST_RESET;
            endcase
        end
    end

endmodule
