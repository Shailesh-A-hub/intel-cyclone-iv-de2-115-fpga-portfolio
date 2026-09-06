# Verification Methodology & Test Plan
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### 1. Verification Strategy
Verification followed a disciplined 3-tier approach:
1. **Mathematical Reference Modeling (Python):** Floating-point ground truth compared against fixed-point Q0.8 integer arithmetic to quantify quantization noise.
2. **Behavioral Protocol Modeling:** Behavioral MCP3008 10-bit SPI ADC slave responder responding to physical SPI cycles in simulation.
3. **Integration Testbench Verification (Verilog):** 11 self-checking scenarios executed in Icarus Verilog (`iverilog`) and ModelSim-Altera 10.5b (`vsim`).

### 2. Comprehensive Test Scenarios

| Test Case | Description | Stimulus Profile | Expected Behavior | Result |
|---|---|---|---|---|
| **TC-1** | Clean Room Baseline | Gas=120, Temp=80, Flame=950, Hum=700 | Score=5, Level=SAFE, Green LEDs active, Buzzer silent | **PASS** |
| **TC-2** | Combustible Gas Leak | Gas=650, Temp=80, Flame=950, Hum=700 | Score=28, NormGas=200, Elevated hazard detected | **PASS** |
| **TC-3** | Elevated Temperature | Gas=120, Temp=200, Flame=950, Hum=700 | NormTemp=201, Temp=64°C | **PASS** |
| **TC-4** | Optical Flame Detection | Gas=120, Temp=80, Flame=150, Hum=700 | NormFlame=255, Dominant hazard=Flame (01) | **PASS** |
| **TC-5** | Simultaneous Hazards | Gas=850, Temp=250, Flame=100, Hum=150 | Score=100, Level=DANGER, Red flashing LEDs, siren active | **PASS** |
| **TC-6** | Threshold Boundaries | Gas=280, Temp=120, Flame=900, Hum=600 | Sub-threshold boundary verification (Score=21, SAFE) | **PASS** |
| **TC-7** | Maximum Saturation | All sensors at extreme fire limits | Saturated at Score=100 without wrapping or overflow | **PASS** |
| **TC-8** | Minimum Boundary | All sensors at ultra-clean lower limits | Resolves cleanly to Score=0 | **PASS** |
| **TC-9** | Dynamic Weight Profiles | KEY[2] profile switch toggled | Profile toggles to Flame-Centric ($W_f = 154$), verified in hardware | **PASS** |
| **TC-10** | Sensor Fault Diagnostics | Gas sensor disconnected (raw=0) via synthetic fault | Fault mask `5'b00001` asserted, Level=FAULT, display dashes | **PASS** |
| **TC-11** | Buzzer Alarm Mute | Active hazard alarm followed by KEY[1] mute press | Alarm successfully silenced (`alarm_active = 0`, `muted = 1`) | **PASS** |

### 3. Execution Commands
To re-run the entire Project 2 verification suite independently:
```bash
iverilog -o sim_fire_gas.vvp -I common/rtl -I project_02_fire_gas/rtl project_02_fire_gas/sim/tb_fire_gas_top.v project_02_fire_gas/rtl/*.v common/rtl/reset_synchronizer.v common/rtl/button_debounce.v common/rtl/spi_master.v common/rtl/pwm_generator.v common/rtl/lcd_hd44780_controller.v common/rtl/seven_seg_dec.v common/rtl/periodic_timer.v common/rtl/uart_tx.v
vvp sim_fire_gas.vvp
```

To run the master regression suite including all projects and common IP:
```bash
python tools/simulation/run_all_tests.py
```
