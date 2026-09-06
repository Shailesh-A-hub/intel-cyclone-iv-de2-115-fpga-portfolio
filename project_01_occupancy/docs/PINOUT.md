# Pinout Specification: Project 1
## Multi-Zone Occupancy & Energy Decision Engine

All pin mappings target the **Cyclone IV EP4CE115F29C7** FPGA on the **Terasic DE2-115** board.

---

## 1. Master Pin Table

| Signal | FPGA Pin | Direction | I/O Standard | Peripheral | Description |
|---|---|---|---|---|---|
| `CLOCK_50` | `PIN_Y2` | Input | 3.3-V LVTTL | 50 MHz Oscillator | Primary system clock |
| `KEY[0]` | `PIN_M23` | Input | 3.3-V LVTTL | Pushbutton 0 | Active-low asynchronous master reset |
| `KEY[1]` | `PIN_M21` | Input | 3.3-V LVTTL | Pushbutton 1 | Manual test motion trigger |
| `SW[0]` | `PIN_AB28` | Input | 3.3-V LVTTL | Slide Switch 0 | Zone 1 motion simulation switch |
| `SW[1]` | `PIN_AC28` | Input | 3.3-V LVTTL | Slide Switch 1 | Zone 2 motion simulation switch |
| `SW[2]` | `PIN_AC27` | Input | 3.3-V LVTTL | Slide Switch 2 | Zone 3 motion simulation switch |
| `SW[3]` | `PIN_AD27` | Input | 3.3-V LVTTL | Slide Switch 3 | Zone 4 motion simulation switch |
| `SW[4]` | `PIN_AB27` | Input | 3.3-V LVTTL | Slide Switch 4 | Dark mode: 1 = Dark (lights enabled), 0 = Daylight |
| `SW[16]` | `PIN_Y24` | Input | 3.3-V LVTTL | Slide Switch 16 | Timeout preset selector bit 0 |
| `SW[17]` | `PIN_Y23` | Input | 3.3-V LVTTL | Slide Switch 17 | Timeout preset selector bit 1 |
| `GPIO_PIR_IN[0]` | `PIN_AB22` | Input | 3.3-V LVTTL | JP5 Pin 1 | External PIR sensor Zone 1 |
| `GPIO_PIR_IN[1]` | `PIN_AC15` | Input | 3.3-V LVTTL | JP5 Pin 2 | External PIR sensor Zone 2 |
| `GPIO_PIR_IN[2]` | `PIN_AB21` | Input | 3.3-V LVTTL | JP5 Pin 3 | External PIR sensor Zone 3 |
| `GPIO_PIR_IN[3]` | `PIN_Y17` | Input | 3.3-V LVTTL | JP5 Pin 4 | External PIR sensor Zone 4 |
| `RELAY_LIGHTS` | `PIN_Y16` | Output | 3.3-V LVTTL | JP5 Pin 6 | Lighting contactor relay control |
| `RELAY_HVAC` | `PIN_AD21` | Output | 3.3-V LVTTL | JP5 Pin 7 | HVAC contactor relay control |
| `RELAY_FANS` | `PIN_AE16` | Output | 3.3-V LVTTL | JP5 Pin 8 | Ventilation fan PWM control |
| `LEDR[3:0]` | `PIN_G19, F19, E19, F21` | Output | 2.5 V | Red LEDs 0..3 | Raw motion trigger indicators |
| `LEDR[17]` | `PIN_H15` | Output | 2.5 V | Red LED 17 | Sensor fault / accumulator overflow |
| `LEDG[3:0]` | `PIN_E21, E22, E25, E24` | Output | 2.5 V | Green LEDs 0..3 | Active zone occupancy indicators |
| `LEDG[4]` | `PIN_H21` | Output | 2.5 V | Green LED 4 | Lighting relay energized indicator |
| `LEDG[5]` | `PIN_G20` | Output | 2.5 V | Green LED 5 | HVAC relay energized indicator |
| `LEDG[6]` | `PIN_G22` | Output | 2.5 V | Green LED 6 | Fan relay energized indicator |
| `HEX0[6:0]` | `PIN_H22..G18` | Output | 2.5 V / 3.3 V | 7-Segment Digit 0 | Energy saved Wh digit 0 (LSB) |
| `HEX1[6:0]` | `PIN_U24..M24` | Output | 3.3-V LVTTL | 7-Segment Digit 1 | Energy saved Wh digit 1 |
| `HEX2[6:0]` | `PIN_W28..AA25` | Output | 3.3-V LVTTL | 7-Segment Digit 2 | Energy saved Wh digit 2 |
| `HEX3[6:0]` | `PIN_Y19..V21` | Output | 3.3-V LVTTL | 7-Segment Digit 3 | Energy saved Wh digit 3 (MSB) |
| `HEX4[6:0]` | `PIN_AE18..AB19` | Output | 3.3-V LVTTL | 7-Segment Digit 4 | HVAC stage numeric value (0-3) |
| `HEX5[6:0]` | `PIN_AH18..AD18` | Output | 3.3-V LVTTL | 7-Segment Digit 5 | HVAC indicator label ('H') |
| `HEX6[6:0]` | `PIN_AC17..AA17` | Output | 3.3-V LVTTL | 7-Segment Digit 6 | Active zones numeric count (0-4) |
| `HEX7[6:0]` | `PIN_AA14..AD17` | Output | 3.3-V LVTTL | 7-Segment Digit 7 | Zone indicator label ('Z') |
| `LCD_DATA[7:0]`| `PIN_M1..L3` | InOut | 3.3-V LVTTL | 16x2 LCD Data | Parallel data bus |
| `LCD_RW` | `PIN_M5` | Output | 3.3-V LVTTL | 16x2 LCD RW | Read/Write control (0=Write) |
| `LCD_EN` | `PIN_L6` | Output | 3.3-V LVTTL | 16x2 LCD EN | Enable strobe |
| `LCD_RS` | `PIN_M2` | Output | 3.3-V LVTTL | 16x2 LCD RS | Register select (0=Cmd, 1=Data) |
| `LCD_ON` | `PIN_L5` | Output | 3.3-V LVTTL | 16x2 LCD ON | Display power |
| `LCD_BLON` | `PIN_L4` | Output | 3.3-V LVTTL | 16x2 LCD BLON | Backlight enable |
| `UART_TXD` | `PIN_G9` | Output | 3.3-V LVTTL | RS-232 TX | Serial telemetry stream |
