# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Hardware Setup Guide

## 1. External Sensor Wiring (APDS-9960 Daughterboard)

The APDS-9960 breakout board interfaces with the DE2-115 via 40-pin GPIO Expansion Header `JP5`:

| Sensor Pin | DE2-115 JP5 Header Pin | FPGA Pin | Signal Name | Notes |
|---|---|---|---|---|
| **VCC** | Pin 29 | N/A | `+3.3V` | 3.3V power supply (Do NOT use 5V!) |
| **GND** | Pin 12 / 30 | N/A | `GND` | Common system ground |
| **SCL** | Pin 1 | `PIN_AB22` | `GPIO[0]` | I2C Clock (Requires $4.7\text{ k}\Omega$ pull-up to 3.3V) |
| **SDA** | Pin 2 | `PIN_AC15` | `GPIO[1]` | I2C Data (Requires $4.7\text{ k}\Omega$ pull-up to 3.3V) |
| **INT** | Pin 3 | `PIN_AB21` | `GPIO[2]` | Active-low gesture interrupt |

> [!CAUTION]
> **VOLTAGE COMPLIANCE WARNING:**  
> The Cyclone IV FPGA GPIO pins are strictly 3.3V tolerant. The APDS-9960 sensor must be powered from the DE2-115 3.3V rail. Never connect a 5V supply to the sensor breakout board as this may permanently damage the FPGA input buffers.

---

## 2. Onboard Display Connections

### 2.1 HD44780 16x2 Character LCD
The DE2-115 includes an onboard 16x2 character LCD module driven directly by FPGA pins:
- Data bus: `PIN_L3`, `PIN_L1`, `PIN_L2`, `PIN_K7`, `PIN_K1`, `PIN_K2`, `PIN_M3`, `PIN_M5`
- Controls: `LCD_RW` (`PIN_M2`), `LCD_EN` (`PIN_L4`), `LCD_RS` (`PIN_M1`), `LCD_ON` (`PIN_L5`), `LCD_BLON` (`PIN_L6`).
- Ensure contrast potentiometer `VR1` on the DE2-115 board is adjusted if text appears faint or dark.

### 2.2 VGA Monitor Connection
- Connect a standard VGA monitor to the DB-15 female connector on the DE2-115.
- The onboard ADV7123 triple 10-bit high-speed video DAC converts digital signals to analog RGB.
- The monitor displays the full 640x480 @ 60Hz graphical dashboard.

---

## 3. Bench Testing & Operational Controls

| Control Component | Action | Function |
|---|---|---|
| `KEY[0]` | Press | Active-low master system reset |
| `KEY[1]` | Press | Down navigation (Synthetic DOWN gesture) |
| `KEY[2]` | Press | Up navigation (Synthetic UP gesture) |
| `KEY[3]` | Press | Submenu Enter / Parameter adjust (Synthetic RIGHT/ENTER gesture) |
| `SW[17]` | Slide Switch | `0`: Real APDS-9960 I2C sensor mode; `1`: Synthetic bench test mode |
| `SW[16]` | Slide Switch | Synthetic LEFT / Exit Submenu pulse trigger |
| `SW[15]` | Slide Switch | Synthetic NEAR gesture trigger |
| `SW[14]` | Slide Switch | Synthetic FAR gesture trigger |
| `SW[11:0]` | Slide Switches | Synthetic photodiode offsets ($U, D, L, R$) |
| `LEDG[0]` | Green LED | APDS-9960 device ready indicator |
| `LEDG[1]` | Green LED | Initialization sequence completed successfully |
| `LEDG[2]` | Green LED | Active inside a Submenu |
| `LEDG[3]` | Green LED | Audio Beeper enabled status |
| `LEDG[7:4]` | Green LEDs | Active Main Menu category one-hot indicator |
| `LEDR[3:0]` | Red LEDs | Directional gesture indicators (UP, DOWN, LEFT, RIGHT) |
| `LEDR[5:4]` | Red LEDs | Proximity gesture indicators (NEAR, FAR) |
| `LEDR[16]` | Red LED | I2C bus communication error indicator |
| `LEDR[17]` | Red LED | Synthetic mode active indicator |
| `HEX7` | 7-Segment Digit | Current Menu ID (0:STATUS, 1:SETTINGS, 2:SENSORS, 3:ABOUT) |
| `HEX6` | 7-Segment Digit | Submenu Active flag (`S` / `1`) |
| `HEX5` | 7-Segment Digit | Submenu Page index (0, 1, 2) |
| `HEX4` | 7-Segment Digit | Last detected gesture code (1..6) |
| `HEX3-0` | 7-Segment Digits | Cumulative gesture event counter |
| `UART_TXD` | RS-232 Port | Connect to PC via DB-9 serial cable or USB-UART adapter at 115200-8-N-1 |
