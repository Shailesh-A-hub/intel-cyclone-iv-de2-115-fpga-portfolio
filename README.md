# Team Details
**Team Name:** ControlAltDelete
**Members & Registration Numbers:**
1. Shailesh - 24BEC0655
2. Pradeep P - 24BVD0206

**FPGA Board:** Terasic DE2-115 (Intel Cyclone IV EP4CE115F29C7)

---

# Intel Cyclone IV (DE2-115) 5-Project FPGA Engineering Portfolio

[![Verification Status](https://img.shields.io/badge/Regression%20Suite-17%2F17%20PASS%20(100%25)-brightgreen.svg)](tools/simulation/run_all_tests.py)
[![FPGA Family](https://img.shields.io/badge/Target%20Device-Altera%2FIntel%20Cyclone%20IV%20EP4CE115F29C7-blue.svg)](docs/master_pin_map.csv)
[![HDL Standard](https://img.shields.io/badge/HDL-Verilog--2001%20%2F%20SystemVerilog-orange.svg)](common/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

---

## 1. Portfolio Overview

This repository hosts a production-grade, multi-domain digital design portfolio developed for the **Terasic DE2-115 Development Board** featuring the **Intel Cyclone IV EP4CE115F29C7 FPGA**.

The portfolio is architected upon a shared **20-module parameterized reusable IP platform layer** and comprises **5 full-scale, fully verified engineering projects** spanning industrial automation, life-safety sensor fusion, precision agriculture, touchless human-machine interfaces, and real-time DSP audio spectral analysis.

---

## 2. Project Portfolio Summary

| # | Project Name | Focus Domain | Key Hardware & Protocols | Status |
|---|---|---|---|---|
| **01** | [**Multi-Zone Occupancy & Energy Management Engine**](project_01_occupancy/) | Smart Infrastructure | 4-Zone PIR, Day/Night Sensor, Dual Timers, 3-Stage Relay Sequencer, LCD, UART | **100% PASS** (8/8 Tests) |
| **02** | [**Adaptive Multi-Sensor Fire & Combustible Gas Risk Scoring Engine**](project_02_fire_gas/) | Life Safety & Hazard Mitigation | MCP3008 SPI ADC, MQ-2/MQ-7/Thermistor/Flame, Q0.8 Fixed-Point Fusion, Multi-Cadence Siren | **100% PASS** (11/11 Tests) |
| **03** | [**Smart Adaptive Agricultural Irrigation Control System**](project_03_irrigation/) | Environmental Control | DHT11 1-Wire, MCP3008 SPI ADC, Evapotranspiration Compensation, Motor Safety Interlocks | **100% PASS** (12/12 Tests) |
| **04** | [**FPGA-Based Gesture-Controlled Multi-Display Menu Interface**](project_04_gesture/) | Touchless HMI & Video Graphics | Broadcom APDS-9960 I2C Driver, Vector Classifier, Multi-Tier Menu FSM, 640x480 @ 60Hz VGA | **100% PASS** (21/21 Tests) |
| **05** | [**Real-Time Audio Spectrum Analyzer & Noise Classification Engine**](project_05_audio/) | Mixed-Signal DSP (Flagship) | Wolfson WM8731 I2C/I2S, Dual Ping-Pong RAM, Hanning Window, Radix-2 FFT, AMBM Magnitude, 6-Band Equalizer | **100% PASS** (18/18 Tests) |

---

## 3. Platform Architecture & Reusable IP Layer (`common/`)

The platform layer provides 20 modular, highly parameterizable Verilog-2001 IP blocks:
- **Core Clocks & Resets:** `reset_synchronizer.v`, `clock_divider.v`, `edge_detector.v`
- **User Interface & Timing:** `button_debounce.v`, `timer_ms.v`, `timer_sec.v`, `periodic_timer.v`, `timeout_timer.v`, `pwm_generator.v`
- **Display Controllers:** `seven_seg_hex.v`, `seven_seg_dec.v`, `lcd_hd44780_controller.v`, `vga_timing_controller.v`
- **Serial Protocols:** `uart_tx.v`, `uart_rx.v`, `spi_master.v`, `i2c_master.v`, `i2s_receiver.v`, `wm8731_configurator.v`

---

## 4. Verification & Regression Runner

The complete test suite is automated through `tools/simulation/run_all_tests.py` and compatible with **Icarus Verilog (`iverilog`/`vvp`)** and **ModelSim-Intel (`vsim`)**.

### Execute Full Regression Suite:
```bash
python tools/simulation/run_all_tests.py
```

### Execution Output:
```
======================================================================
 DE2-115 FPGA PORTFOLIO - COMMON PLATFORM REGRESSION SUITE
======================================================================
[*] Running testbench: tb_reset_synchronizer ................. PASS (0.19s)
[*] Running testbench: tb_clock_divider ...................... PASS (0.18s)
[*] Running testbench: tb_button_debounce .................... PASS (0.17s)
[*] Running testbench: tb_edge_detector ...................... PASS (0.19s)
[*] Running testbench: tb_seven_seg .......................... PASS (0.17s)
[*] Running testbench: tb_timers ............................. PASS (0.17s)
[*] Running testbench: tb_pwm_generator ...................... PASS (0.20s)
[*] Running testbench: tb_uart ............................... PASS (0.22s)
[*] Running testbench: tb_spi_master ......................... PASS (0.19s)
[*] Running testbench: tb_i2c_master ......................... PASS (0.18s)
[*] Running testbench: tb_vga_timing_controller .............. PASS (0.18s)
[*] Running testbench: tb_i2s_receiver ....................... PASS (0.18s)
[*] Running testbench: tb_occupancy_top (Project 1) .......... PASS (13.24s)
[*] Running testbench: tb_fire_gas_top (Project 2) ........... PASS (3.10s)
[*] Running testbench: tb_irrigation_top (Project 3) ......... PASS (6.11s)
[*] Running testbench: tb_gesture_top (Project 4) ............ PASS (6.24s)
[*] Running testbench: tb_audio_top (Project 5) .............. PASS (12.65s)
======================================================================
Total Testbenches: 17 | Passed: 17 | Failed: 0 (100% PASS)
======================================================================
```

---

## 5. Repository Directory Layout

```
buildx/
├── LICENSE                        # MIT Open Source License
├── README.md                      # Master Portfolio Overview
├── common/                        # Reusable Platform IP Layer
│   ├── rtl/                       # 20 Parameterized Verilog Modules
│   └── sim/                       # 12 Unit Testbenches
├── docs/                          # Architecture & Portfolio Documentation
│   ├── master_pin_map.csv         # Master DE2-115 Peripheral Pin Map
│   ├── PROGRESS.md                # Phase & Milestone Live Progress Tracker
│   └── DECISIONS.md               # 14 Architectural Decision Records (ADR)
├── project_01_occupancy/          # Project 1: Multi-Zone Occupancy Engine
├── project_02_fire_gas/           # Project 2: Adaptive Fire & Gas Risk Engine
├── project_03_irrigation/         # Project 3: Smart Irrigation Controller
├── project_04_gesture/            # Project 4: Gesture Menu & VGA Interface
├── project_05_audio/              # Project 5: Real-Time Audio Spectrum Analyzer (Flagship)
└── tools/                         # Automated Simulation & Build Tools
    └── simulation/
        └── run_all_tests.py       # Master Regression Runner
```

---

## 6. Synthesis & Timing Closure

All 5 projects include complete Intel Quartus Prime synthesis setups:
- Quartus Project Files (`.qpf`)
- Exact Cyclone IV pin and I/O standard assignments (`.qsf`)
- Synopsys Design Timing Constraints (`.sdc`) achieving timing closure with positive slack on all clock domains.
