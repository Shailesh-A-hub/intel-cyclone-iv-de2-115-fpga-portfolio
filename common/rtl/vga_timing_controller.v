//=============================================================================
// Module: vga_timing_controller
// Description: Standard 640x480 @ 60Hz VGA timing generator for the ADV7123
//              video DAC on the DE2-115 board. Produces horizontal/vertical sync,
//              active blanking, and (X, Y) pixel coordinates.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module vga_timing_controller (
    input  wire       clk_50mhz,    // 50 MHz on-board system clock (PIN_Y2)
    input  wire       rst,          // Synchronous active-high reset
    output reg        vga_clk,      // 25 MHz pixel clock output to ADV7123 (PIN_A12)
    output reg        vga_hs,       // Horizontal sync (active low)
    output reg        vga_vs,       // Vertical sync (active low)
    output reg        vga_blank_n,  // Direct DAC blanking (1 = active display, 0 = blank)
    output wire       vga_sync_n,   // Composite sync (tied high for standard VGA)
    output reg  [9:0] pixel_x,      // Active horizontal coordinate (0 - 639)
    output reg  [9:0] pixel_y,      // Active vertical coordinate (0 - 479)
    output reg        active_area,  // 1 when electron beam is within visible display
    output reg        pixel_tick    // Single-cycle strobe at 25 MHz pixel rate
);

    assign vga_sync_n = 1'b1; // Normal separate sync mode

    // 640x480 @ 60 Hz Timing Parameters
    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 16;
    localparam integer H_SYNC   = 96;
    localparam integer H_BACK   = 48;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK; // 800

    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT  = 10;
    localparam integer V_SYNC   = 2;
    localparam integer V_BACK   = 33;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK; // 525

    // Pixel clock divider (50 MHz / 2 = 25 MHz)
    reg clk_div;
    always @(posedge clk_50mhz) begin
        if (rst) begin
            clk_div    <= 1'b0;
            vga_clk    <= 1'b0;
            pixel_tick <= 1'b0;
        end else begin
            clk_div    <= ~clk_div;
            vga_clk    <= ~vga_clk;
            pixel_tick <= ~clk_div; // Strobe once every 2 system clock cycles
        end
    end

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk_50mhz) begin
        if (rst) begin
            h_count     <= 10'd0;
            v_count     <= 10'd0;
            vga_hs      <= 1'b1;
            vga_vs      <= 1'b1;
            vga_blank_n <= 1'b0;
            active_area <= 1'b0;
            pixel_x     <= 10'd0;
            pixel_y     <= 10'd0;
        end else if (pixel_tick) begin
            // Horizontal counter
            if (h_count >= H_TOTAL - 1) begin
                h_count <= 10'd0;
                // Vertical counter
                if (v_count >= V_TOTAL - 1) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 1'b1;
                end
            end else begin
                h_count <= h_count + 1'b1;
            end

            // Horizontal sync: active-low between (H_ACTIVE + H_FRONT) and (H_ACTIVE + H_FRONT + H_SYNC - 1)
            vga_hs <= ~((h_count >= H_ACTIVE + H_FRONT) && (h_count < H_ACTIVE + H_FRONT + H_SYNC));

            // Vertical sync: active-low between (V_ACTIVE + V_FRONT) and (V_ACTIVE + V_FRONT + V_SYNC - 1)
            vga_vs <= ~((v_count >= V_ACTIVE + V_FRONT) && (v_count < V_ACTIVE + V_FRONT + V_SYNC));

            // Active display region and blanking
            if ((h_count < H_ACTIVE) && (v_count < V_ACTIVE)) begin
                active_area <= 1'b1;
                vga_blank_n <= 1'b1;
                pixel_x     <= h_count;
                pixel_y     <= v_count;
            end else begin
                active_area <= 1'b0;
                vga_blank_n <= 1'b0;
                pixel_x     <= 10'd0;
                pixel_y     <= 10'd0;
            end
        end
    end

endmodule
