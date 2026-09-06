// ============================================================================
// DE2-115 5-Project FPGA Portfolio
// Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
// File Name:   risk_engine_q8_8.v
// Description: Fixed-Point Q0.8 Weighted Sensor Fusion Risk Scoring Engine.
//              Calculates composite risk score:
//                RiskScore = Wg*Gas + Wt*Temp + Wf*Flame + Wh*Hum
//              Converts scaled products to 0 - 100 integer range and classifies
//              into SAFE, CAUTION, DANGER, and FAULT operational regions.
// Standard:    Verilog-2001 (Purely Synchronous, Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module risk_engine_q8_8 #(
    parameter THRESH_SAFE_MAX    = 7'd34,  // 0 - 34: SAFE
    parameter THRESH_CAUTION_MAX = 7'd69   // 35 - 69: CAUTION, 70 - 100: DANGER
)(
    input  wire        clk,
    input  wire        rst_n,

    // Normalized Inputs (0 - 255)
    input  wire        norm_valid_in,
    input  wire [7:0]  norm_gas,
    input  wire [7:0]  norm_temp,
    input  wire [7:0]  norm_flame,
    input  wire [7:0]  norm_hum,
    input  wire [4:0]  sensor_fault_mask_in,

    // Configurable Q0.8 Weights (Sum should equal 256 for 1.000)
    // Default weights: Flame=102 (40%), Gas=77 (30%), Temp=51 (20%), Hum=26 (10%)
    input  wire [7:0]  weight_gas,
    input  wire [7:0]  weight_temp,
    input  wire [7:0]  weight_flame,
    input  wire [7:0]  weight_hum,

    // Risk Engine Outputs
    output reg  [6:0]  risk_score,          // 0 to 100 decimal integer
    output reg  [7:0]  risk_intermediate,   // 0 to 255 Q8.0 internal value
    output reg  [1:0]  risk_level,          // 00=SAFE, 01=CAUTION, 10=DANGER, 11=FAULT
    output reg  [1:0]  dominant_hazard,     // 00=None, 01=Flame, 10=Gas, 11=Temp
    output reg  [4:0]  fault_code,
    output reg         risk_valid_out
);

    // Operational Level Encoding
    localparam [1:0]
        LVL_SAFE    = 2'b00,
        LVL_CAUTION = 2'b01,
        LVL_DANGER  = 2'b10,
        LVL_FAULT   = 2'b11;

    // Dominant Hazard Encoding
    localparam [1:0]
        HAZ_NONE  = 2'b00,
        HAZ_FLAME = 2'b01,
        HAZ_GAS   = 2'b10,
        HAZ_TEMP  = 2'b11;

    // ------------------------------------------------------------------------
    // Pipeline Stage 1: Multiplication and Weighted Summation
    // ------------------------------------------------------------------------
    reg        st1_valid;
    reg [4:0]  st1_fault;
    reg [15:0] prod_gas;
    reg [15:0] prod_temp;
    reg [15:0] prod_flame;
    reg [15:0] prod_hum;
    reg [16:0] sum_weighted; // Up to 65,280

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st1_valid    <= 1'b0;
            st1_fault    <= 5'd0;
            prod_gas     <= 16'd0;
            prod_temp    <= 16'd0;
            prod_flame   <= 16'd0;
            prod_hum     <= 16'd0;
            sum_weighted <= 17'd0;
        end else begin
            st1_valid <= norm_valid_in;
            st1_fault <= sensor_fault_mask_in;

            prod_gas   <= weight_gas   * norm_gas;
            prod_temp  <= weight_temp  * norm_temp;
            prod_flame <= weight_flame * norm_flame;
            prod_hum   <= weight_hum   * norm_hum;

            sum_weighted <= (weight_gas   * norm_gas) +
                            (weight_temp  * norm_temp) +
                            (weight_flame * norm_flame) +
                            (weight_hum   * norm_hum);
        end
    end

    // ------------------------------------------------------------------------
    // Pipeline Stage 2: Scaling to 0-100 and Threshold Classification
    // ------------------------------------------------------------------------
    // Formula: (sum_weighted * 100 + 32640) / 65280
    // sum_weighted max is 65280.
    // 65280 * 100 + 32640 = 6,560,640 (23 bits)
    wire [23:0] scaled_numer = (sum_weighted * 24'd100) + 24'd32640;
    wire [23:0] raw_score_100 = scaled_numer / 24'd65280;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            risk_valid_out    <= 1'b0;
            risk_score        <= 7'd0;
            risk_intermediate <= 8'd0;
            risk_level        <= LVL_SAFE;
            dominant_hazard   <= HAZ_NONE;
            fault_code        <= 5'd0;
        end else begin
            risk_valid_out <= st1_valid;
            fault_code     <= st1_fault;

            // Clamping intermediate 0-255
            risk_intermediate <= (sum_weighted[16:8] > 8'd255) ? 8'd255 : sum_weighted[15:8];

            // Risk Score 0-100
            if (raw_score_100 > 24'd100)
                risk_score <= 7'd100;
            else
                risk_score <= raw_score_100[6:0];

            // Dominant Hazard Evaluation
            if (prod_flame >= prod_gas && prod_flame >= prod_temp && prod_flame > 16'd500)
                dominant_hazard <= HAZ_FLAME;
            else if (prod_gas >= prod_flame && prod_gas >= prod_temp && prod_gas > 16'd500)
                dominant_hazard <= HAZ_GAS;
            else if (prod_temp >= prod_flame && prod_temp >= prod_gas && prod_temp > 16'd500)
                dominant_hazard <= HAZ_TEMP;
            else
                dominant_hazard <= HAZ_NONE;

            // Level Classification with Fault Override
            if (st1_fault != 5'd0) begin
                risk_level <= LVL_FAULT;
            end else if (raw_score_100 <= THRESH_SAFE_MAX) begin
                risk_level <= LVL_SAFE;
            end else if (raw_score_100 <= THRESH_CAUTION_MAX) begin
                risk_level <= LVL_CAUTION;
            end else begin
                risk_level <= LVL_DANGER;
            end
        end
    end

endmodule
