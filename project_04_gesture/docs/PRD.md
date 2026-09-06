# Project 4: FPGA-Based Gesture-Controlled Menu Interface — PRD

## 1. Problem Statement
Traditional human-machine interfaces (HMIs) relying on physical pushbuttons, rotary encoders, or resistive touchscreens suffer from mechanical fatigue, contact degradation, dust contamination, and hygiene risks in sterile or industrial settings. Optical spatial gesture sensing offers a touch-free alternative, but microcontroller implementations often suffer from high interrupt latency, non-deterministic scheduling, and limited display bandwidth. A hardware FPGA architecture provides microsecond-level optical sampling, deterministic trajectory decoding, and simultaneous multi-display driving (character LCD and 60 Hz VGA).

## 2. Objective
Design, implement, verify, and prepare for synthesis a complete gesture-controlled menu interface on the Intel Cyclone IV EP4CE115 FPGA (DE2-115). The system interfaces with an external APDS-9960 sensor over I2C, classifies hand motions into 6 distinct gestures, navigates a multi-tier menu structure, and renders real-time visual output across both a 16x2 character LCD and a 640x480 @ 60Hz VGA monitor.

## 3. Target Users & Use Cases
- **Industrial Automation:** Touchless machine control in environments where operators wear heavy work gloves.
- **Medical & Cleanroom Instrumentation:** Contactless sterile menu navigation eliminating bio-contamination.
- **Consumer Electronics & Smart Displays:** Modern touch-free user interfaces.

## 4. Functional Requirements
1. **I2C Protocol Master:** Initialize and control the APDS-9960 sensor at $100\text{ kHz}$ (or $400\text{ kHz}$ fast mode).
2. **Gesture Decoding Engine:** Continuously process 4-channel photodiode data ($U, D, L, R$) and classify motions into:
   - `UP`, `DOWN`, `LEFT`, `RIGHT`, `NEAR`, `FAR`.
3. **Hierarchical Menu State Machine:**
   - 4 Main Menu items: `STATUS`, `SETTINGS`, `SENSORS`, `ABOUT`.
   - Submenu navigation: Enter via `RIGHT`/`NEAR`, Exit via `LEFT`/`FAR`, Scroll via `UP`/`DOWN`.
   - Dynamic parameter adjustments: LCD Backlight Level, Audio Beeper Enable, Inactivity Timeout.
   - Automatic Inactivity Timeout: Returns to Main Menu after a user-selectable duration (10s, 20s, 30s).
4. **Display Controllers:**
   - Onboard HD44780 16x2 character LCD displaying dynamic menus, sensor values, and cursor hints.
   - 640x480 @ 60Hz VGA display rendering a full graphical dashboard with glowing selection cards and real-time photodiode bar graphs.
5. **Serial Telemetry Logger:** 115200 baud RS-232 UART output broadcasting structured event logs and status heartbeats.
6. **Synthetic Simulation Mode:** Complete bench testing using onboard switches (`SW[17] = 1`) and pushbuttons (`KEY[3:1]`).

## 5. Non-Functional Requirements
- **Clock Domain:** Single global 50 MHz clock (`CLOCK_50`), with derived 25 MHz pixel clock for VGA DAC.
- **Latency:** Gesture event classification latency $< 20\text{ ms}$ from completion of physical hand swipe.
- **Refractory Lockout:** Hardware-enforced refractory delay ($250\text{ ms}$ HW / $1\text{ ms}$ sim) to prevent double-triggering.
- **Resource Utilization:** Fit within $< 2,000$ Cyclone IV Logic Elements (<2% of EP4CE115).

## 6. System Inputs & Outputs
- **Inputs:**
  - `CLOCK_50`: 50 MHz crystal oscillator.
  - `KEY[0]`: Active-low master asynchronous reset.
  - `KEY[3:1]`: Pushbuttons for synthetic gesture entry (`ENTER`, `UP`, `DOWN`).
  - `SW[17:0]`: Synthetic mode toggle, gesture selection, and sensor offsets.
  - `GPIO[1:0]`: I2C open-drain lines (SCL, SDA).
  - `GPIO[2]`: Active-low interrupt line from APDS-9960.
- **Outputs:**
  - `LCD_*`: 8-bit parallel bus and control signals for HD44780 16x2 LCD.
  - `VGA_*`: ADV7123 24-bit RGB video DAC lines and sync strobes.
  - `HEX0 - HEX7`: 8x 7-segment decimal/hexadecimal status displays.
  - `LEDR[17:0]` & `LEDG[8:0]`: Visual indicators for gestures, menu states, and sensor signals.
  - `UART_TXD`: 115200 baud serial telemetry stream.

## 7. Assumptions & Safety Interlocks
- APDS-9960 daughterboard contains proper $4.7\text{ k}\Omega$ pull-up resistors on SCL and SDA lines to $3.3\text{ V}$.
- Power supply to external daughterboard is strictly $3.3\text{ V}$ (provided by JP5 Pin 29) to prevent FPGA I/O overvoltage.
- I2C bus error handler provides automatic recovery and status reporting without hanging the Menu FSM.

## 8. Acceptance Criteria
- 100% pass on all 21 automated simulation testbench scenarios.
- Zero timing violations under 50 MHz static timing analysis in Quartus.
- Verified menu navigation, parameter adjustment, and display update in simulation and synthesis configurations.
