# Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

**Target FPGA:** Altera / Intel Cyclone IV EP4CE115F29C7 (Terasic DE2-115)  
**HDL Standard:** IEEE 1364-2001 Verilog  
**Verification:** 100% PASS (11/11 Testbench Scenarios)  

---

### Project Overview
This project implements a real-time, deterministic hardware sensor fusion engine that continuously converts multiple environmental analog metrics (combustible gas, ambient temperature, optical IR flame, and relative humidity) into a composite risk score ($0–100$) using Q0.8 fixed-point arithmetic.

```
Gas ───────────┐
Temperature ───┤
Flame ─────────┤
Humidity ──────┤
↓
Sensor Normalization (Pipelined)
↓
Weighted Risk Engine (Q0.8 Fixed-Point)
↓
Composite Risk Score 0–100
↓
Threshold Classification
↓
┌─────────────┼─────────────┐
↓             ↓             ↓
SAFE         CAUTION       DANGER
```

### Directory Structure
```
project_02_fire_gas/
├── rtl/
│   ├── fire_gas_top.v              # Top-level DE2-115 integration
│   ├── mcp3008_adc_controller.v    # 4-channel SPI ADC master with watchdog
│   ├── sensor_normalizer.v         # 2-stage calibration & fault detector
│   ├── risk_engine_q8_8.v          # Fixed-point Q0.8 weighted fusion engine
│   ├── alarm_buzzer_controller.v   # Multi-cadence PWM siren with mute
│   └── fire_gas_uart_logger.v      # 115200 baud ASCII serial telemetry
├── sim/
│   └── tb_fire_gas_top.v           # 11-scenario self-checking testbench
├── python/
│   └── fire_gas_risk_ref.py        # Python floating-point reference model
├── quartus/
│   ├── fire_gas_top.qpf            # Quartus project file
│   ├── fire_gas_top.qsf            # Pin assignments & device configuration
│   └── fire_gas_top.sdc            # Timing constraints (50 MHz)
└── docs/
    ├── PRD.md                      # Product Requirements Document
    ├── ARCHITECTURE.md             # System architecture & dataflow
    ├── RTL_DESIGN.md               # Detailed RTL & arithmetic specification
    ├── VERIFICATION.md             # Verification plan & test coverage
    ├── HARDWARE_SETUP.md           # Wiring guide & bench testing
    ├── PINOUT.md                   # Pin mapping table
    ├── TEST_REPORT.md              # Test execution results
    ├── KNOWN_LIMITATIONS.md        # Hardware limitations & mitigations
    └── FINAL_REPORT.md             # 23-section final academic report
```

### Key Technical Features
1. **Pipelined Normalization:** Maps 10-bit raw ADC readings to 8-bit dynamic metrics with baseline offsets and clamping.
2. **Deterministic Fixed-Point Engine:** Sub-$100\text{ ns}$ pipeline latency using Q0.8 unsigned weights ($\sum W_i = 256$) with unbiased rounding.
3. **Hardware Fault Diagnostics:** Automatically isolates disconnected, shorted, or rail-saturated sensors and communication watchdogs.
4. **Synthetic Simulation Mode:** Complete physical board testing without hazardous open flames or toxic gases via onboard slide switches (`SW[17] = 1`).
5. **Multi-Protocol I/O:** Interfaces with SPI, PWM, UART (115200 baud), HD44780 16x2 LCD, 8x 7-segment decimal displays, and status LEDs.

### Verification
Run the self-checking testbench:
```bash
iverilog -o sim_fire_gas.vvp -I common/rtl -I project_02_fire_gas/rtl project_02_fire_gas/sim/tb_fire_gas_top.v project_02_fire_gas/rtl/*.v common/rtl/reset_synchronizer.v common/rtl/button_debounce.v common/rtl/spi_master.v common/rtl/pwm_generator.v common/rtl/lcd_hd44780_controller.v common/rtl/seven_seg_dec.v common/rtl/periodic_timer.v common/rtl/uart_tx.v
vvp sim_fire_gas.vvp
```
All 11 test cases pass with zero failures.
