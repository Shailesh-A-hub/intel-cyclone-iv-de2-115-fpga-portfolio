# Project 3: Smart Adaptive Irrigation System — Test Report

**Execution Date:** 2026-09-04  
**Environment:** Icarus Verilog v12.0 / VVP on Windows x86_64  
**Test Suite:** `project_03_irrigation/sim/tb_irrigation_top.v`  
**Overall Result:** **ALL 12 TEST CASES PASSED (100% SUCCESS RATE)**

---

## 1. Test Summary

```
============================================================
           SMART ADAPTIVE IRRIGATION REGRESSION
============================================================
TC1:  Reset & Idle Initialization                  [PASS]
TC2:  Nominal Ambient (Adaptive Boost)             [PASS]
TC3:  Hot & Dry Stress Adaptive Elevation         [PASS]
TC4:  Cool & Humid Threshold Depression            [PASS]
TC5:  Dry Soil Detection & Pump ON Activation      [PASS]
TC6:  Minimum Run-Time Interlock Hold              [PASS]
TC7:  Moisture Satisfied & Transition to Rest      [PASS]
TC8:  Minimum Rest-Time Interlock Lockout          [PASS]
TC9:  Rain Sensor Immediate Abort Interlock        [PASS]
TC10: Manual Override Immediate Priority           [PASS]
TC11: DHT11 1-Wire Checksum Error Diagnostic       [PASS]
TC12: SPI ADC Communication Fault Diagnostic       [PASS]
============================================================
TOTAL TESTS: 12 | PASSED: 12 | FAILED: 0 | STATUS: PASS
============================================================
```

---

## 2. Detailed Test Results & Timing Verification

### TC1: Reset & Idle Initialization
- **Stimulus:** De-asserted `KEY[0]` low for $200\text{ ns}$.
- **Result:** FSM entered `ST_OFF_READY`. Relay output remained de-energized (`0`). All internal cycle timers and error flags cleared to zero.

### TC2 - TC4: Adaptive Threshold Engine Accuracy
- **Stimulus:** Varied ambient parameters ($T_{\text{temp}} = 32^\circ\text{C}, H = 45\%$; $T_{\text{temp}} = 42^\circ\text{C}, H = 20\%$; $T_{\text{temp}} = 20^\circ\text{C}, H = 85\%$).
- **Result:** Computed threshold matched mathematical reference model within $\pm 0\%$ quantization error:
  - Nominal: $35 + 3 - 0 = 38\%$
  - Hot/Dry: $35 + 8 - 0 = 43\%$
  - Cool/Humid: $35 + 0 - 5 = 30\%$

### TC5 - TC8: Pump Control, Hysteresis, and Interlocks
- **Stimulus:** Driven dry soil ($25\%$) triggering pump. Attempted early shutdown after $1\text{ ms}$ of run-time.
- **Result:** Pump engaged cleanly. When soil moisture immediately reported $60\%$, the minimum run-time interlock held the relay energised until $T_{\text{min\_on}}$ expired. Once shut down, a subsequent dry soil pulse was locked out until $T_{\text{min\_off}}$ expired, validating motor contactor protection.

### TC9: Rain Lockout
- **Stimulus:** Asserted `rain_in = 1` while pump actively running.
- **Result:** Relay output shut down within 1 clock cycle ($20\text{ ns}$), transitioning FSM to `ST_RAIN_LOCKOUT` and illuminating `LEDR[17]`.

### TC10: Manual Override
- **Stimulus:** Toggled `SW[16] = 1`.
- **Result:** FSM transitioned immediately to `ST_MANUAL_OVERRIDE`, overriding automatic soil moisture hysteresis.

### TC11 & TC12: Fault Injection & Diagnostics
- **Stimulus:** Injected DHT11 single-wire checksum inversion and SPI ADC rail saturation.
- **Result:** Checksum mismatch correctly asserted `dht_checksum_err` without crashing the FSM. ADC rail fault asserted `adc_fault` and transitioned the pump controller to safe state `ST_SENSOR_FAULT`.
