# Product Requirements Document (PRD)
## Project 3: Smart Adaptive Irrigation System

**Author:** FPGA Portfolio Lead Engineer  
**Target Platform:** Altera / Intel DE2-115 Development Board (Cyclone IV EP4CE115F29C7)  
**Status:** Verified & Released  

---

### 1. Problem Statement
Agricultural automation and smart landscaping systems frequently suffer from either excessive water waste or under-watering due to rigid, static soil moisture thresholds. Fixed-threshold irrigation ignores ambient microclimate dynamics: on hot, dry afternoons, soil moisture depletes rapidly through plant evapotranspiration, whereas humid, overcast conditions retard moisture loss. Furthermore, improper pump cycling damages pump motors through short-cycling and wastes power during rainstorms. An autonomous, deterministic FPGA-based irrigation engine is required to adapt soil moisture thresholds based on real-time temperature and humidity trends while enforcing mechanical safety runtimes and sensor fault lockouts.

### 2. Objective
Design, implement, verify, and prepare for physical hardware execution a synthesizable Smart Adaptive Irrigation System on the DE2-115 FPGA that:
1. Samples soil moisture percentage using an external 10-bit SPI ADC (Microchip MCP3008).
2. Interrogates a DHT11 / DHT22 temperature and humidity sensor using a dedicated microsecond-resolution 1-wire state machine.
3. Computes a dynamic, adaptive soil moisture threshold influenced mathematically by ambient temperature and relative humidity trends.
4. Controls a pump/valve relay with dual-threshold hysteresis ($TH_{on}$ vs $TH_{off}$), minimum ON time protection ($T_{min\_on}$), and minimum OFF rest time protection ($T_{min\_off}$).
5. Enforces immediate rain sensor lockout and prioritized manual override.
6. Displays live environmental metrics on a 16x2 HD44780 LCD, 8x 7-segment decimal displays, and status LEDs, while streaming telemetry over 115200 baud UART.

### 3. Users & Use Cases
- **Precision Agriculture & Greenhouses:** Regulating drip irrigation in commercial nurseries based on canopy microclimate.
- **Smart City Landscaping:** Municipal parks and highway verge irrigation preventing water runoff during rainstorms.
- **Embedded FPGA Engineers & Students:** Practical demonstration of mixed-signal SPI ADC integration, custom 1-wire timing protocols, hysteresis FSMs, and safety-critical control.

### 4. Functional Requirements
- **FR-1 Soil Moisture Sensing:** Periodically sample MCP3008 SPI ADC Channel 0 at $\ge 10\text{ Hz}$, converting raw 10-bit analog values into calibrated soil moisture percentage ($0..100\%$).
- **FR-2 Custom 1-Wire Protocol:** Implement a dedicated finite state machine for DHT11 single-wire communication with $18\text{ ms}$ start pulses, $40\text{ bit}$ pulse-width demodulation, and 8-bit checksum verification.
- **FR-3 Adaptive Threshold Engine:** Dynamically calculate the irrigation threshold:
  $$\text{TargetThreshold} = \text{clamp}(\text{BaseThreshold} + \text{TempAdj} + \text{HumAdj}, 25\%, 75\%)$$
  where $\text{TempAdj} = \min(15, \max(0, T - 25))$ and $\text{HumAdj} = \min(10, \max(0, (50 - H)/2))$.
- **FR-4 Dual-Threshold Hysteresis:**
  $$\text{Turn-On} = \max(5, \text{Threshold} - 5\%)$$
  $$\text{Turn-Off} = \min(95, \text{Threshold} + 5\%)$$
  Inside the deadband $[\text{Turn-On}, \text{Turn-Off})$, the pump maintains its previous state to prevent chattering.
- **FR-5 Pump Runtime Protection:**
  - Enforce minimum ON duration ($T_{min\_on} \ge 5\text{ s}$) to prevent motor short-cycling.
  - Enforce minimum OFF rest period ($T_{min\_off} \ge 10\text{ s}$) for water soil permeation and winding cool-down.
- **FR-6 Rain Sensor Lockout:** Active rain signal immediately de-energizes pump, aborts active watering, and resets timers.
- **FR-7 Manual Override:** Dedicated switch / button forcing pump ON immediately, secondary only to rain lockout.
- **FR-8 Diagnostics & Fault Handling:** Detect open/short soil ADC conditions, DHT11 checksum errors, and communication timeouts.
- **FR-9 Watering Statistics:** Accumulate total watering activations and cumulative runtime seconds.
- **FR-10 Multi-Modal Outputs:** 16x2 HD44780 LCD, 8x 7-segment decimal displays, status LEDs, and 115200 baud ASCII UART telemetry.

### 5. Non-Functional Requirements
- **Single Clock Domain:** $50.000\text{ MHz}$ global oscillator (`CLOCK_50`).
- **Synthesis:** Fully synthesizable Verilog-2001 code targeting Intel Cyclone IV EP4CE115.
- **Safety:** Never drive an inductive relay coil or pump directly from FPGA pins; all GPIO outputs buffered with transistors or optocouplers.

### 6. Acceptance Criteria
- 100% PASS rate across all 12 self-checking testbench scenarios in Icarus Verilog and ModelSim.
- Full timing closure at $50\text{ MHz}$ ($> 10\text{ ns}$ positive slack).
- Complete Quartus project and pin mapping verified against official DE2-115 master constraints.
