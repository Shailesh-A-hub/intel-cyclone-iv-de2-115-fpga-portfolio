# Project 4: FPGA-Based Gesture-Controlled Menu Interface

**Target FPGA:** Altera / Intel Cyclone IV EP4CE115F29C7 (Terasic DE2-115)  
**HDL Standard:** IEEE 1364-2001 Verilog  
**Verification:** 100% PASS (21/21 Testbench Scenarios)  

---

### Project Overview
This project implements an optical spatial gesture recognition engine and interactive multi-tiered menu navigation interface on the DE2-115 development board. It interfaces with an external Broadcom / Avago APDS-9960 gesture sensor via a custom hardware I2C master driver, tracks real-time spatial differential trajectories across 4 integrated infrared photodiodes (Up, Down, Left, Right), decodes complex physical hand motions, and drives both a character HD44780 16x2 LCD and a 640x480 @ 60Hz graphical VGA dashboard.

```
+--------------------+
| APDS-9960 Sensor   |
| (4x IR Photodiode) |
+---------+----------+
          |
          | I2C (100 kHz SCL / SDA)
          v
+--------------------+
| apds9960_i2c_driver| (Config Engine & FIFO Polling)
+---------+----------+
          |
          | 4-Channel Stream: (U, D, L, R)
          v
+--------------------+
|  gesture_decoder   | (Phase Vector Tracker & Directional Classifier)
+---------+----------+
          |
          | Classified Gesture Events: UP, DOWN, LEFT, RIGHT, NEAR, FAR
          v
+--------------------+
|      menu_fsm      | (Hierarchical Navigation, Cursor, Parameter Toggles)
+----+----------+----+
     |          |
     v          v
+---------+  +-------------------+  +---------------+  +---------------+
| HD44780 |  |  vga_menu_display |  | 8x 7-Segment  |  | UART Logger   |
| 16x2 LCD|  |  (640x480 @ 60Hz) |  | HEX0 - HEX7   |  | (115200 Baud) |
+---------+  +-------------------+  +---------------+  +---------------+
```

### Directory Structure
```
project_04_gesture/
├── rtl/
│   ├── gesture_top.v            # Top-level DE2-115 system integration
│   ├── apds9960_i2c_driver.v    # Hardware I2C master & APDS register driver
│   ├── gesture_decoder.v        # Multi-axis trajectory differential decoder
│   ├── menu_fsm.v               # Hierarchical menu state machine & LCD formatter
│   ├── vga_menu_display.v       # 640x480 @ 60Hz graphical VGA renderer
│   └── gesture_uart_logger.v    # 115200 baud ASCII serial telemetry logger
├── sim/
│   └── tb_gesture_top.v         # 21-scenario self-checking testbench with I2C model
├── quartus/
│   ├── gesture_top.qpf          # Quartus project file
│   ├── gesture_top.qsf          # Pin assignments & device constraints
│   └── gesture_top.sdc          # Timing constraints (50 MHz sys & 25 MHz pixel)
└── docs/
    ├── PRD.md                   # Product Requirements Document
    ├── ARCHITECTURE.md          # System architecture & trajectory classification
    ├── RTL_DESIGN.md            # Detailed RTL specification
    ├── VERIFICATION.md          # Verification plan & test coverage
    ├── HARDWARE_SETUP.md        # Wiring guide & bench testing procedures
    ├── PINOUT.md                # Pin mapping table
    ├── TEST_REPORT.md           # Simulation test execution results
    ├── KNOWN_LIMITATIONS.md     # Hardware constraints & mitigations
    └── FINAL_REPORT.md          # Comprehensive 23-section academic report
```

### Key Technical Features
1. **Hardware I2C Driver & Auto-Sequencer:** Executes power-up sequencing, reads device ID (`0xAB`), configures gesture proximity entry/exit thresholds and gain registers, and polls the internal 32-dataset FIFO.
2. **Phase Vector Spatial Decoder:** Analyzes differential entry and exit profiles ($\Delta_{\text{UD}} = U - D$ and $\Delta_{\text{LR}} = L - R$) to distinguish directional swipes (`UP`, `DOWN`, `LEFT`, `RIGHT`) and volumetric proximity depth (`NEAR`, `FAR`).
3. **Hierarchical 4-Category Menu FSM:** Navigates `STATUS`, `SETTINGS`, `SENSORS`, and `ABOUT` menus, supports cursor wrap-around, submenus, dynamic parameter toggles (backlight, audio beep, timeout), and inactivity auto-exit timers.
4. **Dual Visual Displays:** Drives both the onboard 16x2 character LCD and a 24-bit 640x480 60Hz VGA dashboard featuring animated selection cards, live photodiode bar graphs, and gesture telemetry badges.
5. **Deterministic Bench Injection Mode:** Provides instant slide-switch synthetic validation (`SW[17] = 1`) utilizing onboard pushbuttons (`KEY[3:1]`) for bench testing without physical sensor daughterboards.

### Verification
Run the 21-scenario self-checking regression test:
```bash
python tools/simulation/run_all_tests.py
```
Or directly via Icarus Verilog:
```bash
iverilog -o sim_gesture.vvp -I common/rtl -I project_04_gesture/rtl project_04_gesture/sim/tb_gesture_top.v project_04_gesture/rtl/*.v common/rtl/reset_synchronizer.v common/rtl/button_debounce.v common/rtl/edge_detector.v common/rtl/i2c_master.v common/rtl/lcd_hd44780_controller.v common/rtl/vga_timing_controller.v common/rtl/seven_seg_hex.v common/rtl/seven_seg_dec.v common/rtl/periodic_timer.v common/rtl/uart_tx.v
vvp sim_gesture.vvp
```
All 21 test cases pass with zero errors.
