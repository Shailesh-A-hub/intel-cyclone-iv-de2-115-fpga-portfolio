//=============================================================================
// Testbench: tb_vga_timing_controller
// Description: Self-checking testbench for 640x480 @ 60Hz VGA timing controller.
//=============================================================================

`timescale 1ns / 1ps

module tb_vga_timing_controller;

    reg clk;
    reg rst;

    wire vga_clk;
    wire vga_hs;
    wire vga_vs;
    wire vga_blank_n;
    wire vga_sync_n;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_area;
    wire pixel_tick;

    vga_timing_controller dut (
        .clk_50mhz(clk),
        .rst(rst),
        .vga_clk(vga_clk),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_blank_n(vga_blank_n),
        .vga_sync_n(vga_sync_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .active_area(active_area),
        .pixel_tick(pixel_tick)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer h_pixels = 0;
    integer v_lines = 0;
    integer active_pixels_line0 = 0;

    initial begin
        clk = 0;
        rst = 1;
        #45;
        rst = 0;

        // Count pixel ticks in 1 full line (800 pixels)
        while (h_pixels < 800) begin
            @(posedge clk);
            if (pixel_tick) begin
                h_pixels = h_pixels + 1;
                if (active_area) begin
                    active_pixels_line0 = active_pixels_line0 + 1;
                end
            end
        end

        // Verify exactly 640 active pixels in visible region
        if (active_pixels_line0 !== 640) begin
            $display("ERROR: Expected 640 active pixels per line, observed %0d", active_pixels_line0);
            errors = errors + 1;
        end else begin
            $display("INFO: Verified 640 active display pixels out of 800 total line pixels");
        end

        // Verify composite sync tied high
        if (vga_sync_n !== 1'b1) begin
            $display("ERROR: vga_sync_n not tied high");
            errors = errors + 1;
        end

        #100;
        if (errors == 0) begin
            $display("=== TB_VGA_TIMING_CONTROLLER: ALL TESTS PASSED ===");
            $finish;
        end else begin
            $display("=== TB_VGA_TIMING_CONTROLLER: FAILED with %0d errors ===", errors);
            $finish;
        end
    end

endmodule
