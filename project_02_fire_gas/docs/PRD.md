# Product Requirements Document (PRD)
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

**Author:** FPGA Portfolio Engineering Lead  
**Target Platform:** Altera / Intel DE2-115 Development Board (Cyclone IV EP4CE115F29C7)  
**Status:** Verified & Released  

---

### 1. Problem Statement
Industrial facilities, chemical warehouses, server rooms, and residential buildings face catastrophic risks from fire and combustible gas leaks. Traditional single-sensor fire detectors rely on crude, fixed thresholds (e.g., thermal rise or smoke opacity alone), suffering from frequent false alarms or delayed detection. There is a pressing need for a hard real-time, deterministic hardware sensor fusion engine on FPGA that continuously computes a composite risk score from multi-spectral environmental inputs (combustible gas, thermal gradient, optical IR flame signature, and relative humidity) using fixed-point arithmetic, dynamic weight configuration, and hardware fault diagnostics.

### 2. Objective
Design, verify, and implement a synthesizable FPGA sensor-fusion decision engine that:
1. Samples an external 8-channel 10-bit SPI ADC (Microchip MCP3008) across multiple environmental sensor channels.
2. Normalizes raw ADC readings to an 8-bit dynamic range ($0–255$) with calibrated baselines and noise clamping.
3. Computes a real-time weighted composite risk score ($0–100$) using Q0.8 fixed-point arithmetic without floating-point latencies.
4. Classifies system operational status into discrete hazard zones: `SAFE`, `CAUTION`, `DANGER`, and `SENSOR_FAULT`.
5. Controls auditory warning cadences (piezo buzzer PWM), visual status indicators (8x 7-segment displays, multi-color LEDs, 16x2 HD44780 LCD), and real-time ASCII serial telemetry over UART.
6. Provides a synthetic test and fault injection mode enabling physical board testing without requiring hazardous open flames or toxic gases.

### 3. Users & Use Cases
- **Industrial Safety & Process Automation:** Chemical storage, refineries, and server clusters requiring sub-millisecond hazard triage.
- **Academic & Embedded Research:** Demonstrating hardware sensor fusion, fixed-point DSP math, and multi-protocol hardware interfaces (SPI, UART, PWM, HD44780).
- **Embedded Hardware Engineers:** Portfolio demonstration of safety-critical RTL design and comprehensive self-checking verification.

### 4. Functional Requirements
- **FR-1 Multi-Channel Acquisition:** Periodically query 4 channels of MCP3008 SPI ADC (CH0: Gas, CH1: Temperature, CH2: Optical Flame, CH3: Humidity) at $\ge 10\text{ Hz}$.
- **FR-2 Piecewise Normalization:** Convert 10-bit raw ADC readings into normalized 8-bit values ($0..255$) with baseline offsets and upper saturation clamping.
- **FR-3 Fixed-Point Weighted Scoring:** Calculate composite risk:
  $$\text{RiskScore} = W_g \cdot \text{GasNorm} + W_t \cdot \text{TempNorm} + W_f \cdot \text{FlameNorm} + W_h \cdot \text{HumNorm}$$
  using Q0.8 integer arithmetic ($\sum W_i = 256$) scaled to $0..100$.
- **FR-4 Threshold Classification:**
  - $0 \le \text{Score} \le 34$: `SAFE`
  - $35 \le \text{Score} \le 69$: `CAUTION`
  - $70 \le \text{Score} \le 100$: `DANGER`
  - Active sensor fault: `FAULT`
- **FR-5 Hardware Fault Detection:** Detect open-circuit, short-circuit, rail-saturation, and SPI communication watchdog timeouts.
- **FR-6 Multi-Mode Buzzer Cadence:**
  - `SAFE`: Silent ($0\%$ duty cycle).
  - `CAUTION`: Intermittent $1.0\text{ kHz}$ chirp ($100\text{ ms}$ on, $900\text{ ms}$ off).
  - `DANGER`: High-priority dual-tone alternating siren ($2.0\text{ kHz} \leftrightarrow 2.5\text{ kHz}$ toggling every $250\text{ ms}$).
  - `FAULT`: Low-frequency pulse ($500\text{ Hz}$, $100\text{ ms}$ on, $100\text{ ms}$ off).
  - Pushbutton mute/acknowledge with automatic unmute on new hazard escalation.
- **FR-7 Visual Displays:**
  - 8x 7-Segment displays: Score (HEX1-0), Gas % (HEX3-2), Temp °C (HEX5-4), Flame % (HEX7-6).
  - 16x2 LCD: Line 1 shows live metrics; Line 2 shows Risk Score and status banner.
  - LEDs: Green (Safe), Amber (Caution), Red flashing at $4\text{ Hz}$ (Danger).
- **FR-8 Telemetry Logging:** Stream human-readable ASCII packets over UART at 115200 baud, 8N1 once per second.
- **FR-9 Synthetic Simulation Mode:** Switch-selectable override allowing slider control and fault injection via onboard switches.

### 5. Non-Functional Requirements
- **Clock Domain:** Single synchronous clock domain ($50\text{ MHz}$, `CLOCK_50`).
- **Timing Margin:** Positive setup/hold slack for $50\text{ MHz}$ target ($T_{cyc} = 20\text{ ns}$).
- **Portability:** Fully synthesizable IEEE 1364-2001 Verilog RTL with parameterized clock frequency and timebases.
- **Safety:** Zero direct relay drive from FPGA pins; all GPIO outputs buffered or optocoupled.

### 6. Acceptance Criteria
- 100% PASS rate across all 11 integration testbench scenarios in Icarus Verilog and ModelSim regressions.
- Maximum arithmetic error between floating-point software model and fixed-point hardware engine $\le 1.0$ point out of 100.
- Complete Quartus project and pin mapping verified against official DE2-115 master constraints.
