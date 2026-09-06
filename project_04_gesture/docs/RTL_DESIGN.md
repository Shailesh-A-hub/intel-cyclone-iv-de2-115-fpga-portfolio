# Project 4: FPGA-Based Gesture-Controlled Menu Interface — RTL Design

## 1. Module Hierarchy

```
gesture_top
│
├── reset_synchronizer (common/rtl/reset_synchronizer.v)
├── button_debounce [x3: KEY3, KEY2, KEY1] (common/rtl/button_debounce.v)
├── periodic_timer [x2: 1-sec & 100ms ticks] (common/rtl/periodic_timer.v)
│
├── apds9960_i2c_driver (project_04_gesture/rtl/apds9960_i2c_driver.v)
│   └── i2c_master (common/rtl/i2c_master.v)
│
├── gesture_decoder (project_04_gesture/rtl/gesture_decoder.v)
│
├── menu_fsm (project_04_gesture/rtl/menu_fsm.v)
│
├── lcd_hd44780_controller (common/rtl/lcd_hd44780_controller.v)
│
├── vga_menu_display (project_04_gesture/rtl/vga_menu_display.v)
│   └── vga_timing_controller (common/rtl/vga_timing_controller.v)
│
├── gesture_uart_logger (project_04_gesture/rtl/gesture_uart_logger.v)
│   └── uart_tx (common/rtl/uart_tx.v)
│
└── seven_seg_hex & seven_seg_dec [HEX7 - HEX0] (common/rtl/)
```

---

## 2. Detailed RTL Descriptions

### 2.1 `apds9960_i2c_driver.v`
- **I2C Sequencing:**
  - `ST_RESET`: Awaits power-up stabilization ($10\text{ ms}$).
  - `ST_READ_ID_CMD`: Reads register `0x92` (ID). Verifies silicon ID `0xAB` (or `0x9C`, `0xA8`).
  - `ST_CONFIG_STEP`: Automates write cycles across 8 configuration registers:
    - `0x80` (ENABLE): `8'h01` (Power ON)
    - `0xA0` (GPENTH): `8'h28` (40 threshold)
    - `0xA1` (GEXTH): `8'h1E` (30 threshold)
    - `0xA2` (GCONF2): `8'h40` (GGAIN=4x, GLDRIVE=100mA)
    - `0xA9` (GPULSE): `8'hC9` (32us, 10 pulses)
    - `0xAA` (GCONF3): `8'h00` (All 4 photodiodes active)
    - `0xAB` (GCONF4): `8'h01` (Gesture mode active)
    - `0x80` (ENABLE): `8'h45` (PON | PEN | GEN)
  - `ST_READ_STATUS`: Polls `0xAF` (GSTATUS). If `GVALID` (bit 0) is set, transitions to FIFO read.
  - `ST_READ_FIFO`: Reads 4 sequential bytes (`GFIFO_U`, `GFIFO_D`, `GFIFO_L`, `GFIFO_R`) from `0xFC`..`0xFF`.
  - `ST_SAMPLE_LATCH`: Emits 1-cycle strobe `sample_valid` with 8-bit photodiode values.

### 2.2 `gesture_decoder.v`
- **Trajectory Phase Accumulator:**
  - Compares signed differentials:
    $$\text{cur\_diff\_ud} = U - D, \quad \text{cur\_diff\_lr} = L - R$$
  - Latches entry phase $\Delta_{\text{phase1}}$ when sum exceeds 50 counts.
  - Latches exit phase $\Delta_{\text{phase2}}$ as hand recedes.
  - Directional decision logic executes upon signal exit.
- **Refractory Lockout Filter:**
  - After any gesture output pulse, holds FSM in `ST_REFRACTORY` for $250\text{ ms}$ ($1\text{ ms}$ in simulation) to prevent duplicate triggers from trailing hand edges.
- **Synthetic Input Multiplexer:**
  - When `synth_mode == 1`, directly converts pushbuttons and switches to 1-cycle gesture pulses with zero simulation latency.

### 2.3 `menu_fsm.v`
- **Two-Tier Navigation Architecture:**
  - `current_menu[1:0]`: Tracks active main category (0: STATUS, 1: SETTINGS, 2: SENSORS, 3: ABOUT).
  - `in_submenu`: Boolean tracking top-level vs deep page navigation.
  - `submenu_page[1:0]`: Selects active screen within submenu.
- **Setting Registers:**
  - `setting_backlight[1:0]`: Controls LCD brightness (LOW, MED, HIGH).
  - `setting_beep_en`: Controls audible acoustic feedback toggle.
  - `setting_timeout_sel[1:0]`: Configures inactivity timer (10s, 20s, 30s).
- **LCD Character Generator:**
  - Dynamically synthesizes two 16-character ASCII strings (`lcd_line1`, `lcd_line2`) using combinational ASCII character matrices.

### 2.4 `vga_menu_display.v`
- **25 MHz VGA Generation:**
  - Integrates `vga_timing_controller.v` for industry-standard 640x480 @ 60 Hz video timing.
- **Graphical GUI Layout:**
  - Top header banner ($Y \le 50$) with title bar.
  - Left navigation sidebar ($X \in [40, 210]$) with 4 menu cards. Active card rendered with cyan neon border `24'h00F0FF` and highlight fill `24'h006494`.
  - Right details window ($X \in [240, 600]$) rendering dynamic 4-column photodiode bar graphs (green, cyan, gold, orange) or interactive settings sliders.
  - Bottom status footer ($Y \in [420, 470]$) showing active gesture color badge and gesture counter.
