//=============================================================================
// Module: reset_synchronizer
// Description: Asynchronous assert, synchronous de-assert reset synchronizer.
//              Prevents metastability issues on reset release across flip-flops.
// Standard: IEEE 1364-2001 Verilog
// Board: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
//=============================================================================

`timescale 1ns / 1ps

module reset_synchronizer #(
    parameter STAGES = 2,           // Number of synchronization flip-flops (>=2)
    parameter ACTIVE_LOW_IN = 1,    // 1 if async_rst_in is active-low (e.g. KEY[0])
    parameter ACTIVE_LOW_OUT = 0    // 1 if sync_rst_out should be active-low
)(
    input  wire clk,                // Destination clock domain (e.g. 50 MHz)
    input  wire async_rst_in,       // Raw asynchronous reset input from pin
    output wire sync_rst_out        // Synchronously released reset output
);

    // Internal active-high asynchronous reset condition
    wire rst_raw_active = ACTIVE_LOW_IN ? (~async_rst_in) : async_rst_in;

    // Shift register for synchronization
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_AUTO" *)
    reg [STAGES-1:0] sync_reg;

    always @(posedge clk or posedge rst_raw_active) begin
        if (rst_raw_active) begin
            sync_reg <= {STAGES{1'b1}}; // Assert immediately on async reset
        end else begin
            sync_reg <= {sync_reg[STAGES-2:0], 1'b0}; // De-assert synchronously
        end
    end

    // Output polarity assignment
    assign sync_rst_out = ACTIVE_LOW_OUT ? (~sync_reg[STAGES-1]) : sync_reg[STAGES-1];

endmodule
