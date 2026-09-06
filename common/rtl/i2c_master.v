//=============================================================================
// Module: i2c_master
// Description: Robust single-master I2C controller supporting 100 kHz Standard
//              and 400 kHz Fast modes. Provides command-driven byte transactions,
//              start/restart/stop conditions, and ACK/NACK validation.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module i2c_master #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000
)(
    input  wire       clk,
    input  wire       rst,
    // Control interface
    input  wire       cmd_start,       // Execute commanded operation
    input  wire [2:0] cmd_type,        // 000: START+ADDR_W, 001: START+ADDR_R, 010: WRITE, 011: READ_ACK, 100: READ_NACK, 101: STOP
    input  wire [7:0] din,             // Address or data byte to transmit
    output reg  [7:0] dout,            // Received data byte
    output reg        busy,            // Master busy executing command
    output reg        done,            // 1-cycle pulse upon command completion
    output reg        ack_error,       // 1 if slave NACKed when ACK was expected
    // Physical I2C open-drain lines
    inout  wire       scl,
    inout  wire       sda
);

    // Command encodings
    localparam [2:0]
        CMD_START_W   = 3'b000,
        CMD_START_R   = 3'b001,
        CMD_WRITE     = 3'b010,
        CMD_READ_ACK  = 3'b011,
        CMD_READ_NACK = 3'b100,
        CMD_STOP      = 3'b101;

    // 4 quarter-phase ticks per SCL cycle
    localparam integer QUARTER_PERIOD = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);
    localparam integer Q_CNT_W        = $clog2(QUARTER_PERIOD);

    reg [Q_CNT_W-1:0] q_cnt;
    wire q_tick = (q_cnt >= QUARTER_PERIOD - 1);

    always @(posedge clk) begin
        if (rst) begin
            q_cnt <= {Q_CNT_W{1'b0}};
        end else begin
            if (q_tick) begin
                q_cnt <= {Q_CNT_W{1'b0}};
            end else begin
                q_cnt <= q_cnt + 1'b1;
            end
        end
    end

    // Open-drain output driver controls (1 = release/float line high via pull-up, 0 = pull to GND)
    reg scl_oen;
    reg sda_oen;

    assign scl = scl_oen ? 1'bz : 1'b0;
    assign sda = sda_oen ? 1'bz : 1'b0;

    // Synchronize inputs
    reg sda_sync1, sda_sync2;
    always @(posedge clk) begin
        if (rst) begin
            sda_sync1 <= 1'b1;
            sda_sync2 <= 1'b1;
        end else begin
            sda_sync1 <= sda;
            sda_sync2 <= sda_sync1;
        end
    end

    // FSM State Encoding
    localparam [3:0]
        S_IDLE        = 4'd0,
        S_START_1     = 4'd1,
        S_START_2     = 4'd2,
        S_BIT_LOW     = 4'd3,
        S_BIT_RAISE   = 4'd4,
        S_BIT_HIGH    = 4'd5,
        S_BIT_FALL    = 4'd6,
        S_ACK_LOW     = 4'd7,
        S_ACK_RAISE   = 4'd8,
        S_ACK_HIGH    = 4'd9,
        S_ACK_FALL    = 4'd10,
        S_STOP_1      = 4'd11,
        S_STOP_2      = 4'd12,
        S_STOP_3      = 4'd13;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] tx_shifter;
    reg [7:0] rx_shifter;
    reg [2:0] cur_cmd;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            scl_oen    <= 1'b1; // Float high
            sda_oen    <= 1'b1; // Float high
            busy       <= 1'b0;
            done       <= 1'b0;
            ack_error  <= 1'b0;
            bit_cnt    <= 3'd0;
            tx_shifter <= 8'd0;
            rx_shifter <= 8'd0;
            dout       <= 8'd0;
            cur_cmd    <= 3'd0;
        end else begin
            done <= 1'b0; // Default pulse low

            if (state == S_IDLE) begin
                busy <= 1'b0;
                if (cmd_start) begin
                    busy      <= 1'b1;
                    cur_cmd   <= cmd_type;
                    tx_shifter <= din;
                    ack_error <= 1'b0;
                    case (cmd_type)
                        CMD_START_W, CMD_START_R: begin
                            // Initiate Start condition: SDA falls while SCL high
                            sda_oen <= 1'b1;
                            scl_oen <= 1'b1;
                            state   <= S_START_1;
                        end
                        CMD_WRITE: begin
                            bit_cnt <= 3'd7;
                            state   <= S_BIT_LOW;
                        end
                        CMD_READ_ACK, CMD_READ_NACK: begin
                            bit_cnt <= 3'd7;
                            sda_oen <= 1'b1; // Release SDA for reading
                            state   <= S_BIT_LOW;
                        end
                        CMD_STOP: begin
                            // Stop condition: SDA rises while SCL high
                            sda_oen <= 1'b0;
                            scl_oen <= 1'b0;
                            state   <= S_STOP_1;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
            end else if (q_tick) begin
                case (state)
                    // START Generation
                    S_START_1: begin
                        sda_oen <= 1'b0; // Pull SDA low while SCL is high
                        state   <= S_START_2;
                    end
                    S_START_2: begin
                        scl_oen <= 1'b0; // Pull SCL low to begin clocking bits
                        bit_cnt <= 3'd7;
                        state   <= S_BIT_LOW;
                    end

                    // BIT Transmission / Reception (4-phase SCL cycle)
                    S_BIT_LOW: begin
                        scl_oen <= 1'b0; // SCL low
                        if (cur_cmd == CMD_START_W || cur_cmd == CMD_START_R || cur_cmd == CMD_WRITE) begin
                            sda_oen <= tx_shifter[bit_cnt]; // Drive MSB first
                        end else begin
                            sda_oen <= 1'b1; // Release line to read from slave
                        end
                        state <= S_BIT_RAISE;
                    end

                    S_BIT_RAISE: begin
                        scl_oen <= 1'b1; // Release SCL high
                        state   <= S_BIT_HIGH;
                    end

                    S_BIT_HIGH: begin
                        // Sample SDA on high SCL
                        if (cur_cmd == CMD_READ_ACK || cur_cmd == CMD_READ_NACK) begin
                            rx_shifter[bit_cnt] <= sda_sync2;
                        end
                        state <= S_BIT_FALL;
                    end

                    S_BIT_FALL: begin
                        scl_oen <= 1'b0; // Pull SCL low
                        if (bit_cnt == 3'd0) begin
                            state <= S_ACK_LOW;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                            state   <= S_BIT_LOW;
                        end
                    end

                    // ACK Phase
                    S_ACK_LOW: begin
                        scl_oen <= 1'b0;
                        if (cur_cmd == CMD_READ_ACK) begin
                            sda_oen <= 1'b0; // Master drives ACK (low)
                        end else if (cur_cmd == CMD_READ_NACK) begin
                            sda_oen <= 1'b1; // Master drives NACK (high)
                        end else begin
                            sda_oen <= 1'b1; // Master releases SDA to sample Slave ACK
                        end
                        state <= S_ACK_RAISE;
                    end

                    S_ACK_RAISE: begin
                        scl_oen <= 1'b1; // SCL rises
                        state   <= S_ACK_HIGH;
                    end

                    S_ACK_HIGH: begin
                        // Check ACK from slave during write operations
                        if (cur_cmd == CMD_START_W || cur_cmd == CMD_START_R || cur_cmd == CMD_WRITE) begin
                            if (sda_sync2 == 1'b1) begin
                                ack_error <= 1'b1; // NACK received!
                            end
                        end
                        state <= S_ACK_FALL;
                    end

                    S_ACK_FALL: begin
                        scl_oen <= 1'b0;
                        if (cur_cmd == CMD_READ_ACK || cur_cmd == CMD_READ_NACK) begin
                            dout <= rx_shifter;
                        end
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end

                    // STOP Generation
                    S_STOP_1: begin
                        sda_oen <= 1'b0; // Ensure SDA low
                        scl_oen <= 1'b1; // Bring SCL high
                        state   <= S_STOP_2;
                    end

                    S_STOP_2: begin
                        sda_oen <= 1'b1; // Float SDA high while SCL high (STOP)
                        state   <= S_STOP_3;
                    end

                    S_STOP_3: begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
