# System Architecture Document
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### 1. High-Level Architecture Overview

The system architecture implements a modular, pipelined hardware sensor fusion pipeline:

```
+-----------------------------------------------------------------------------------+
|                                 DE2-115 FPGA                                      |
|                                                                                   |
|  +--------------------+         +-------------------+         +----------------+  |
|  | mcp3008_adc_ctrl   |         | sensor_normalizer |         | risk_engine_   |  |
|  |                    |         |                   |         | q8_8           |  |
|  | +----------------+ |  10-bit | Stage 1: Offsets  |  8-bit  | Stage 1: Mult  |  |
|  | |  spi_master    | |-------->| Stage 2: Scaling  |-------->| Stage 2: Scale |  |
|  | +----------------+ | Raw ADC | Engineering Units | Norm G, | Score (0-100)  |  |
|  +--------------------+         | Fault Detection   | T, F, H | Threshold FSM  |  |
|          ^                      +-------------------+         +----------------+  |
|          | SPI Bus                        |                           |           |
|          v                                v                           v           |
|     (MCP3008 ADC)                   Fault Vector                 Risk Level       |
|                                           |                           |           |
|  +----------------------------------------+---------------------------+--------+  |
|  | Peripheral Output Layer                                                     |  |
|  |  +--------------------+  +--------------------+  +-----------------------+  |  |
|  |  | alarm_buzzer_ctrl  |  | lcd_hd44780_ctrl   |  | fire_gas_uart_logger  |  |  |
|  |  | (PWM Tone Siren)   |  | (16x2 Display)     |  | (115200 Baud ASCII)   |  |  |
|  |  +--------------------+  +--------------------+  +-----------------------+  |  |
|  |  +--------------------+  +--------------------+                             |  |
|  |  | seven_seg_dec (x8) |  | LED Risk Bar       |                             |  |
|  |  +--------------------+  +--------------------+                             |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

### 2. Module Decomposition & Dataflow

1. **`mcp3008_adc_controller`**:
   - Master SPI sequencer operating at $1.0\text{ MHz}$ SCLK.
   - Issues 3-byte command bursts: `{0x01, {1'b1, 1'b0, ch[1:0], 4'b0}, 0x00}`.
   - Extracts 10-bit ADC output from `{rx_byte1[1:0], rx_byte2[7:0]}`.
   - Periodically scans Channels 0, 1, 2, 3 in round-robin sequence.
   - Monitors SPI transactions with a $10\text{ ms}$ communication watchdog timer to flag disconnection.
   - Supports seamless bypass into synthetic test mode via `SW[17]`.

2. **`sensor_normalizer`**:
   - 2-stage synchronous pipeline:
     - Stage 1: Computes difference from baseline ($raw - BASELINE$), handles polarity inversion for flame/humidity sensors, and checks open/short boundary conditions ($< 5$ or $\ge 1020$).
     - Stage 2: Multiplies by scale constant and clamps output to $0..255$. Converts metrics to human-readable engineering units (Temp in °C, Gas in %, Flame in %, Humidity in %).

3. **`risk_engine_q8_8`**:
   - Fixed-point sensor fusion core:
     - Stage 1: Four parallel 8-bit unsigned multipliers ($W_i \times N_i$) generating 16-bit products, summed into a 17-bit accumulator ($\le 65,280$).
     - Stage 2: Integer scaling to 0–100 integer range using:
       $$\text{Score}_{100} = \frac{\text{Accumulator} \times 100 + 32640}{65280}$$
     - Dominant hazard arbitration: identifies the single largest hazard contributor.
     - Threshold comparator: partitions operational state into `SAFE` ($0..34$), `CAUTION` ($35..69$), `DANGER` ($70..100$), and `FAULT` (sensor fault override).

4. **`alarm_buzzer_controller`**:
   - Dynamic tone modulator driving an external piezo transducer via `pwm_generator`.
   - Modulates PWM frequency and cadence:
     - Silent during `SAFE`.
     - $1.0\text{ kHz}$ chirp ($100\text{ ms}$ on, $900\text{ ms}$ off) during `CAUTION`.
     - Dual-tone siren ($2.0\text{ kHz} \leftrightarrow 2.5\text{ kHz}$ toggling every $250\text{ ms}$) during `DANGER`.
     - $500\text{ Hz}$ diagnostic pulse during `FAULT`.
   - Built-in mute button with automatic unmute when entering higher severity.

5. **`fire_gas_uart_logger`**:
   - Streaming ASCII packetizer outputting real-time system state at 115200 baud, 8N1 once per second:
     `[FIRE_GAS] G:xx% T:xxC F:xx% H:xx% | RISK:xxx [SAFE  ] FLT:00\r\n`

6. **Display Subsystem**:
   - 8x 7-Segment decimal displays (`seven_seg_dec`):
     - `HEX1-HEX0`: Risk score (00–99) or `--` on fault.
     - `HEX3-HEX2`: Gas concentration (00–99%).
     - `HEX5-HEX4`: Ambient temperature (00–99°C).
     - `HEX7-HEX6`: Optical flame intensity (00–99%).
   - 16x2 Character LCD (`lcd_hd44780_controller`):
     - Line 1: `G:xx% T:xxC F:xx%`
     - Line 2: `RISK:xxx [SAFE  ]` or `FAULT: ERR 0xXX`
