# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classifier — PRD

## 1. Problem Statement
Real-time audio spectral analysis and acoustic environmental monitoring are vital capabilities in industrial noise pollution assessment, speech recognition front-ends, hearing aids, automotive cabin acoustics, and structural vibration diagnosis. Microcontroller and embedded CPU implementations suffer from jitter, limited DMA bandwidth, and high latency when computing multi-point Fast Fourier Transforms while concurrently driving high-resolution video graphics. An FPGA-based architecture delivers deterministic pipelined DSP throughput, zero-drop sample streaming, parallel psychoacoustic energy extraction, and flicker-free 60 Hz visual rendering.

---

## 2. Project Goals & Scope
Design, verify, and implement a synthesizable real-time audio spectrum analysis and acoustic scene classification system on the Intel Cyclone IV EP4CE115 FPGA. The system ingests 48 kHz stereo audio via the onboard Wolfson WM8731 codec, performs dual-buffered FFT analysis with Hanning windowing, computes vector magnitudes using Alpha-Max Beta-Min approximation, calculates psychoacoustic sub-band energies, executes real-time noise classification, and drives multi-modal visual (VGA, LCD, 7-Segment) and serial (UART) telemetry.

---

## 3. Target Users & Operating Scenarios
- **Industrial Safety & Environmental Health:** Continuous acoustic monitoring to detect hazardous workplace noise thresholds and mechanical failure signatures.
- **Smart Building Automation & Voice Activation:** Distinguishing human speech from background HVAC rumble and high-frequency screeching to trigger building events.
- **Audio Engineering & Studio Monitoring:** Real-time visual frequency spectrum equalizer with peak-hold monitoring for audio mixing consoles.

---

## 4. Functional Requirements

### 4.1 Audio Ingestion & Codec Configuration
- **FR-01 (I2C Codec Configuration):** The system shall automatically configure the Wolfson WM8731 codec over I2C at power-up into 48 kHz, 16-bit stereo I2S slave mode by sequencing 10 internal control registers.
- **FR-02 (Codec Master Clock):** The FPGA shall generate a clean 12.5 MHz master clock (`AUD_XCK`) from the onboard 50 MHz crystal oscillator.
- **FR-03 (I2S Streaming):** The I2S receiver shall capture 16-bit signed two's complement PCM audio samples synchronized to `AUD_BCLK` and `AUD_ADCLRCK`.

### 4.2 DSP & Spectral Analysis Pipeline
- **FR-04 (Ping-Pong Buffering):** Audio samples shall be acquired into a dual-bank ping-pong buffer allowing seamless acquisition while the previous frame is processed.
- **FR-05 (Spectral Windowing):** A 16-bit Hanning window ROM shall attenuate boundary discontinuities and eliminate spectral leakage.
- **FR-06 (Radix-2 DIF FFT):** The core shall compute a Fast Fourier Transform across 64/256/512 points with fixed-point twiddle factors.
- **FR-07 (AMBM Magnitude Approximation):** The system shall estimate Euclidean vector magnitude using the Alpha-Max Beta-Min algorithm:
  $$|X| \approx \max(|I|, |Q|) + \frac{3}{8}\min(|I|, |Q|)$$
  with zero multiplier or division overhead.
- **FR-08 (6-Band Psychoacoustic Extraction):** The extractor shall sum bin magnitudes into 6 discrete psychoacoustic frequency bands:
  - Band 0: Sub-Bass / Rumble ($0 - 250\text{ Hz}$)
  - Band 1: Bass ($250 - 500\text{ Hz}$)
  - Band 2: Low-Mid / Fundamental Speech ($500 - 1000\text{ Hz}$)
  - Band 3: Midrange / Speech Formants ($1000 - 2500\text{ Hz}$)
  - Band 4: High-Mid / Consonants ($2500 - 5000\text{ Hz}$)
  - Band 5: High-Frequency / Noise ($5000 - 24000\text{ Hz}$)
- **FR-09 (Deterministic Noise Classification):** The classifier shall categorize the frame into one of 5 states:
  - `QUIET` (Class 0): Total energy $< \text{Threshold}_{\text{quiet}}$
  - `SPEECH` (Class 1): Energy concentrated in speech bands (Bands 2 & 3)
  - `LOW-FREQ` (Class 2): Energy concentrated in rumble bands (Bands 0 & 1)
  - `HIGH-FREQ` (Class 3): Energy concentrated in screeching bands (Bands 4 & 5)
  - `NOISE` (Class 4): Broad, flat energy distribution across all bands.

### 4.3 Multi-Modal Feedback & Visualization
- **FR-10 (60 Hz VGA Equalizer):** The VGA controller shall render 6 dynamic multi-colored gradient bar graphs (Green $\rightarrow$ Yellow $\rightarrow$ Red) corresponding to the 6 frequency bands, featuring decaying peak-hold markers.
- **FR-11 (Character LCD):** The HD44780 16x2 LCD shall display the current acoustic classification name, total frame energy, and dominant peak frequency bin.
- **FR-12 (7-Segment & LEDs):** HEX displays shall render numerical energy metrics; LEDR shall display the 18-bit instantaneous audio level meter; LEDG shall show system status.
- **FR-13 (UART Telemetry):** The logger shall transmit 115200 baud ASCII status strings once per frame.
- **FR-14 (Synthetic Direct Digital Synthesis Mode):** Controlled by `SW[17]`, the FPGA shall generate synthetic test signals ($1\text{ kHz}, 2\text{ kHz}, 5\text{ kHz}$ pure sine tones, silence, Galois LFSR pseudo-random white noise) for 100% bench testability.

---

## 5. Non-Functional Requirements
- **Clock Domain:** Single global 50 MHz clock (`CLOCK_50`), with derived 25 MHz pixel clock and 12.5 MHz codec clock.
- **Processing Latency:** End-to-end spectral transformation and classification latency $< 2\text{ ms}$ per audio frame.
- **VGA Refresh:** Deterministic 60 Hz frame rate with zero dropped frames or display artifacts.
- **FPGA Utilization:** Total logic consumption $< 6,000$ Cyclone IV Logic Elements (<6% of EP4CE115).

---

## 6. Acceptance Criteria
- 100% test pass rate across all 18 automated simulation scenarios in `tb_audio_top.v`.
- Clean timing closure at 50 MHz under TimeQuest Static Timing Analysis.
- Verified physical pin mapping matching Terasic DE2-115 schematics.
