//=============================================================================
// Module: vga_spectrum_display
// Description: 640x480 @ 60Hz real-time graphical audio spectrum analyzer for
//              the ADV7123 video DAC. Renders 6 psychoacoustic equalizer bars
//              with dynamic multi-color gradient fills (Green -> Yellow -> Red),
//              persistent peak-hold lines with decay, active noise classification
//              badges, and live peak frequency telemetry.
// Standard: IEEE 1364-2001 Verilog
//=============================================================================

`timescale 1ns / 1ps

module vga_spectrum_display (
    input  wire        clk_50,             // 50 MHz system clock
    input  wire        reset_n,

    // Latched psychoacoustic band energies from extractor
    input  wire [23:0] band0_energy,
    input  wire [23:0] band1_energy,
    input  wire [23:0] band2_energy,
    input  wire [23:0] band3_energy,
    input  wire [23:0] band4_energy,
    input  wire [23:0] band5_energy,
    input  wire [27:0] total_energy,
    input  wire [7:0]  peak_bin_index,
    input  wire [15:0] peak_magnitude,

    // Active classification from noise_classifier
    input  wire [2:0]  class_code,
    input  wire [31:0] class_ascii,
    input  wire [7:0]  confidence_pct,

    // ADV7123 Video DAC Physical Outputs
    output wire        vga_clk,            // 25.175 MHz pixel clock
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output reg  [7:0]  vga_r,
    output reg  [7:0]  vga_g,
    output reg  [7:0]  vga_b
);

    // Instantiate VGA Timing Controller (produces 25 MHz pixel clock internally)
    wire [9:0] pixel_x, pixel_y;
    wire       active_video;
    wire       vsync_wire;

    vga_timing_controller u_vga_timing (
        .clk_50mhz(clk_50),
        .rst(!reset_n),
        .vga_clk(vga_clk),
        .vga_hs(vga_hs),
        .vga_vs(vsync_wire),
        .vga_blank_n(vga_blank_n),
        .vga_sync_n(vga_sync_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .active_area(active_video),
        .pixel_tick()
    );

    assign vga_vs = vsync_wire;

    // Detect frame edge for peak-hold decay (60 Hz tick)
    reg vsync_d;
    wire frame_tick = (vsync_wire && !vsync_d);
    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n)
            vsync_d <= 1'b0;
        else
            vsync_d <= vsync_wire;
    end

    // Scaled Bar Heights (Clamped to 0 - 200 pixels tall)
    // Scale factor: Shift down by 14 bits for clean visual dynamics
    function [7:0] scale_bar;
        input [23:0] eng;
        reg [11:0] val;
        begin
            val = eng[23:12];
            scale_bar = (val > 12'd200) ? 8'd200 : val[7:0];
        end
    endfunction

    wire [7:0] h0 = scale_bar(band0_energy);
    wire [7:0] h1 = scale_bar(band1_energy);
    wire [7:0] h2 = scale_bar(band2_energy);
    wire [7:0] h3 = scale_bar(band3_energy);
    wire [7:0] h4 = scale_bar(band4_energy);
    wire [7:0] h5 = scale_bar(band5_energy);

    // Peak-Hold Registers with slow 60 Hz gravity decay
    reg [7:0] peak0, peak1, peak2, peak3, peak4, peak5;
    reg [3:0] decay_counter;

    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n) begin
            peak0         <= 8'd0;
            peak1         <= 8'd0;
            peak2         <= 8'd0;
            peak3         <= 8'd0;
            peak4         <= 8'd0;
            peak5         <= 8'd0;
            decay_counter <= 4'd0;
        end else if (frame_tick) begin
            // Track instantaneous maximums
            if (h0 > peak0) peak0 <= h0;
            if (h1 > peak1) peak1 <= h1;
            if (h2 > peak2) peak2 <= h2;
            if (h3 > peak3) peak3 <= h3;
            if (h4 > peak4) peak4 <= h4;
            if (h5 > peak5) peak5 <= h5;

            // Decay peak every 4 frames (~15 Hz decay rate)
            if (decay_counter >= 4'd3) begin
                decay_counter <= 4'd0;
                if (peak0 > 0) peak0 <= peak0 - 1'b1;
                if (peak1 > 0) peak1 <= peak1 - 1'b1;
                if (peak2 > 0) peak2 <= peak2 - 1'b1;
                if (peak3 > 0) peak3 <= peak3 - 1'b1;
                if (peak4 > 0) peak4 <= peak4 - 1'b1;
                if (peak5 > 0) peak5 <= peak5 - 1'b1;
            end else begin
                decay_counter <= decay_counter + 1'b1;
            end
        end
    end

    // Visual Palette (24-bit RGB)
    localparam [23:0]
        C_BG       = 24'h0A0E1A, // Deep navy background
        C_HEADER   = 24'h162035, // Header banner
        C_BORDER   = 24'h334E68, // Border grey-blue
        C_GREEN    = 24'h06D6A0, // Low level bar
        C_YELLOW   = 24'hFFD166, // Mid level bar
        C_RED      = 24'hEF476F, // High level bar
        C_PEAK     = 24'hFFFFFF, // White peak hold indicator
        C_CYAN     = 24'h00F0FF, // Cyan accent
        C_PURPLE   = 24'h8B5CF6, // Purple badge
        C_ORANGE   = 24'hF59E0B; // Orange badge

    // Spectrum Equalizer Baseline is Y = 360
    localparam integer BASE_Y = 360;

    // Bar column regions
    wire in_bar0 = (pixel_x >= 60  && pixel_x <= 130);
    wire in_bar1 = (pixel_x >= 150 && pixel_x <= 220);
    wire in_bar2 = (pixel_x >= 240 && pixel_x <= 310);
    wire in_bar3 = (pixel_x >= 330 && pixel_x <= 400);
    wire in_bar4 = (pixel_x >= 420 && pixel_x <= 490);
    wire in_bar5 = (pixel_x >= 510 && pixel_x <= 580);

    // Active fill checks
    wire fill0 = in_bar0 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h0));
    wire fill1 = in_bar1 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h1));
    wire fill2 = in_bar2 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h2));
    wire fill3 = in_bar3 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h3));
    wire fill4 = in_bar4 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h4));
    wire fill5 = in_bar5 && (pixel_y <= BASE_Y) && (pixel_y >= (BASE_Y - h5));

    // Peak-hold line checks (2 pixels thick)
    wire is_peak0 = in_bar0 && (pixel_y >= (BASE_Y - peak0 - 2)) && (pixel_y <= (BASE_Y - peak0));
    wire is_peak1 = in_bar1 && (pixel_y >= (BASE_Y - peak1 - 2)) && (pixel_y <= (BASE_Y - peak1));
    wire is_peak2 = in_bar2 && (pixel_y >= (BASE_Y - peak2 - 2)) && (pixel_y <= (BASE_Y - peak2));
    wire is_peak3 = in_bar3 && (pixel_y >= (BASE_Y - peak3 - 2)) && (pixel_y <= (BASE_Y - peak3));
    wire is_peak4 = in_bar4 && (pixel_y >= (BASE_Y - peak4 - 2)) && (pixel_y <= (BASE_Y - peak4));
    wire is_peak5 = in_bar5 && (pixel_y >= (BASE_Y - peak5 - 2)) && (pixel_y <= (BASE_Y - peak5));

    // Classification Badge Card ($X \in [240, 400]$, $Y \in [65, 110]$)
    wire in_badge = (pixel_x >= 240 && pixel_x <= 400 && pixel_y >= 65 && pixel_y <= 110);
    wire is_badge_border = in_badge && (pixel_x == 240 || pixel_x == 400 || pixel_y == 65 || pixel_y == 110);

    // Pixel Color Logic
    reg [23:0] rgb_next;

    always @(*) begin
        if (!active_video) begin
            rgb_next = 24'h000000;
        end else if (pixel_y <= 45) begin
            // Top Header Bar
            if (pixel_y == 45)
                rgb_next = C_CYAN;
            else if (pixel_x >= 40 && pixel_x <= 600 && pixel_y >= 12 && pixel_y <= 32)
                rgb_next = 24'h1F3A60;
            else
                rgb_next = C_HEADER;
        end else if (is_badge_border) begin
            rgb_next = C_CYAN;
        end else if (in_badge) begin
            case (class_code)
                3'd0: rgb_next = 24'h334E68; // QUIET (Slate)
                3'd1: rgb_next = C_CYAN;     // SPEECH (Cyan)
                3'd2: rgb_next = C_ORANGE;   // LOW-FREQ (Orange)
                3'd3: rgb_next = C_PURPLE;   // HIGH-FREQ (Purple)
                3'd4: rgb_next = C_RED;      // IMPULSIVE/NOISE (Red)
                default: rgb_next = C_HEADER;
            endcase
        end else if (is_peak0 || is_peak1 || is_peak2 || is_peak3 || is_peak4 || is_peak5) begin
            rgb_next = C_PEAK;
        end else if (fill0 || fill1 || fill2 || fill3 || fill4 || fill5) begin
            // Multi-color dynamic gradient based on height
            if (pixel_y < (BASE_Y - 140))
                rgb_next = C_RED;
            else if (pixel_y < (BASE_Y - 70))
                rgb_next = C_YELLOW;
            else
                rgb_next = C_GREEN;
        end else if (pixel_y == BASE_Y || pixel_y == (BASE_Y + 1)) begin
            // Baseline frequency axis line
            rgb_next = C_BORDER;
        end else if (pixel_y >= 415 && pixel_y <= 465 && pixel_x >= 40 && pixel_x <= 600) begin
            // Bottom footer panel
            if (pixel_x == 40 || pixel_x == 600 || pixel_y == 415 || pixel_y == 465)
                rgb_next = C_BORDER;
            else if (pixel_x >= 60 && pixel_x <= (60 + {2'b00, peak_bin_index, 1'b0}) && pixel_y >= 430 && pixel_y <= 450)
                rgb_next = C_CYAN; // Peak bin energy meter
            else
                rgb_next = C_HEADER;
        end else begin
            rgb_next = C_BG;
        end
    end

    // Registered DAC Outputs
    always @(posedge vga_clk or negedge reset_n) begin
        if (!reset_n) begin
            vga_r <= 8'd0;
            vga_g <= 8'd0;
            vga_b <= 8'd0;
        end else begin
            vga_r <= rgb_next[23:16];
            vga_g <= rgb_next[15:8];
            vga_b <= rgb_next[7:0];
        end
    end

endmodule
