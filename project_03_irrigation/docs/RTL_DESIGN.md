# Project 3: Smart Adaptive Irrigation System — RTL Design Document

## 1. Module Hierarchy & Port Map

```
irrigation_top
│
├── reset_synchronizer (common/rtl/reset_synchronizer.v)
├── button_debounce [KEY0, KEY1, KEY2] (common/rtl/button_debounce.v)
├── edge_detector [KEY1, KEY2] (common/rtl/edge_detector.v)
│
├── dht11_controller (project_03_irrigation/rtl/dht11_controller.v)
│   └── 1-Wire Bidirectional Tristate Buffer
│
├── soil_moisture_adc_reader (project_03_irrigation/rtl/soil_moisture_adc_reader.v)
│   └── spi_master (common/rtl/spi_master.v)
│
├── adaptive_threshold_engine (project_03_irrigation/rtl/adaptive_threshold_engine.v)
│
├── pump_controller_fsm (project_03_irrigation/rtl/pump_controller_fsm.v)
│
├── seven_seg_dec [x4 pairs: HEX7-6, HEX5-4, HEX3-2, HEX1-0] (common/rtl/seven_seg_dec.v)
├── lcd_hd44780_controller (common/rtl/lcd_hd44780_controller.v)
├── irrigation_uart_logger (project_03_irrigation/rtl/irrigation_uart_logger.v)
│   └── uart_tx (common/rtl/uart_tx.v)
└── periodic_timer [1 sec tick & 100ms tick] (common/rtl/periodic_timer.v)
```

---

## 2. Detailed RTL Descriptions

### 2.1 `dht11_controller.v`
- **Generics / Parameters:**
  - `CLK_FREQ_HZ`: Default `50_000_000` (50 MHz).
  - `SAMPLE_INTERVAL_MS`: Refresh period between read attempts ($2000\text{ ms}$ default, $2\text{ ms}$ in simulation).
  - `SIMULATION`: Overrides microsecond prescaler for accelerated verification.
- **Port Interface:**
  - `clk`, `reset_n`: System clock and active-low synchronous reset.
  - `dht_data`: `inout` physical bidirectional pin. Driven via internal tristate logic:
    ```verilog
    assign dht_data = (drive_low) ? 1'b0 : 1'bz;
    ```
  - `temperature[7:0]`: Measured temperature in $^\circ\text{C}$ ($0–50^\circ\text{C}$).
  - `humidity[7:0]`: Measured relative humidity in $\%$ ($20–90\%$).
  - `data_valid`: Single-cycle pulse asserted when 40-bit frame matches checksum.
  - `checksum_error`: Asserted high upon frame checksum mismatch.
  - `timeout_error`: Asserted high if line fails to respond within $5\text{ ms}$.

### 2.2 `soil_moisture_adc_reader.v`
- **Functionality:**
  - Instantiates `spi_master` configured for Mode 0, $50\text{ kHz}$ SPI clock.
  - Sends 3-byte command packet: `{8'h01, 8'h80, 8'h00}` to MCP3008 Channel 0.
  - Extracts 10-bit raw ADC: `{rx_byte1[1:0], rx_byte2[7:0]}`.
  - Computes volumetric percentage:
    $$M = \frac{(1023 - ADC) \times 100}{823}$$
    Clamped between $0\%$ and $100\%$.

### 2.3 `adaptive_threshold_engine.v`
- **Arithmetic Implementation:**
  - Operates using unsigned fixed-point and integer math with full pipelined saturation.
  - Temperature adder:
    $$\Delta T = (T_{\text{temp}} > 25) \ ? \ ((T_{\text{temp}} - 25) \gg 1) : 0$$
  - Humidity subtractor:
    $$\Delta H = (T_{\text{humid}} > 60) \ ? \ ((T_{\text{humid}} - 60) / 5) : 0$$
  - Result:
    $$T_{\text{calc}} = T_{\text{base}} + \Delta T - \Delta H$$
  - Bound clamping:
    $$T_{\text{adaptive}} = \begin{cases} 
    20 & \text{if } T_{\text{calc}} < 20 \\
    75 & \text{if } T_{\text{calc}} > 75 \\
    T_{\text{calc}} & \text{otherwise}
    \end{cases}$$

### 2.4 `pump_controller_fsm.v`
- **State Machine Encoding (One-Hot / Gray / Binary):**
  - `ST_OFF_READY` (`3'd0`): Standby state; monitors moisture vs $(T_{\text{adaptive}} - \text{HYST})$.
  - `ST_PUMP_ON` (`3'd1`): Relay actively energised (`relay_out = 1`). Min-run timer running.
  - `ST_MIN_OFF_WAIT` (`3'd2`): Pump shut down; cooling/settling interlock timer running.
  - `ST_RAIN_LOCKOUT` (`3'd3`): Rain detected; pump locked out.
  - `ST_SENSOR_FAULT` (`3'd4`): Sensor disconnected or invalid; safety shutdown.
  - `ST_MANUAL_OVERRIDE` (`3'd5`): User manual override active.
- **Watering Event Accumulator:**
  - Increments 16-bit counter `total_watering_seconds` on each 1-second pulse while in `ST_PUMP_ON`.
  - Increments 8-bit counter `watering_cycle_count` on each transition into `ST_PUMP_ON`.

---

## 3. Timing and Resource Strategy
- **Single Clock Domain:** All sequential registers clocked by `clk` (50 MHz).
- **Asynchronous Sensor Signals:** `miso`, `rain_in`, and `dht_data` synchronized through 2-stage flip-flop synchronizers to prevent metastability.
- **Tristate Buffer Control:** `dht_data` utilizes standard open-drain emulation with an external $4.7\text{ k}\Omega$ pull-up resistor.
