# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classifier — Hardware Setup

## 1. Required Hardware & Equipment

1. **Development Board:** Terasic DE2-115 Development & Education Board with Intel Cyclone IV EP4CE115F29C7 FPGA.
2. **Audio Input Source:** 3.5mm standard audio source (PC line-out, smartphone, function generator, or microphone pre-amp).
3. **Audio Cable:** 3.5mm male-to-male stereo audio cable.
4. **Audio Output (Optional Monitoring):** Standard headphones or powered speakers connected to Line-Out (green 3.5mm jack).
5. **VGA Monitor:** Standard 60 Hz computer monitor connected via 15-pin D-Sub VGA cable.
6. **Host Computer Connection:** USB-Blaster II programming cable for FPGA bitstream configuration and RS-232 UART serial cable (or USB-to-UART adapter).

---

## 2. Onboard Audio Jack Map (DE2-115)

The DE2-115 contains three 3.5mm audio jacks connected directly to the Wolfson WM8731 codec:
- **Blue Jack (`J4`):** Line-In (Stereo analog input) $\rightarrow$ Connect your audio source here.
- **Green Jack (`J5`):** Line-Out / Headphone Out (Stereo analog output).
- **Pink Jack (`J3`):** Microphone In (Mono analog input with bias).

---

## 3. Onboard Controls & Operational Modes

### 3.1 Pushbuttons (`KEY[3:0]`)
- `KEY[0]` (`PIN_M23`): Master System Reset (Active-Low).
- `KEY[1]` (`PIN_M21`): Re-trigger WM8731 I2C Codec Configuration Sequence.
- `KEY[2]` (`PIN_N21`): Synthetic Tone Select Step (Cycles through test tones).
- `KEY[3]` (`PIN_R24`): Unused / Spare.

### 3.2 Slide Switches (`SW[17:0]`)
- `SW[17]` (`PIN_Y23`):
  - `0`: **Live Hardware Audio Mode** (Streams real audio from Line-In via Wolfson WM8731).
  - `1`: **Synthetic DDS Simulation Mode** (Internal FPGA tone generator enabled).
- `SW[16:14]` (`PIN_Y24`, `PIN_AA22`, `PIN_AA23`): Synthetic Test Tone Select:
  - `3'b000` (0): Silence (Zero Amplitude)
  - `3'b001` (1): 1.0 kHz Pure Sine Wave
  - `3'b010` (2): 2.0 kHz Pure Sine Wave
  - `3'b011` (3): 5.0 kHz Pure Sine Wave
  - `3'b100` (4): White Noise (Galois LFSR)
- `SW[13:0]`: Reserved / Display Gain Adjustments.

---

## 4. Visual Feedback Indicators

### 4.1 VGA 640x480 @ 60Hz Dashboard
- 6 vertical dynamic equalizer columns rendering real-time amplitude in each frequency band.
- Multi-stop color gradient: Green ($0 - 50\%$) $\rightarrow$ Yellow ($50 - 80\%$) $\rightarrow$ Red ($80 - 100\%$).
- White horizontal peak-hold markers that fall slowly with a decaying timer.
- Title banner with real-time acoustic classification badge (`QUIET`, `SPEECH`, `LOW-FREQ`, `HIGH-FREQ`, `NOISE`).

### 4.2 HD44780 16x2 Character LCD
- **Line 1:** `CLASS: SPEECH     ` (Active classification badge).
- **Line 2:** `ENG:068908 PK:04 ` (Total frame energy and peak frequency bin index).

### 4.3 7-Segment Displays (`HEX7` - `HEX0`)
- `HEX7 - HEX6`: Peak spectral bin index (Decimal).
- `HEX5 - HEX0`: Total frame energy accumulation value (Decimal).

### 4.4 Red LEDs (`LEDR[17:0]`)
- 18-LED instantaneous volume unit (VU) meter bar graph representing total frame acoustic energy.

### 4.5 Green LEDs (`LEDG[8:0]`)
- `LEDG[0]`: Codec I2C Configuration Done.
- `LEDG[1]`: Codec I2C Configuration Error / NACK.
- `LEDG[2]`: I2S Sample Receiving Strobe.
- `LEDG[3]`: FFT Frame Processing Active.
- `LEDG[8:4]`: One-hot acoustic classification indicator (`[4]`: Quiet, `[5]`: Speech, `[6]`: Low-Freq, `[7]`: High-Freq, `[8]`: Noise).

---

## 5. Serial RS-232 Telemetry Setup

- **Baud Rate:** 115200 baud
- **Data Bits:** 8
- **Parity:** None
- **Stop Bits:** 1
- **Flow Control:** None
- **Sample Output:**
  ```
  [AUDIO] CLASS: SPCH | PEAK_BIN: 04 | PEAK_MAG: 27203 | ENG: 00068908 | B0..B5: 00000 00001 00005 68855 00013 00034
  ```
