# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classifier — Pinout

**Target Device:** Intel Cyclone IV EP4CE115F29C7 (Terasic DE2-115)  
**Package:** 780-pin FBGA  
**Speed Grade:** -7  

---

## 1. Master System Pin Map

| Signal Name | FPGA Pin | Direction | I/O Standard | Peripheral | Description |
|---|---|---|---|---|---|
| `CLOCK_50` | `PIN_Y2` | Input | 3.3-V LVTTL | 50 MHz Oscillator | Primary Master Clock |
| `KEY[0]` | `PIN_M23` | Input | 3.3-V LVTTL | Pushbutton 0 | Active-Low Master Reset |
| `KEY[1]` | `PIN_M21` | Input | 3.3-V LVTTL | Pushbutton 1 | Codec Re-Configuration Strobe |
| `KEY[2]` | `PIN_N21` | Input | 3.3-V LVTTL | Pushbutton 2 | Synthetic Tone Cycle Strobe |
| `KEY[3]` | `PIN_R24` | Input | 3.3-V LVTTL | Pushbutton 3 | Spare Pushbutton |
| `SW[0]` | `PIN_AB28` | Input | 3.3-V LVTTL | Slide Switch 0 | Display Gain Bit 0 |
| `SW[1]` | `PIN_AC28` | Input | 3.3-V LVTTL | Slide Switch 1 | Display Gain Bit 1 |
| `SW[2]` | `PIN_AC27` | Input | 3.3-V LVTTL | Slide Switch 2 | Display Gain Bit 2 |
| `SW[3]` | `PIN_AD27` | Input | 3.3-V LVTTL | Slide Switch 3 | Display Gain Bit 3 |
| `SW[14]` | `PIN_AA23` | Input | 3.3-V LVTTL | Slide Switch 14 | Tone Select Bit 0 |
| `SW[15]` | `PIN_AA22` | Input | 3.3-V LVTTL | Slide Switch 15 | Tone Select Bit 1 |
| `SW[16]` | `PIN_Y24` | Input | 3.3-V LVTTL | Slide Switch 16 | Tone Select Bit 2 |
| `SW[17]` | `PIN_Y23` | Input | 3.3-V LVTTL | Slide Switch 17 | Synthetic Audio Mode Enable |

---

## 2. Wolfson WM8731 Audio Codec Physical Interface

| Signal Name | FPGA Pin | Direction | I/O Standard | Description |
|---|---|---|---|---|
| `I2C_SCLK` | `PIN_B7` | Output | 3.3-V LVTTL | Codec I2C Serial Clock |
| `I2C_SDAT` | `PIN_A8` | InOut | 3.3-V LVTTL | Codec I2C Open-Drain Serial Data |
| `AUD_BCLK` | `PIN_F2` | Input | 3.3-V LVTTL | Audio I2S Bit Clock ($1.536\text{ MHz}$) |
| `AUD_XCK` | `PIN_E1` | Output | 3.3-V LVTTL | Audio Master Clock ($12.5\text{ MHz}$) |
| `AUD_ADCLRCK` | `PIN_E2` | Input | 3.3-V LVTTL | ADC Sample Left/Right Frame Clock ($48\text{ kHz}$) |
| `AUD_ADCDAT` | `PIN_D2` | Input | 3.3-V LVTTL | ADC Serial Audio Data Stream |
| `AUD_DACLRCK` | `PIN_E3` | Output | 3.3-V LVTTL | DAC Sample Left/Right Frame Clock |
| `AUD_DACDAT` | `PIN_D1` | Output | 3.3-V LVTTL | DAC Serial Audio Data Output |

---

## 3. ADV7123 24-bit VGA DAC Physical Interface

| Signal Name | FPGA Pin | Direction | I/O Standard | Description |
|---|---|---|---|---|
| `VGA_CLK` | `PIN_A12` | Output | 3.3-V LVTTL | 25.175 MHz Video Pixel Clock |
| `VGA_HS` | `PIN_G13` | Output | 3.3-V LVTTL | Horizontal Synchronization Pulse |
| `VGA_VS` | `PIN_C13` | Output | 3.3-V LVTTL | Vertical Synchronization Pulse |
| `VGA_BLANK_N` | `PIN_F11` | Output | 3.3-V LVTTL | Video Active Blanking Signal (Active Low) |
| `VGA_SYNC_N` | `PIN_C10` | Output | 3.3-V LVTTL | Composite Sync Signal |
| `VGA_R[7:0]` | `PIN_H10`, `PIN_H8`, `PIN_J12`, `PIN_G10`, `PIN_F12`, `PIN_D10`, `PIN_E11`, `PIN_E12` | Output | 3.3-V LVTTL | Red Video DAC Channels (MSB to LSB) |
| `VGA_G[7:0]` | `PIN_C9`, `PIN_F10`, `PIN_B8`, `PIN_C8`, `PIN_H12`, `PIN_F8`, `PIN_G11`, `PIN_G8` | Output | 3.3-V LVTTL | Green Video DAC Channels (MSB to LSB) |
| `VGA_B[7:0]` | `PIN_D12`, `PIN_D11`, `PIN_C12`, `PIN_A11`, `PIN_B11`, `PIN_C11`, `PIN_A10`, `PIN_B10` | Output | 3.3-V LVTTL | Blue Video DAC Channels (MSB to LSB) |

---

## 4. HD44780 16x2 Character LCD Interface

| Signal Name | FPGA Pin | Direction | I/O Standard | Description |
|---|---|---|---|---|
| `LCD_DATA[7:0]` | `PIN_M5`, `PIN_M3`, `PIN_K2`, `PIN_K1`, `PIN_K7`, `PIN_L2`, `PIN_L1`, `PIN_L3` | InOut | 3.3-V LVTTL | 8-bit Parallel Data Bus |
| `LCD_ON` | `PIN_L5` | Output | 3.3-V LVTTL | LCD Power Control (1=On) |
| `LCD_BLON` | `PIN_L4` | Output | 3.3-V LVTTL | LCD Backlight Control (1=On) |
| `LCD_RW` | `PIN_M2` | Output | 3.3-V LVTTL | Read/Write Select (0=Write) |
| `LCD_EN` | `PIN_L6` | Output | 3.3-V LVTTL | LCD Enable Strobe |
| `LCD_RS` | `PIN_M1` | Output | 3.3-V LVTTL | Register Select (0=Command, 1=Data) |

---

## 5. Status Indicators & Serial Telemetry

| Signal Name | FPGA Pin Range | Direction | I/O Standard | Description |
|---|---|---|---|---|
| `HEX0[6:0]` .. `HEX7[6:0]` | Pins detailed in `.qsf` | Output | 2.5 V / 3.3-V | 8x 7-Segment Numerical Displays |
| `LEDR[17:0]` | `PIN_H15` .. `PIN_G19` | Output | 2.5 V | 18x Red LEDs (VU Meter Bar) |
| `LEDG[8:0]` | `PIN_F17` .. `PIN_E21` | Output | 2.5 V | 9x Green LEDs (System & Class Flags) |
| `UART_TXD` | `PIN_G9` | Output | 3.3-V LVTTL | RS-232 UART Serial Telemetry Transmit |
