# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classifier — RTL Design

## 1. Top-Level Module (`audio_top.v`)
`audio_top` instantiates and orchestrates all hardware submodules on the Cyclone IV EP4CE115 FPGA.

### Top-Level Port List
| Signal Name | Width | Dir | Description |
|---|---|---|---|
| `CLOCK_50` | 1 | In | 50 MHz primary master clock (`PIN_Y2`) |
| `KEY[3:0]` | 4 | In | Active-low pushbuttons (KEY[0]: Reset, KEY[1]: Re-init Codec, KEY[2]: Tone Cycle) |
| `SW[17:0]` | 18 | In | Slide switches (SW[17]: Synth Mode, SW[16:14]: Tone Sel, SW[13:0]: Reserved/Gains) |
| `I2C_SCLK` | 1 | Out | WM8731 I2C Clock (`PIN_B7`) |
| `I2C_SDAT` | 1 | InOut | WM8731 I2C Open-Drain Data (`PIN_A8`) |
| `AUD_BCLK` | 1 | In | WM8731 I2S Bit Clock (`PIN_F2`) |
| `AUD_XCK` | 1 | Out | WM8731 12.5 MHz Master Clock (`PIN_E1`) |
| `AUD_ADCLRCK` | 1 | In | WM8731 ADC Sample Frame Clock (`PIN_E2`) |
| `AUD_ADCDAT` | 1 | In | WM8731 ADC Serial PCM Bit Stream (`PIN_D2`) |
| `AUD_DACLRCK` | 1 | Out | WM8731 DAC Sample Frame Clock (`PIN_E3`) |
| `AUD_DACDAT` | 1 | Out | WM8731 DAC Serial Data Output (`PIN_D1`) |
| `LCD_DATA[7:0]` | 8 | InOut | HD44780 8-bit bidirectional data bus |
| `LCD_ON`, `LCD_BLON` | 1 each | Out | LCD power on and backlight enable |
| `LCD_RW`, `LCD_EN`, `LCD_RS` | 1 each | Out | LCD read/write, strobe enable, and register select |
| `VGA_CLK`, `VGA_HS`, `VGA_VS` | 1 each | Out | VGA 25 MHz pixel clock, horizontal and vertical sync |
| `VGA_BLANK_N`, `VGA_SYNC_N` | 1 each | Out | VGA active blanking and composite sync controls |
| `VGA_R[7:0]`, `VGA_G[7:0]`, `VGA_B[7:0]` | 8 each | Out | 24-bit TrueColor RGB video channels to ADV7123 |
| `HEX0 - HEX7` | 7 each | Out | 8x Active-low 7-segment display digit lines |
| `LEDR[17:0]` | 18 | Out | Red LED real-time audio energy meter bar |
| `LEDG[8:0]` | 9 | Out | Green LED status and classification indicators |
| `UART_TXD` | 1 | Out | RS-232 serial telemetry TX pin (`PIN_G9`) |

---

## 2. Core Processing Submodules

### 2.1 `wm8731_configurator.v`
- **Function:** Initializes Wolfson WM8731 audio codec upon power-up or `KEY[1]` press.
- **Register Table:**
  - Reg 0 (0x00): Left Line In (0dB, unmute)
  - Reg 1 (0x01): Right Line In (0dB, unmute)
  - Reg 2 (0x02): Left Headphone Out (0dB)
  - Reg 3 (0x03): Right Headphone Out (0dB)
  - Reg 4 (0x04): Analogue Audio Path Control (Line to ADC, DAC unmute)
  - Reg 5 (0x05): Digital Audio Path Control (Clear soft-mute, 48kHz filter)
  - Reg 6 (0x06): Power Down Control (Power on all analog/digital blocks)
  - Reg 7 (0x07): Digital Audio Interface Format (16-bit I2S, slave mode)
  - Reg 8 (0x08): Sampling Control (Normal 256fs, 48 kHz mode)
  - Reg 9 (0x09): Active Control (Activate digital core)

### 2.2 `audio_pingpong_buffer.v`
- **Function:** Dual-bank sample buffer allowing uninterrupted incoming I2S audio sample streaming.
- **Operation:** When Bank A is filling with incoming 16-bit PCM audio samples, Bank B is read out at 50 MHz to drive the Hanning window and FFT core. When Bank A fills to capacity ($N$ samples), bank pointers toggle automatically and a `frame_ready` strobe is pulsed.

### 2.3 `hanning_window.v`
- **Function:** Multiplies 16-bit signed audio samples by a 16-bit pre-calculated Hanning window lookup table stored in block ROM.
- **Latency:** 1 clock cycle pipelined product with signed scaling:
  $$x_{\text{windowed}} = (x_{\text{sample}} \times w_{\text{rom}}[n]) \gg 16$$

### 2.4 `fft_radix2_core.v`
- **Function:** Computes $N$-point Discrete Fourier Transform using Radix-2 Decimation-in-Frequency.
- **Architecture:** Pipelined butterfly execution engine with dual internal SRAM memory banks (real $I$ and imaginary $Q$ registers) and fixed-point twiddle generator.

### 2.5 `magnitude_approximator.v`
- **Function:** Computes Euclidean vector magnitude from complex $(I, Q)$ outputs using the Alpha-Max Beta-Min algorithm:
  $$|X| = \max(|I|, |Q|) + (\min(|I|, |Q|) \gg 2) + (\min(|I|, |Q|) \gg 3)$$

### 2.6 `spectral_band_extractor.v`
- **Function:** Accumulates individual bin magnitudes into the 6 designated frequency sub-bands, computes total frame energy $E_{\text{total}} = \sum E_i$, and identifies peak spectral bin index and peak amplitude.

### 2.7 `noise_classifier.v`
- **Function:** Evaluates energy distributions across bands to emit single-cycle deterministic classification code (`0`: QUIET, `1`: SPEECH, `2`: LOW-FREQ, `3`: HIGH-FREQ, `4`: NOISE) and 4-character ASCII badge (`QUET`, `SPCH`, `LOWF`, `HGHF`, `NOIS`).

### 2.8 `vga_spectrum_display.v`
- **Function:** Direct pixel renderer generating 640x480 @ 60Hz video stream.
- **Visual Features:**
  - 6 vertical equalizer columns with rounded borders.
  - Multi-stop color gradient: Green ($0 - 50\%$) $\rightarrow$ Yellow ($50 - 80\%$) $\rightarrow$ Red ($80 - 100\%$).
  - White horizontal peak-hold markers that fall gradually with a decaying timer.
  - Header banner with dynamic text title and active acoustic classification badge.

### 2.9 `audio_uart_logger.v`
- **Function:** Formats and transmits 115200 baud ASCII status strings over RS-232 once per frame:
  `[AUDIO] CLASS: SPCH | PEAK_BIN: 04 | PEAK_MAG: 27203 | ENG: 00068908 | B0..B5: 00000 00001 00005 68855 00013 00034\r\n`

### 2.10 `sine_lut_generator.v`
- **Function:** Generates calibrated synthetic test tones ($1\text{ kHz}, 2\text{ kHz}, 5\text{ kHz}$ sinusoidal waves, silence, and 16-bit Galois LFSR white noise) for standalone bench verification.
