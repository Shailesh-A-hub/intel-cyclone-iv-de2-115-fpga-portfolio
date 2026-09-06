# Verification Plan & Methodology
## Project 1 - Multi-Zone Occupancy & Energy Decision Engine

---

## 1. Verification Strategy
Verification of the multi-zone occupancy decision engine combines self-checking unit tests and multi-zone integration testbenches. The integration testbench stimulates the top-level entity across all operational boundaries, sensor fault conditions, and physical timing thresholds.

## 2. Test Cases & Acceptance Matrix

| Case | Test Description | Stimulus | Expected Output | Status |
|---|---|---|---|---|
| **TC1** | No Occupancy | All sensors 0 | All zones vacant, HVAC OFF, Fan OFF, Lights OFF | **PASS** |
| **TC2** | Single Zone Occupied | PIR Zone 1 = 1 | Zone 1 occupied, HVAC LOW (stage 1), Lights ON (if dark) | **PASS** |
| **TC3** | Multiple Zones Occupied | PIR Zone 1 & 3 = 1 | 2 active zones, HVAC MED (stage 2), Fan ~70% duty | **PASS** |
| **TC4** | Simultaneous Triggers | All 4 PIRs = 1 | 4 active zones, HVAC HIGH (stage 3), Fan 100% duty | **PASS** |
| **TC5** | Motion Retrigger | Motion re-asserted in TIMEOUT | Countdown reloads to preset without dropping to vacant | **PASS** |
| **TC6** | Timeout Expiration | Motion ceases past preset | Countdown reaches 0, zone transitions to VACANT | **PASS** |
| **TC7** | Glitch Rejection | Narrow pulses (<10ms) | Debouncer filters pulses; zone remains vacant | **PASS** |
| **TC8** | Counter Saturation | Energy accumulator wrap | Handles upper bounds cleanly, sets overflow flag | **PASS** |

## 3. Simulation Command
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
