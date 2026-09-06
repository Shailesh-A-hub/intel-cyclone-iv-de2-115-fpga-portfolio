# Project 3: Smart Adaptive Irrigation System using FPGA

**Target FPGA:** Altera / Intel Cyclone IV EP4CE115F29C7 (Terasic DE2-115)  
**HDL Standard:** IEEE 1364-2001 Verilog  
**Verification:** 100% PASS (12/12 Testbench Scenarios)  

---

### Project Overview
This project implements an intelligent, closed-loop precision agricultural irrigation decision controller on the DE2-115 FPGA board. Rather than relying on a brittle static soil moisture threshold, the system continuously computes an **adaptive moisture trigger threshold** adjusted in real time based on ambient temperature and relative humidity vapor pressure deficit trends.

```
Soil Moisture (SPI ADC) ──┐
DHT11 Temperature ───────┤
DHT11 Humidity ──────────┤
Rain Sensor (Digital) ───┤
                         ↓
             Sensor Conditioning & Filtering
                         ↓
            Adaptive Threshold Engine (Q8.8)
                         ↓
            Pump Controller FSM (Hysteresis & Interlocks)
                         ↓
         Relay Driver Output / Status Telemetry
```

### Directory Structure
```
project_03_irrigation/
├── rtl/
│   ├── irrigation_top.v             # Top-level DE2-115 hardware integration
│   ├── dht11_controller.v           # 1-Wire protocol master with CRC check
│   ├── soil_moisture_adc_reader.v   # MCP3008 SPI ADC reader & inversion
│   ├── adaptive_threshold_engine.v  # Dynamic threshold calculation (Q8.8)
│   ├── pump_controller_fsm.v        # State machine with safety timers
│   └── irrigation_uart_logger.v     # 115200 baud ASCII telemetry logger
├── sim/
│   └── tb_irrigation_top.v          # 12-scenario self-checking testbench
├── python/
│   └── irrigation_ref.py            # Reference mathematical model & verification
├── quartus/
│   ├── irrigation_top.qpf           # Quartus project file
│   ├── irrigation_top.qsf           # Pin assignments & device constraints
│   └── irrigation_top.sdc           # Timing constraints (50 MHz)
└── docs/
    ├── PRD.md                       # Product Requirements Document
    ├── ARCHITECTURE.md              # System architecture & mathematical models
    ├── RTL_DESIGN.md                # Detailed RTL & arithmetic specification
    ├── VERIFICATION.md              # Verification plan & test coverage
    ├── HARDWARE_SETUP.md            # Wiring guide & electrical isolation
    ├── PINOUT.md                    # DE2-115 physical pin mapping table
    ├── TEST_REPORT.md               # Simulation test execution results
    ├── KNOWN_LIMITATIONS.md         # Hardware constraints & mitigations
    └── FINAL_REPORT.md              # Comprehensive 23-section academic report
```

### Key Technical Features
1. **Adaptive Moisture Threshold Engine:** Dynamically calculates:
   $$T_{\text{adaptive}} = T_{\text{base}} + \Delta T_{\text{temp}} - \Delta H_{\text{humid}}$$
   clamped safely between $20\%$ and $75\%$ moisture.
2. **Dedicated Single-Wire DHT11 Protocol Engine:** Microsecond-precision bidirectional 1-wire FSM providing robust start pulses, 40-bit bitstream decoding, and hardware checksum verification with timeout recovery.
3. **Robust Relay Interlocks:** Hardware-enforced minimum run-time ($15\text{ s}$ hardware / $3\text{ ms}$ sim) and minimum rest-time ($30\text{ s}$ hardware / $5\text{ ms}$ sim) prevent pump motor short-cycling and relay contact pitting.
4. **Multi-Hazard Lockouts:** Immediate pump abort upon rain detection (`rain_detected = 1`) or critical sensor failure (ADC disconnect, DHT11 bus timeout, CRC failure).
5. **Dual Operation Modes:** Supports physical sensors (MCP3008 ADC + DHT11) or full synthetic slide-switch override mode (`SW[17] = 1`) for laboratory testing.

### Verification
Run the 12-scenario self-checking regression test:
```bash
python tools/simulation/run_all_tests.py
```
Or directly via Icarus Verilog:
```bash
iverilog -o sim_irrigation.vvp -I common/rtl -I project_03_irrigation/rtl project_03_irrigation/sim/tb_irrigation_top.v project_03_irrigation/rtl/*.v common/rtl/reset_synchronizer.v common/rtl/button_debounce.v common/rtl/spi_master.v common/rtl/lcd_hd44780_controller.v common/rtl/seven_seg_dec.v common/rtl/periodic_timer.v common/rtl/uart_tx.v
vvp sim_irrigation.vvp
```
All 12 test cases pass with zero errors.
