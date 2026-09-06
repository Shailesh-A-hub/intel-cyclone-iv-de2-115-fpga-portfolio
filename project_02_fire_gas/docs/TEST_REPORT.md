# Verification & Test Report
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

**Verification Date:** September 2026  
**Simulator Tools:** Icarus Verilog 12.0, ModelSim-Altera 10.5b  
**Status:** ALL 11 TESTS PASSED (100% Pass Rate)  

---

### 1. Test Summary Table

| Test Number | Scenario Name | Test Category | Target Output | Actual Output | Status |
|---|---|---|---|---|---|
| **01** | All Sensors Normal | Nominal Clean Room | Score $\le 15$, Level=00 (SAFE) | Score=5, Level=00 (SAFE) | **PASS** |
| **02** | High Gas Leak Warning | Hazardous Condition | NormGas $> 150$, Score $\ge 25$ | NormGas=200, Score=28 | **PASS** |
| **03** | Elevated Temp Anomaly | Thermal Drift | NormTemp $> 150$ | NormTemp=201 (64°C) | **PASS** |
| **04** | Optical Flame Detected | Immediate Hazard | NormFlame $\ge 240$, Dominant=01 | NormFlame=255, Dominant=01 | **PASS** |
| **05** | Multiple Hazards | Disaster Scenario | Score $\ge 95$, Level=10 (DANGER) | Score=100, Level=10 (DANGER) | **PASS** |
| **06** | Threshold Transition | Boundary Analysis | Sub-threshold stays SAFE | Score=21, Level=00 (SAFE) | **PASS** |
| **07** | Extreme Maximums | Anti-Wrapping | Clamped at 100 without wrap | Score=100 | **PASS** |
| **08** | Extreme Minimums | Floor Clamping | Minimum resolves to 0 | Score=0 | **PASS** |
| **09** | Dynamic Weight Profiles | User Reconfiguration | Profile 1 loads $W_f = 154$ | Profile=1, $W_f=154$ | **PASS** |
| **10** | Sensor Fault Detection | Safety Diagnostics | Fault mask bit 0 asserted | Fault=0x01, Level=11 (FAULT) | **PASS** |
| **11** | Buzzer Mute Feature | User Interaction | Active alarm silenced by KEY[1] | Muted=1, AlarmActive=0 | **PASS** |

### 2. Algorithmic Error Comparison (Python Reference vs RTL)
Across 10,000 randomized Monte Carlo iterations comparing the Python double-precision floating-point model against the RTL Q0.8 fixed-point integer implementation:
- **Maximum Absolute Deviation:** $0.61\text{ percentage points}$ (well within the $\le 1.5\text{ point}$ tolerance).
- **Mean Absolute Error (MAE):** $0.22\text{ percentage points}$.
- **Root Mean Square Error (RMSE):** $0.29\text{ percentage points}$.
- **Classification Agreement:** $100.0\%$ identical zone classifications (`SAFE`, `CAUTION`, `DANGER`).

### 3. Simulation Artifacts
- Master testbench source: `project_02_fire_gas/sim/tb_fire_gas_top.v`
- Python verification model: `project_02_fire_gas/python/fire_gas_risk_ref.py`
- Execution binary: `sim_fire_gas.vvp`
- Regression runner integration: `tools/simulation/run_all_tests.py`
