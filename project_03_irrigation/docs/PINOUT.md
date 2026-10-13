# Project 3: Smart Adaptive Irrigation System — Pinout Specification

All pin assignments map to verified locations from the DE2-115 User Manual and `common/constraints/de2_115_master.qsf`.

| Signal Name | Direction | FPGA Pin | I/O Standard | Peripheral Component | Description |
|---|---|---|---|---|---|
| `CLOCK_50` | Input | `PIN_Y2` | 3.3-V LVTTL | Onboard 50 MHz Oscillator | Primary system clock |
| `KEY[0]` | Input | `PIN_M23` | 2.5 V | Pushbutton 0 | Active-low master reset (`reset_n`) |
| `KEY[1]` | Input | `PIN_M21` | 2.5 V | Pushbutton 1 | Manual pulse trigger / clear |
| `KEY[2]` | Input | `PIN_N21` | 2.5 V | Pushbutton 2 | Base threshold adjust toggle |
| `SW[17]` | Input | `PIN_Y23` | 2.5 V | Slide Switch 17 | Synthetic mode enable (`1`: Sim, `0`: Real) |
| `SW[16]` | Input | `PIN_Y24` | 2.5 V | Slide Switch 16 | Manual pump override |
| `SW[15]` | Input | `PIN_AA22`| 2.5 V | Slide Switch 15 | Rain sensor manual override switch |
| `SW[12]` | Input | `PIN_AB23`| 2.5 V | Slide Switch 12 | Sensor Mode (`0`: Direct LM393 DO default, `1`: MCP3008 SPI) |
| `SW[14:13, 11:0]` | Input | Multiple | 2.5 V | Slide Switches | Synthetic sensor values & fault injection |
| `LEDG[0]` | Output | `PIN_E21` | 2.5 V | Green LED 0 | Pump active status (`1`: Watering) |
| `LEDR[17]` | Output | `PIN_H15` | 2.5 V | Red LED 17 | Rain lockout status |
| `LEDR[16]` | Output | `PIN_G16` | 2.5 V | Red LED 16 | Sensor fault warning indicator |
| `LEDR[12]` | Output | `PIN_J16` | 2.5 V | Red LED 12 | Direct LM393 DO sensor mode indicator |
| `LEDR[11:0]`| Output | Multiple | 2.5 V | Red LEDs | System status & watering counters |
| `HEX7[6:0]`| Output | `PIN_AA14`..`PIN_AD17` | 3.3-V LVTTL | 7-Seg Digit 7 | Soil moisture tens digit |
| `HEX6[6:0]`| Output | `PIN_AE18`..`PIN_AF19` | 3.3-V LVTTL | 7-Seg Digit 6 | Soil moisture ones digit |
| `HEX5[6:0]`| Output | `PIN_V21`..`PIN_W28` | 2.5 V | 7-Seg Digit 5 | Adaptive threshold tens digit |
| `HEX4[6:0]`| Output | `PIN_U21`..`PIN_Y19` | 2.5 V | 7-Seg Digit 4 | Adaptive threshold ones digit |
| `HEX3[6:0]`| Output | `PIN_Y22`..`PIN_W25` | 2.5 V | 7-Seg Digit 3 | Temperature tens digit |
| `HEX2[6:0]`| Output | `PIN_W21`..`PIN_AA25`| 2.5 V | 7-Seg Digit 2 | Temperature ones digit |
| `HEX1[6:0]`| Output | `PIN_AA26`..`PIN_M24` | 2.5 V | 7-Seg Digit 1 | Humidity tens digit |
| `HEX0[6:0]`| Output | `PIN_G18`..`PIN_H22` | 2.5 V | 7-Seg Digit 0 | Humidity ones digit |
| `LCD_DATA[7:0]`| Inout | `PIN_L3`..`PIN_M5` | 3.3-V LVTTL | 16x2 Character LCD | 8-bit bidirectional data bus |
| `LCD_ON` | Output | `PIN_L5` | 3.3-V LVTTL | 16x2 Character LCD | Power on (`1`) |
| `LCD_BLON` | Output | `PIN_L6` | 3.3-V LVTTL | 16x2 Character LCD | Backlight on (`1`) |
| `LCD_RW` | Output | `PIN_M1` | 3.3-V LVTTL | 16x2 Character LCD | Read/Write (`0` = Write) |
| `LCD_EN` | Output | `PIN_L4` | 3.3-V LVTTL | 16x2 Character LCD | Enable latch strobe |
| `LCD_RS` | Output | `PIN_M2` | 3.3-V LVTTL | 16x2 Character LCD | Register select (`0`=Cmd, `1`=Data) |
| `UART_TXD` | Output | `PIN_G9` | 3.3-V LVTTL | RS-232 / UART Port | 115200 baud serial telemetry out |
| `GPIO_0` | Output | `PIN_AB22`| 3.3-V LVTTL | JP5 Pin 1 (GPIO) | External relay coil driver output |
| `GPIO_1` | Output | `PIN_AC15`| 3.3-V LVTTL | JP5 Pin 2 (GPIO) | MCP3008 ADC SPI CS_N |
| `GPIO_3` | Output | `PIN_Y17` | 3.3-V LVTTL | JP5 Pin 4 (GPIO) | MCP3008 ADC SPI SCLK |
| `GPIO_5` | Output | `PIN_Y16` | 3.3-V LVTTL | JP5 Pin 6 (GPIO) | MCP3008 ADC SPI MOSI |
| `GPIO_7` | Input  | `PIN_AE16`| 3.3-V LVTTL | JP5 Pin 8 (GPIO) | **LM393 DO input** (or MCP3008 SPI MISO) |
| `GPIO_9` | Inout  | `PIN_AF16`| 3.3-V LVTTL | JP5 Pin 10 (GPIO)| DHT11 1-Wire Bidirectional Data |
| `GPIO_11`| Input  | `PIN_AE15`| 3.3-V LVTTL | JP5 Pin 13 (GPIO)| Rain sensor digital input |
