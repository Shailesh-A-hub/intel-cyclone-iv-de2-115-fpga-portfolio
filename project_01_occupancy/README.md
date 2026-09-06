# Project 1: Multi-Zone Occupancy & Energy-Saving Decision Engine
**Platform**: Terasic DE2-115 (Cyclone IV EP4CE115F29C7)  
**HDL**: Verilog-2001  
**Status**: `SIMULATED: VERIFIED (100%)` | `SYNTHESIS CONFIG: PREPARED`

---

## Overview
Project 1 is an FPGA-based decision engine that coordinates human occupancy detection across 4 independent building zones to dynamically control lighting relays, multi-stage HVAC equipment, and variable-speed ventilation fans. It continuously accumulates real-time energy savings in Watt-hours compared to an unmanaged 2.2 kW baseline building load.

---

## Key Features
- **4 Independent Zone FSMs**: Each zone maintains `VACANT`, `OCCUPIED`, and `TIMEOUT` states with motion retriggering.
- **Configurable Timeouts**: Runtime selectable (5s, 30s, 60s, 300s) via `SW[17:16]`.
- **Proportional HVAC Staging**:
  - 0 Zones: OFF (0 W)
  - 1 Zone: LOW (600 W, saves 1000 W)
  - 2-3 Zones: MED (1100 W, saves 500 W)
  - 4 Zones: HIGH (1600 W, full load)
- **Variable-Speed PWM Ventilation**: 0%, 40%, 70%, 100% duty cycle.
- **Ambient Light Lockout**: Gates lights off during daylight even if occupied (`SW[4]`).
- **Telemetry & Display**: 7-segment displays (`HEX0..HEX7`), 16x2 HD44780 LCD, and 115200-baud UART stream.

---

## Directory Structure
- `rtl/`: Synthesizable Verilog sources (`occupancy_top.v`, `zone_fsm.v`, `energy_decision_engine.v`, `occupancy_uart_logger.v`).
- `sim/`: Self-checking testbench (`tb_occupancy_top.v`) testing all 8 required scenarios.
- `quartus/`: Intel Quartus Prime project files (`occupancy_top.qpf`, `occupancy_top.qsf`, `occupancy_top.sdc`).
- `docs/`: Complete engineering documentation suite (PRD, ARCHITECTURE, RTL_DESIGN, VERIFICATION, PINOUT, HARDWARE_SETUP, TEST_REPORT, KNOWN_LIMITATIONS, FINAL_REPORT).

---

## Running Verification
```powershell
iverilog -g2001 -o sim_p1.vvp `
  project_01_occupancy/sim/tb_occupancy_top.v `
  project_01_occupancy/rtl/occupancy_top.v `
  project_01_occupancy/rtl/zone_fsm.v `
  project_01_occupancy/rtl/energy_decision_engine.v `
  project_01_occupancy/rtl/occupancy_uart_logger.v `
  common/rtl/reset_synchronizer.v `
  common/rtl/button_debounce.v `
  common/rtl/timer_ms.v `
  common/rtl/timer_sec.v `
  common/rtl/seven_seg_hex.v `
  common/rtl/seven_seg_dec.v `
  common/rtl/pwm_generator.v `
  common/rtl/lcd_hd44780_controller.v `
  common/rtl/uart_tx.v

vvp sim_p1.vvp
```
