# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Pinout

All pin assignments map to verified locations from the DE2-115 User Manual and `common/constraints/de2_115_master.qsf`.

| Signal Name | Direction | FPGA Pin | I/O Standard | Peripheral Component | Description |
|---|---|---|---|---|---|
| `CLOCK_50` | Input | `PIN_Y2` | 3.3-V LVTTL | 50 MHz Oscillator | Primary system clock |
| `KEY[0]` | Input | `PIN_M23` | 3.3-V LVTTL | Pushbutton 0 | Active-low master reset (`reset_n`) |
| `KEY[1]` | Input | `PIN_M21` | 3.3-V LVTTL | Pushbutton 1 | Cursor DOWN / synthetic DOWN gesture |
| `KEY[2]` | Input | `PIN_N21` | 3.3-V LVTTL | Pushbutton 2 | Cursor UP / synthetic UP gesture |
| `KEY[3]` | Input | `PIN_R24` | 3.3-V LVTTL | Pushbutton 3 | Submenu ENTER / synthetic RIGHT gesture |
| `SW[17]` | Input | `PIN_Y23` | 3.3-V LVTTL | Slide Switch 17 | Mode select (`0`: APDS sensor, `1`: Synthetic) |
| `SW[16]` | Input | `PIN_Y24` | 3.3-V LVTTL | Slide Switch 16 | Synthetic LEFT / Exit Submenu pulse |
| `SW[15]` | Input | `PIN_AA22`| 3.3-V LVTTL | Slide Switch 15 | Synthetic NEAR gesture pulse |
| `SW[14]` | Input | `PIN_AA23`| 3.3-V LVTTL | Slide Switch 14 | Synthetic FAR gesture pulse |
| `SW[11:0]` | Input | Multiple | 3.3-V LVTTL | Slide Switches 11-0 | Synthetic sensor photodiode inputs |
| `GPIO[0]` | Inout | `PIN_AB22`| 3.3-V LVTTL | JP5 Pin 1 (GPIO) | APDS-9960 I2C SCL (Open-drain) |
| `GPIO[1]` | Inout | `PIN_AC15`| 3.3-V LVTTL | JP5 Pin 2 (GPIO) | APDS-9960 I2C SDA (Open-drain) |
| `GPIO[2]` | Input | `PIN_AB21`| 3.3-V LVTTL | JP5 Pin 3 (GPIO) | APDS-9960 INT_N interrupt |
| `VGA_CLK` | Output | `PIN_A12` | 3.3-V LVTTL | ADV7123 Video DAC | 25.175 MHz pixel clock |
| `VGA_HS` | Output | `PIN_G13` | 3.3-V LVTTL | ADV7123 Video DAC | Horizontal sync |
| `VGA_VS` | Output | `PIN_C13` | 3.3-V LVTTL | ADV7123 Video DAC | Vertical sync |
| `VGA_BLANK_N` | Output | `PIN_F11` | 3.3-V LVTTL | ADV7123 Video DAC | Active display blanking |
| `VGA_SYNC_N` | Output | `PIN_C10` | 3.3-V LVTTL | ADV7123 Video DAC | Composite sync (tied high) |
| `VGA_R[7:0]` | Output | `PIN_H10`..`PIN_E12` | 3.3-V LVTTL | ADV7123 Video DAC | 8-bit Red channel |
| `VGA_G[7:0]` | Output | `PIN_C9`..`PIN_G8` | 3.3-V LVTTL | ADV7123 Video DAC | 8-bit Green channel |
| `VGA_B[7:0]` | Output | `PIN_D12`..`PIN_B10` | 3.3-V LVTTL | ADV7123 Video DAC | 8-bit Blue channel |
| `LCD_DATA[7:0]` | Inout | `PIN_M5`..`PIN_L3` | 3.3-V LVTTL | 16x2 Character LCD | 8-bit bidirectional data bus |
| `LCD_ON` | Output | `PIN_L5` | 3.3-V LVTTL | 16x2 Character LCD | Power on (`1`) |
| `LCD_BLON` | Output | `PIN_L6` | 3.3-V LVTTL | 16x2 Character LCD | Backlight on (`1`) |
| `LCD_RW` | Output | `PIN_M2` | 3.3-V LVTTL | 16x2 Character LCD | Read/Write (`0` = Write) |
| `LCD_EN` | Output | `PIN_L4` | 3.3-V LVTTL | 16x2 Character LCD | Enable latch strobe |
| `LCD_RS` | Output | `PIN_M1` | 3.3-V LVTTL | 16x2 Character LCD | Register select (`0`=Cmd, `1`=Data) |
| `UART_TXD` | Output | `PIN_G9` | 3.3-V LVTTL | RS-232 Port | 115200 baud serial telemetry out |
| `HEX7 - HEX0`| Output | Multiple | 3.3V / 2.5V | 7-Segment Displays | Menu, state, and gesture counters |
| `LEDR[17:0]`| Output | Multiple | 2.5 V | Red LEDs | Gesture and activity status indicators |
| `LEDG[8:0]` | Output | Multiple | 2.5 V | Green LEDs | Submenu and ready status indicators |
