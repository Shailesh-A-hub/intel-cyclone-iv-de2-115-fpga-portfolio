## Synopsys Design Constraints for Project 1 - Occupancy Top
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {GPIO_PIR_IN[*]}]

set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {HEX*[*]}]
set_false_path -to [get_ports {LCD_*}]
set_false_path -to [get_ports {RELAY_*}]
set_false_path -to [get_ports {UART_TXD}]
