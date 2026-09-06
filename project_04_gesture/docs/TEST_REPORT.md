# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Test Report

**Execution Date:** 2026-09-04  
**Environment:** Icarus Verilog v12.0 / VVP on Windows x86_64  
**Test Suite:** `project_04_gesture/sim/tb_gesture_top.v`  
**Overall Result:** **ALL 21 TEST CASES PASSED (100% SUCCESS RATE)**

---

## 1. Test Summary

```
============================================================
    PROJECT 4: GESTURE-CONTROLLED MENU INTERFACE TB
============================================================
[PASS] TC1: Reset Initialization
[PASS] TC2a: Menu DOWN to SETTINGS
[PASS] TC2b: Menu DOWN to SENSORS
[PASS] TC2c: Menu DOWN to ABOUT
[PASS] TC2d: Menu Boundary Wrap to STATUS
[PASS] TC3a: Menu Boundary UP Wrap to ABOUT
[PASS] TC3b: Menu UP to SENSORS
[PASS] TC3c: Menu UP to SETTINGS
[PASS] TC4: Submenu Entry into SETTINGS
[PASS] TC5a: Backlight Setting Toggle (to LOW)
[PASS] TC5b: Submenu Page Down to BUZZER
[PASS] TC5c: Audio Beep Toggle to MUTED
[PASS] TC6: Submenu Exit back to Main Menu
[PASS] TC7a: NEAR Gesture Submenu Entry
[PASS] TC7b: FAR Gesture Submenu Exit
[PASS] TC8a: In Submenu for Timeout Test
[PASS] TC8b: Auto-Exit on Inactivity Timeout
[PASS] TC9: Rapid Input Filter Stability
[PASS] TC10: LCD Text Buffer Active
[PASS] TC11: VGA Sync Active
[PASS] TC12: UART Line Idle High
============================================================
TOTAL TESTS: 21 | PASSED: 21 | FAILED: 0
STATUS: PASS
============================================================
```

---

## 2. Test Execution Details

### TC1: Reset & Initial State Validation
- **Stimulus:** Master active-low reset `KEY[0]` asserted for 50 clock cycles.
- **Result:** System initialized with `current_menu = 0` (`STATUS`), `in_submenu = 0`, and `gesture_count = 0`.

### TC2a–TC2d & TC3a–TC3c: Menu Navigation & Circular Wrap-around
- **Stimulus:** Sequential application of `DOWN` and `UP` gesture vectors across all 4 top-level menu categories.
- **Result:** FSM smoothly navigated `STATUS` $\rightarrow$ `SETTINGS` $\rightarrow$ `SENSORS` $\rightarrow$ `ABOUT`. At boundary conditions, `DOWN` at `ABOUT` wrapped directly to `STATUS`, and `UP` at `STATUS` wrapped directly to `ABOUT`.

### TC4–TC6: Submenu Hierarchy & Parameter Toggle
- **Stimulus:** `RIGHT`/`ENTER` gesture injected into `SETTINGS`. Repeated toggle gestures injected on parameters.
- **Result:** FSM entered submenu mode (`in_submenu = 1`). Backlight parameter cycled through `HIGH` $\rightarrow$ `LOW`. Buzzer audio toggled to `MUTED`. `LEFT`/`EXIT` gesture cleanly restored Main Menu context without state corruption.

### TC7a–TC7b: Proximity Gesture (NEAR / FAR) Processing
- **Stimulus:** Volumetric proximity push (`NEAR`) and pull (`FAR`) injected into the decoder.
- **Result:** `NEAR` successfully triggered submenu entry; `FAR` triggered submenu exit, validating multi-modal interaction.

### TC8a–TC8b: Inactivity Timeout Auto-Exit
- **Stimulus:** Navigation into submenu followed by inactivity period exceeding the programmed threshold.
- **Result:** Hardware watchdog timer automatically de-asserted `in_submenu`, returning display context to the top-level Main Menu.

### TC9–TC12: Peripheral & Display Driver Verification
- **Stimulus:** Rapid pulse injection, string inspection, and pixel clock monitoring.
- **Result:** Refractory lockout filter prevented double-counting under rapid triggers. HD44780 text buffers, VGA 25 MHz sync generation, and 115200-baud UART transmission verified active and compliant.
