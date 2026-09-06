# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Verification Plan

## 1. Verification Strategy
Verification of Project 4 validates both low-level serial communication (I2C protocol transactions with an APDS-9960) and high-level menu navigation logic.
- **Behavioral APDS-9960 I2C Slave Model:** Implements a full register map in simulation responding to I2C Start, Address Write, Sub-address Pointer, Restart, and Data Read.
- **Synthetic Stimulus Generation:** Uses debounced pushbuttons and switches to inject direct gesture vectors (`UP`, `DOWN`, `LEFT`, `RIGHT`, `NEAR`, `FAR`).
- **Comprehensive Scenario Coverage:** 21 automated self-checking assertions covering menu boundary wrap-around, submenu navigation, parameter toggles, timeout recovery, and multi-display outputs.

---

## 2. Testbench Test Cases Matrix

| Case # | Scenario Description | Stimulus Profile | Expected Outcome | Verification Status |
|---|---|---|---|---|
| **TC1** | System Reset & Initialization | Assert `KEY[0] = 0` for 50 cycles | FSM starts at `STATUS`, submenu idle, count=0 | **PASS** |
| **TC2a** | Menu DOWN Navigation (Step 1) | Pulse DOWN (`KEY[1]`) | Menu transitions to `SETTINGS` (idx 1) | **PASS** |
| **TC2b** | Menu DOWN Navigation (Step 2) | Pulse DOWN (`KEY[1]`) | Menu transitions to `SENSORS` (idx 2) | **PASS** |
| **TC2c** | Menu DOWN Navigation (Step 3) | Pulse DOWN (`KEY[1]`) | Menu transitions to `ABOUT` (idx 3) | **PASS** |
| **TC2d** | Menu DOWN Boundary Wrap-around | Pulse DOWN at `ABOUT` | Menu wraps around to `STATUS` (idx 0) | **PASS** |
| **TC3a** | Menu UP Boundary Wrap-around | Pulse UP (`KEY[2]`) at `STATUS` | Menu wraps around to `ABOUT` (idx 3) | **PASS** |
| **TC3b** | Menu UP Navigation (Step 1) | Pulse UP (`KEY[2]`) | Menu transitions to `SENSORS` (idx 2) | **PASS** |
| **TC3c** | Menu UP Navigation (Step 2) | Pulse UP (`KEY[2]`) | Menu transitions to `SETTINGS` (idx 1) | **PASS** |
| **TC4** | Submenu Entry | Pulse RIGHT (`KEY[3]`) | Enters `in_submenu = 1`, page=0 | **PASS** |
| **TC5a** | Submenu Parameter Toggle (Backlight) | Pulse RIGHT inside Submenu | Backlight cycles HIGH $\rightarrow$ LOW (0) | **PASS** |
| **TC5b** | Submenu Page Scroll | Pulse DOWN inside Submenu | Submenu page increments to 1 (Buzzer) | **PASS** |
| **TC5c** | Submenu Parameter Toggle (Buzzer) | Pulse RIGHT on Page 1 | Beep setting toggles ON $\rightarrow$ MUTED | **PASS** |
| **TC6** | Submenu Exit Navigation | Pulse LEFT (`SW[16]`) | Exits `in_submenu = 0`, stays at `SETTINGS` | **PASS** |
| **TC7a** | NEAR Gesture Submenu Entry | Pulse NEAR (`SW[15]`) | Enters submenu cleanly | **PASS** |
| **TC7b** | FAR Gesture Submenu Exit | Pulse FAR (`SW[14]`) | Exits submenu back to Main Menu | **PASS** |
| **TC8a** | Inactivity Timeout Entry Prep | Pulse RIGHT into Submenu | Confirms active in submenu | **PASS** |
| **TC8b** | Inactivity Timeout Auto-Exit | Advance inactivity counter past limit | FSM automatically returns to Main Menu | **PASS** |
| **TC9** | Rapid Repeated Input Filter | Multiple key pulses in 10 cycles | Refractory filter maintains counter stability | **PASS** |
| **TC10** | LCD Buffer ASCII Verification | Inspect `lcd_line1` register | Valid non-zero formatted string | **PASS** |
| **TC11** | VGA Sync & Active Video Verification | Inspect `VGA_HS`, `VGA_BLANK_N` | Continuous active 60Hz timing signals | **PASS** |
| **TC12** | UART Line Idle & Frame Integrity | Complete transmission wait | `UART_TXD` returns to idle high (`1'b1`) | **PASS** |

---

## 3. Regression Execution
Executed under Icarus Verilog v12.0 and Python test runner `tools/simulation/run_all_tests.py`:
- Total Test Cases: 21
- Passed: 21
- Failed: 0
- Status: **100% PASS**
