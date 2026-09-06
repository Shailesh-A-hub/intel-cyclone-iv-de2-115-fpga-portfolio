# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classification Engine

**Platform:** Terasic DE2-115 (Intel Cyclone IV EP4CE115F29C7)  
**Language:** Verilog-2001 (IEEE 1364-2001)  
**Tools:** Intel Quartus Prime, ModelSim, Icarus Verilog, Python 3  
**Status:** **100% Verified (18/18 Tests Passing)**

---

## 1. Executive Summary

Project 5 is the flagship DSP and mixed-signal project of the DE2-115 FPGA Portfolio. It implements a complete hardware pipeline for real-time acoustic signal processing, Fast Fourier Transform (FFT) spectral analysis, psychoacoustic frequency energy extraction, and deterministic noise classification.

The system interfaces directly with the onboard **Wolfson WM8731 Audio Codec** over I2C and I2S at 48 kHz sampling rate, windows incoming audio samples using a 16-bit **Hanning Window ROM**, computes a **Radix-2 Decimation-in-Frequency (DIF) FFT**, approximates complex Euclidean vector magnitudes using the **Alpha-Max Beta-Min (AMBM)** algorithm, extracts energy across **6 psychoacoustic frequency sub-bands**, and classifies ambient acoustic environments into 5 discrete categories (`QUIET`, `SPEECH`, `LOW-FREQ`, `HIGH-FREQ`, `NOISE`).

Visual feedback is rendered in real time on a 640x480 @ 60Hz VGA monitor with dynamic frequency equalizer bars and peak-hold indicators, an HD44780 16x2 character LCD, eight 7-segment displays, and continuous 115200 baud RS-232 serial telemetry.

---

## 2. Key Technical Highlights

1. **Hardware Wolfson WM8731 Configuration Engine:**
   - Automated I2C state sequencer configuring 10 internal registers for 48 kHz, 16-bit stereo line-in audio.
   - Master clock generation ($50\text{ MHz} / 4 = 12.5\text{ MHz}$ `AUD_XCK`).
2. **Philips I2S Audio Streaming Receiver:**
   - Bit-synchronized serial-to-parallel converter capturing 16-bit signed two's complement PCM audio samples.
3. **Dual-Bank Ping-Pong Sample Buffer:**
   - Zero-drop continuous sample streaming with seamless acquisition/computation overlapping.
4. **Hardware Hanning Spectral Windowing:**
   - 16-bit fixed-point sinusoidal window ROM suppressing spectral leakage and side-lobe distortion.
5. **Radix-2 DIF FFT Processing Core:**
   - Scalable 64/256/512-point pipelined FFT engine with fixed-point twiddle factor generation.
6. **Alpha-Max Beta-Min (AMBM) Magnitude Approximator:**
   - Ultra-low-latency Euclidean magnitude estimation ($|X| \approx \max + \frac{3}{8}\min$) with $<3\%$ peak error and zero multiplier or square-root overhead.
7. **6-Band Psychoacoustic Energy Extractor:**
   - Sub-band bin accumulation across Sub-Bass, Bass, Low-Mid, Midrange, High-Mid, and High-Frequency bands.
8. **Deterministic Acoustic Noise Classifier:**
   - Decision-tree classifier categorizing environments (`QUIET`, `SPEECH`, `LOW-FREQ`, `HIGH-FREQ`, `NOISE`) in a single clock cycle.
9. **Real-Time 60 Hz VGA Visualizer:**
   - 640x480 active raster display rendering 6 gradient equalizer columns with persistent peak-hold falling indicators.
10. **Onboard Synthetic DDS Audio Generator:**
    - Direct Digital Synthesis tone generator ($1\text{ kHz}, 2\text{ kHz}, 5\text{ kHz}$ sines, silence, Galois LFSR white noise) for 100% bench testing without external audio equipment.

---

## 3. Directory Structure

```
project_05_audio/
├── README.md                  # Project overview and quick start guide
├── docs/                      # Complete 9-file engineering documentation suite
│   ├── PRD.md                 # Product Requirements Document
│   ├── ARCHITECTURE.md        # System Architecture & DSP Pipeline
│   ├── RTL_DESIGN.md          # RTL Module Specifications & Register Maps
│   ├── VERIFICATION.md        # Verification Strategy & Test Scenarios
│   ├── HARDWARE_SETUP.md      # Physical DE2-115 Wiring & Codec Guidelines
│   ├── PINOUT.md              # FPGA Pin Assignments & Voltage Standards
│   ├── TEST_REPORT.md         # Simulation & Bench Test Results
│   ├── KNOWN_LIMITATIONS.md   # Architectural Boundaries & Edge Cases
│   └── FINAL_REPORT.md        # Comprehensive Portfolio Closeout Report
├── rtl/                       # Synthesizable Verilog-2001 Source Code
│   ├── audio_top.v            # Top-Level Integration Module
│   ├── audio_pingpong_buffer.v# Dual-Bank Sample Buffer
│   ├── hanning_window.v       # Hanning Windowing ROM & Multiplier
│   ├── fft_radix2_core.v      # Radix-2 DIF FFT Processor
│   ├── magnitude_approximator.v # AMBM Euclidean Magnitude Unit
│   ├── spectral_band_extractor.v# 6-Band Energy Accumulator
│   ├── noise_classifier.v     # Acoustic Scene Classification Engine
│   ├── vga_spectrum_display.v # 640x480 60Hz VGA Equalizer Renderer
│   ├── audio_uart_logger.v    # 115200 Baud Telemetry Broadcaster
│   └── sine_lut_generator.v   # DDS Tone & White Noise Generator
├── sim/                       # Simulation Testbenches
│   └── tb_audio_top.v         # Full System Self-Checking Testbench
├── python/                    # Python DSP Reference Model
│   └── audio_dsp_ref.py       # NumPy/SciPy Reference Implementation
└── quartus/                   # Intel Quartus Prime Synthesis Project
    ├── audio_top.qpf          # Quartus Project File
    ├── audio_top.qsf          # Quartus Settings & Pin Assignments
    └── audio_top.sdc          # Synopsys Timing Constraints
```

---

## 4. Quick Start & Verification

### Running Automated Simulation (Icarus Verilog)
```bash
# Run standalone Project 5 verification
iverilog -g2001 -o test_audio.vvp project_05_audio/sim/tb_audio_top.v project_05_audio/rtl/*.v common/rtl/*.v
vvp test_audio.vvp

# Run master regression suite across all 5 projects
python tools/simulation/run_all_tests.py
```

### Running Python DSP Reference Model
```bash
python project_05_audio/python/audio_dsp_ref.py
```

### Target Hardware Mapping (DE2-115)
- **Primary Clock:** 50 MHz Oscillator (`PIN_Y2`)
- **Reset:** Active-Low Pushbutton `KEY[0]` (`PIN_M23`)
- **Reconfigure Codec:** Pushbutton `KEY[1]` (`PIN_M21`)
- **Synthetic Audio Mode:** Slide Switch `SW[17]` (`PIN_Y23`)
- **Synthetic Tone Select:** `SW[16:14]` (`000`: Silence, `001`: 1kHz, `010`: 2kHz, `011`: 5kHz, `100`: Noise)
- **VGA Output:** 15-pin D-Sub connector to monitor (640x480 @ 60Hz)
- **Audio In:** Line-In 3.5mm jack (blue) connected to audio source
- **Audio Out:** Line-Out 3.5mm jack (green) connected to headphones/speakers
