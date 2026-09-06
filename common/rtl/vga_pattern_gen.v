//=============================================================================
// Module: vga_pattern_gen
// Description: Multi-pattern VGA color generator (color bars, crosshatch grid,
//              solid shades) with overlay capability for spectrum visualizers.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module vga_pattern_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        active_area,
    input  wire [1:0]  pattern_sel,   // 00 = Color Bars, 01 = Grid, 10 = Border/Box, 11 = Gradient
    output reg  [7:0]  vga_r,
    output reg  [7:0]  vga_g,
    output reg  [7:0]  vga_b
);

    always @(posedge clk) begin
        if (rst || !active_area) begin
            vga_r <= 8'h00;
            vga_g <= 8'h00;
            vga_b <= 8'h00;
        end else begin
            case (pattern_sel)
                // 8 standard color bars across 640 horizontal pixels (80 pixels per bar)
                2'b00: begin
                    case (pixel_x / 80)
                        3'd0: {vga_r, vga_g, vga_b} <= {8'hFF, 8'hFF, 8'hFF}; // White
                        3'd1: {vga_r, vga_g, vga_b} <= {8'hFF, 8'hFF, 8'h00}; // Yellow
                        3'd2: {vga_r, vga_g, vga_b} <= {8'h00, 8'hFF, 8'hFF}; // Cyan
                        3'd3: {vga_r, vga_g, vga_b} <= {8'h00, 8'hFF, 8'h00}; // Green
                        3'd4: {vga_r, vga_g, vga_b} <= {8'hFF, 8'h00, 8'hFF}; // Magenta
                        3'd5: {vga_r, vga_g, vga_b} <= {8'hFF, 8'h00, 8'h00}; // Red
                        3'd6: {vga_r, vga_g, vga_b} <= {8'h00, 8'h00, 8'hFF}; // Blue
                        3'd7: {vga_r, vga_g, vga_b} <= {8'h00, 8'h00, 8'h00}; // Black
                        default: {vga_r, vga_g, vga_b} <= 24'h0;
                    endcase
                end

                // Crosshatch 32x32 pixel grid
                2'b01: begin
                    if ((pixel_x[4:0] == 5'd0) || (pixel_y[4:0] == 5'd0)) begin
                        {vga_r, vga_g, vga_b} <= {8'hFF, 8'hFF, 8'hFF}; // White grid lines
                    end else begin
                        {vga_r, vga_g, vga_b} <= {8'h10, 8'h18, 8'h24}; // Dark slate background
                    end
                end

                // Border frame with centered title zone
                2'b10: begin
                    if (pixel_x < 4 || pixel_x >= 636 || pixel_y < 4 || pixel_y >= 476) begin
                        {vga_r, vga_g, vga_b} <= {8'h00, 8'hFF, 8'hC8}; // Teal border
                    end else if (pixel_y < 60) begin
                        {vga_r, vga_g, vga_b} <= {8'h00, 8'h20, 8'h40}; // Header banner
                    end else begin
                        {vga_r, vga_g, vga_b} <= {8'h0A, 8'h0E, 8'h17}; // Dark canvas
                    end
                end

                // Dynamic horizontal color gradient
                2'b11: begin
                    vga_r <= pixel_x[8:1];
                    vga_g <= pixel_y[8:1];
                    vga_b <= 8'h80;
                end
            endcase
        end
    end

endmodule
