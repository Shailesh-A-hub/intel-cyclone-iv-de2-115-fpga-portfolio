#============================================================
# Synopsys Design Constraints: gesture_top.sdc
# Project: Project 4 - FPGA Gesture-Controlled Menu Interface
# Target Board: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
#============================================================

# 50 MHz Primary Clock Constraint (20.0 ns period)
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Generated Pixel Clock for VGA DAC (25 MHz, 40.0 ns period)
create_generated_clock -name vga_clk -source [get_ports {CLOCK_50}] -divide_by 2 [get_registers {vga_menu_display:u_vga_menu|vga_timing_controller:u_vga_timing|vga_clk}]

# Derive Clock Uncertainty
derive_clock_uncertainty

# False Paths on Asynchronous User Inputs
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {GPIO[2]}]

# False Paths on Low-Speed Peripherals & Displays
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {HEX*[*]}]
set_false_path -to [get_ports {LCD_*}]
set_false_path -to [get_ports {UART_TXD}]
