# RTL Design & Module Implementation Details
## Project 1 - Multi-Zone Occupancy & Energy Decision Engine

---

## 1. Module Hierarchy

```
occupancy_top (occupancy_top.v)
├── reset_synchronizer (common/rtl/reset_synchronizer.v)
├── timer_ms (common/rtl/timer_ms.v)
├── timer_sec (common/rtl/timer_sec.v)
├── button_debounce [0..3] (common/rtl/button_debounce.v)
├── zone_fsm [0..3] (project_01_occupancy/rtl/zone_fsm.v)
├── energy_decision_engine (project_01_occupancy/rtl/energy_decision_engine.v)
├── pwm_generator (common/rtl/pwm_generator.v)
├── seven_seg_hex [0..3] (common/rtl/seven_seg_hex.v)
├── seven_seg_dec [4, 6] (common/rtl/seven_seg_dec.v)
├── lcd_hd44780_controller (common/rtl/lcd_hd44780_controller.v)
└── occupancy_uart_logger (project_01_occupancy/rtl/occupancy_uart_logger.v)
    └── uart_tx (common/rtl/uart_tx.v)
```

---

## 2. Register & Port Specifications

### `zone_fsm.v`
- **Parameters**:
  - `ZONE_ID`: Integer ID (1..4) for logging differentiation.
- **Internal Registers**:
  - `state`: 2-bit state register (`S_VACANT`, `S_OCCUPIED`, `S_TIMEOUT`, `S_FAULT`).
  - `countdown_val`: 16-bit countdown timer register.
  - `stuck_timer`: 16-bit timer counting continuous motion seconds.

### `energy_decision_engine.v`
- **Key Logic**:
  - Combinational adder summing `zone_occupied[3:0]`.
  - Staging decoder for HVAC (3-level multi-stage heat pump / compressor staging).
  - 24-bit discrete integrator `watt_sec_accumulator` for numerical integration without loss of fractional Watt-hours.

### `occupancy_uart_logger.v`
- **State Machine**:
  - 28-character frame sequencer streaming ASCII packet over 115200 baud UART TX.
  - Converts binary integers to human-readable ASCII hex nibbles in real time.

---

## 3. Clock Domain Strategy
The entire project operates on a single synchronous 50 MHz clock domain. All multi-rate operations (10ms debounce, 1ms LCD timing, 1s energy integration, 115200 baud UART transmission) are scheduled via single-clock-cycle enable strobes (`tick_1ms`, `tick_1s`, `baud_tick`), guaranteeing zero clock skew across Cyclone IV clock trees.
