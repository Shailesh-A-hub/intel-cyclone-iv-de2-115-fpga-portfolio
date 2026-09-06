# Pinout Specification
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### Master Pin Table (Target: Altera DE2-115 / EP4CE115F29C7)

| Signal Name | FPGA Pin | Direction | IO Standard | Peripheral / Function |
|---|---|---|---|---|
| `CLOCK_50` | `PIN_Y2` | Input | 3.3-V LVTTL | 50 MHz Master Oscillator |
| `KEY[0]` | `PIN_M23` | Input | 3.3-V LVTTL | Active-Low Master Reset Pushbutton |
| `KEY[1]` | `PIN_M21` | Input | 3.3-V LVTTL | Alarm Mute / Acknowledge Pushbutton |
| `KEY[2]` | `PIN_N21` | Input | 3.3-V LVTTL | Dynamic Weight Profile Select |
| `KEY[3]` | `PIN_R24` | Input | 3.3-V LVTTL | Synthetic / Hardware Mode Toggle |
| `SW[9:0]` | `PIN_AB28..PIN_AB25` | Input | 3.3-V LVTTL | 10-bit Synthetic ADC Slider |
| `SW[14:13]` | `PIN_AA22, PIN_AA23` | Input | 3.3-V LVTTL | Synthetic Sensor Select (Gas, Tmp, Flm, Hum) |
| `SW[16:15]` | `PIN_Y23, PIN_Y24` | Input | 3.3-V LVTTL | Fault Injection Selector |
| `SW[17]` | `PIN_AA27` | Input | 3.3-V LVTTL | Synthetic Simulation Mode Enable |
| `GPIO_0` | `PIN_AB22` | Output | 3.3-V LVTTL | Piezo Buzzer PWM Output (JP5 Pin 1) |
| `GPIO_1` | `PIN_AC15` | Output | 3.3-V LVTTL | MCP3008 ADC CS# (JP5 Pin 2) |
| `GPIO_3` | `PIN_Y17` | Output | 3.3-V LVTTL | MCP3008 ADC SCLK (JP5 Pin 4) |
| `GPIO_5` | `PIN_Y16` | Output | 3.3-V LVTTL | MCP3008 ADC MOSI / DIN (JP5 Pin 6) |
| `GPIO_7` | `PIN_AE16` | Input | 3.3-V LVTTL | MCP3008 ADC MISO / DOUT (JP5 Pin 8) |
| `HEX0[6:0]` | `PIN_H22..PIN_G18` | Output | 3.3-V LVTTL | 7-Segment Display 0 (Risk Score Ones) |
| `HEX1[6:0]` | `PIN_U24..PIN_M24` | Output | 3.3-V LVTTL | 7-Segment Display 1 (Risk Score Tens) |
| `HEX2[6:0]` | `PIN_W28..PIN_AA25` | Output | 3.3-V LVTTL | 7-Segment Display 2 (Gas % Ones) |
| `HEX3[6:0]` | `PIN_Y19..PIN_V21` | Output | 3.3-V LVTTL | 7-Segment Display 3 (Gas % Tens) |
| `HEX4[6:0]` | `PIN_AE18..PIN_AB19` | Output | 3.3-V LVTTL | 7-Segment Display 4 (Temp °C Ones) |
| `HEX5[6:0]` | `PIN_AH18..PIN_AD18` | Output | 3.3-V LVTTL | 7-Segment Display 5 (Temp °C Tens) |
| `HEX6[6:0]` | `PIN_AC17..PIN_AA17` | Output | 3.3-V LVTTL | 7-Segment Display 6 (Flame % Ones) |
| `HEX7[6:0]` | `PIN_AA14..PIN_AD17` | Output | 3.3-V LVTTL | 7-Segment Display 7 (Flame % Tens) |
| `LEDG[3:0]` | `PIN_E24..PIN_E21` | Output | 2.5 V | Green Status Indicators (SAFE) |
| `LEDG[5:4]` | `PIN_G20, PIN_H21` | Output | 2.5 V | Active Weight Profile Indicators |
| `LEDG[7:6]` | `PIN_G21, PIN_G22` | Output | 2.5 V | Dominant Hazard Indicator |
| `LEDG[8]` | `PIN_F17` | Output | 2.5 V | Synthetic Mode Active Indicator |
| `LEDR[4:0]` | `PIN_E18..PIN_G19` | Output | 2.5 V | Sensor Fault Code Indicators |
| `LEDR[14:12]` | `PIN_G15..PIN_H17` | Output | 2.5 V | Amber Caution Indicators |
| `LEDR[17:15]` | `PIN_H15..PIN_G16` | Output | 2.5 V | Red Danger Flashing Indicators |
| `LCD_DATA[7:0]` | `PIN_M5..PIN_L3` | Output | 3.3-V LVTTL | 16x2 HD44780 LCD 8-bit Data Bus |
| `LCD_RW` | `PIN_M1` | Output | 3.3-V LVTTL | LCD Read/Write Select (Tied Low) |
| `LCD_EN` | `PIN_L4` | Output | 3.3-V LVTTL | LCD Strobe Enable |
| `LCD_RS` | `PIN_M2` | Output | 3.3-V LVTTL | LCD Register Select (Command/Data) |
| `LCD_ON` | `PIN_L5` | Output | 3.3-V LVTTL | LCD Power On Control (High) |
| `LCD_BLON` | `PIN_L6` | Output | 3.3-V LVTTL | LCD Backlight On Control (High) |
| `UART_TXD` | `PIN_G12` | Output | 3.3-V LVTTL | Serial Telemetry Output (115200 Baud) |
