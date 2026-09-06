# Project 3: Smart Adaptive Irrigation System — Verification Plan

## 1. Verification Strategy

Verification of the Smart Adaptive Irrigation System employs a multi-tier approach:
1. **Mathematical Reference Model Validation:** A Python floating-point and integer fixed-point model (`python/irrigation_ref.py`) verifies the adaptive threshold and hysteresis math across the entire envelope:
   - Soil moisture: $0–100\%$
   - Temperature: $0–60^\circ\text{C}$
   - Humidity: $10–100\%$
   - Base thresholds: $20–60\%$
2. **Behavioral Sensor Simulation:** The integration testbench (`sim/tb_irrigation_top.v`) implements behavioral simulation models:
   - `DHT11` responder model providing accurate low-pulse handshake, byte formatting, and checksum calculation.
   - `MCP3008` SPI slave model returning 10-bit ADC samples matching commanded channels.
3. **End-to-End System-Level Scenarios:** 12 automated test cases verify all operational modes, safety timers, and fault conditions.

---

## 2. Testbench Test Cases Matrix

| Case # | Scenario Description | Stimulus Profile | Expected Outcome | Verification Status |
|---|---|---|---|---|
| **TC1** | System Reset & Initialization | Assert `reset_n = 0` for 200 ns | Outputs idle, pump OFF, counters cleared | **PASS** |
| **TC2** | Nominal Warm Ambient (Adaptive Boost) | $T = 32^\circ\text{C}, H = 45\%$, Base $= 35\%$ | Adaptive threshold calculates to $38\%$ | **PASS** |
| **TC3** | Hot & Dry Stress Condition | $T = 42^\circ\text{C}, H = 20\%$ | Adaptive threshold rises to $43\%$ | **PASS** |
| **TC4** | Cool & Humid Condition | $T = 20^\circ\text{C}, H = 85\%$ | Adaptive threshold drops to $30\%$ | **PASS** |
| **TC5** | Dry Soil Pump Trigger | Moisture drops to $25\%$ ($< T_{\text{adapt}} - 3$) | FSM transitions to `ST_PUMP_ON`, relay active | **PASS** |
| **TC6** | Minimum Run-Time Lockout | Moisture rises to $60\%$ immediately | Pump remains ON until $T_{\text{min\_on}}$ elapses | **PASS** |
| **TC7** | Moisture Satisfied Shutdown | $T_{\text{min\_on}}$ expires, Moisture $= 60\%$ | Pump turns OFF, enters `ST_MIN_OFF_WAIT` | **PASS** |
| **TC8** | Minimum Rest-Time Enforcement | Moisture drops to $20\%$ during rest | Pump held OFF until $T_{\text{min\_off}}$ elapses | **PASS** |
| **TC9** | Rain Sensor Immediate Abort | Rain signal asserted while pump is ON | Immediate transition to `ST_RAIN_LOCKOUT` | **PASS** |
| **TC10** | Manual Override Priority | Manual override switch toggled | Immediate forced ON, override takes precedence | **PASS** |
| **TC11** | DHT11 Checksum Error Detection | Invert checksum byte in 1-Wire response | `dht_checksum_err = 1`, logs error | **PASS** |
| **TC12** | ADC Fault Detection | Drive ADC disconnected / rail error | `adc_fault = 1`, enters `ST_SENSOR_FAULT` | **PASS** |

---

## 3. Coverage Analysis
- **FSM State Coverage:** 100% of states in `pump_controller_fsm` reached and exited (`ST_OFF_READY`, `ST_PUMP_ON`, `ST_MIN_OFF_WAIT`, `ST_RAIN_LOCKOUT`, `ST_SENSOR_FAULT`, `ST_MANUAL_OVERRIDE`).
- **Boundary Conditions:** Moisture clamped at $0\%$ and $100\%$, threshold clamped at $20\%$ and $75\%$.
- **Timer Interlocks:** Minimum run-time and minimum rest-time timer counters verified to the exact clock cycle.
