#============================================================
# Synopsys Design Constraints: fire_gas_top.sdc
# Target Board: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)
# Primary Clock: 50 MHz Oscillator (PIN_Y2)
#============================================================

# Primary 50 MHz Oscillator Constraint (20.000 ns period, 50% duty cycle)
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Derive Clock Uncertainty to account for jitter and skew
derive_clock_uncertainty

# SPI Master Clock Generated Clock (1.0 MHz nominal from internal divider)
create_generated_clock -name SPI_SCLK -source [get_ports {CLOCK_50}] -divide_by 50 [get_ports {GPIO_3}]

# False Paths for Asynchronous / Static Inputs
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {GPIO_7}]

# False Paths for Static / Low-Speed Peripheral Outputs
set_false_path -to [get_ports {HEX*[*]}]
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LCD_DATA[*]}]
set_false_path -to [get_ports {LCD_RW}]
set_false_path -to [get_ports {LCD_EN}]
set_false_path -to [get_ports {LCD_RS}]
set_false_path -to [get_ports {LCD_ON}]
set_false_path -to [get_ports {LCD_BLON}]
set_false_path -to [get_ports {GPIO_0}]
set_false_path -to [get_ports {GPIO_1}]
set_false_path -to [get_ports {GPIO_5}]
set_false_path -to [get_ports {UART_TXD}]
