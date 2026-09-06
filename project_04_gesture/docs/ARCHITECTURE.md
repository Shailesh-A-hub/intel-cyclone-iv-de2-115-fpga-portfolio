# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Architecture

## 1. System Architecture Overview

The Gesture-Controlled Menu Interface architecture bridges high-speed optical spatial sensor telemetry with an interactive human-machine menu environment. The design is structured into five pipelined layers:
1. **Physical Sensor Interface:** Hardware I2C Master and APDS-9960 register configuration state machine.
2. **Gesture Classification Layer:** Phase-vector trajectory tracking engine with spatial differential peak detectors.
3. **Hierarchical Menu Supervisory FSM:** Multi-tier state machine managing page navigation, parameter adjustment, and inactivity timers.
4. **Display Presentation Layer:** Character LCD formatting pipeline and 60 Hz graphical VGA rasterizer.
5. **Telemetry & Diagnostic Layer:** Asynchronous 115200-baud UART event serializer and 7-segment display decoders.

```
+-----------------------------------------------------------------------------------+
| DE2-115 TOP-LEVEL (gesture_top.v)                                                 |
|                                                                                   |
|  +--------------------+     +---------------------+     +-----------------------+ |
|  | reset_synchronizer |     |  button_debounce    |     |  periodic_timer       | |
|  | (clk, reset_n)     |     |  (KEY0, KEY1, KEY2) |     |  (1-sec & 100ms ticks)| |
|  +--------------------+     +---------------------+     +-----------------------+ |
|                                                                                   |
|  +--------------------------+  +----------------------+  +---------------------+  |
|  | apds9960_i2c_driver      |  | gesture_decoder      |  | menu_fsm            |  |
|  | - i2c_master             |  | - Spatial Trajectory |  | - Main: 4 Categories|  |
|  | - Auto-Init Sequence     |  | - Delta UD & Delta LR|  | - Submenus & Toggles|  |
|  | - FIFO Polling & Readout |  | - UP, DN, LF, RT, NR |  | - Auto-Exit Timeout |  |
|  +------------+-------------+  +----------+-----------+  +----------+----------+  |
|               | (U, D, L, R samples)      | (Gesture Pulse)         |             |
|               +---------------------------+                         |             |
|                                                                     |             |
|        +---------------------------+--------------------------------+             |
|        |                           |                           |                  |
|        v                           v                           v                  |
|  +------------------+       +-------------------+       +---------------+         |
|  | vga_menu_display |       | lcd_hd44780       |       | gesture_uart  |         |
|  | (640x480 @ 60Hz) |       | (16x2 Text LCD)   |       | (115200 baud) |         |
|  +------------------+       +-------------------+       +---------------+         |
+-----------------------------------------------------------------------------------+
```

---

## 2. Spatial Gesture Recognition Theory

### 2.1 Optical Differential Trajectory Formulation
The APDS-9960 sensor features four directional infrared photodiodes positioned symmetrically around an internal LED emitter:
- **Up ($U$)**, **Down ($D$)**, **Left ($L$)**, and **Right ($R$)**.

When a hand moves across the field of view, the target reflects infrared light onto the photodiodes in temporal succession:
$$\Delta_{\text{UD}}(t) = U(t) - D(t)$$
$$\Delta_{\text{LR}}(t) = L(t) - R(t)$$
$$\Sigma_{\text{total}}(t) = U(t) + D(t) + L(t) + R(t)$$

A gesture begins when total proximity energy crosses the entry threshold:
$$\Sigma_{\text{total}}(t) \ge \text{ENTER\_THRESHOLD} \quad (50\text{ counts})$$

### 2.2 Directional Classification Rules
During motion, the decoder captures the trajectory phase vector $(\Delta_{\text{phase1}}, \Delta_{\text{phase2}})$:
- **UP Gesture:** Object approaches from the bottom, illuminating $D$ first ($\Delta_{\text{UD}} < -\text{DIFF\_DELTA}$), then moves upward across $U$ ($\Delta_{\text{UD}} > +\text{DIFF\_DELTA}$).
- **DOWN Gesture:** Object approaches from the top, illuminating $U$ first ($\Delta_{\text{UD}} > +\text{DIFF\_DELTA}$), then moves downward across $D$ ($\Delta_{\text{UD}} < -\text{DIFF\_DELTA}$).
- **LEFT Gesture:** Object approaches from the right, illuminating $R$ first ($\Delta_{\text{LR}} < -\text{DIFF\_DELTA}$), then moves left across $L$ ($\Delta_{\text{LR}} > +\text{DIFF\_DELTA}$).
- **RIGHT Gesture:** Object approaches from the left, illuminating $L$ first ($\Delta_{\text{LR}} > +\text{DIFF\_DELTA}$), then moves right across $R$ ($\Delta_{\text{LR}} < -\text{DIFF\_DELTA}$).
- **NEAR Gesture (Push / Tap):** Proximity spikes rapidly across all four photodiodes simultaneously with balanced energy:
  $$\Sigma_{\text{total}} \ge 180 \quad \text{AND} \quad |\Delta_{\text{UD}}| < \text{DIFF\_DELTA} \quad \text{AND} \quad |\Delta_{\text{LR}}| < \text{DIFF\_DELTA}$$
- **FAR Gesture (Pull / Recede):** Total energy gently decreases without strong directional asymmetry.

---

## 3. Menu Navigation FSM Design

```
                     +---------------------------------------+
                     |               MAIN MENU               |
                     |  0: STATUS   1: SETTINGS              |
                     |  2: SENSORS  3: ABOUT                 |
                     +-------------------+-------------------+
                               |                   ^
                   RIGHT / NEAR|                   | LEFT / FAR
                     (Enter)   |                   | (Exit / Timeout)
                               v                   |
                     +-------------------+-------------------+
                     |                SUBMENU                |
                     | - Page UP / DOWN                      |
                     | - Parameter Toggle (RIGHT / NEAR)     |
                     +---------------------------------------+
```

### 3.1 Navigation Semantics
- **Main Menu Level:**
  - `UP`: Decrement Menu Index (with wrap-around: $0 \rightarrow 3 \rightarrow 2 \rightarrow 1 \rightarrow 0$)
  - `DOWN`: Increment Menu Index (with wrap-around: $0 \rightarrow 1 \rightarrow 2 \rightarrow 3 \rightarrow 0$)
  - `RIGHT` or `NEAR`: Enter Submenu for current item.
  - `LEFT`: Ignored at top level.
- **Submenu Level:**
  - `UP` / `DOWN`: Scroll through sub-pages.
  - `RIGHT` or `NEAR`: Cycle / toggle selected configuration parameter.
  - `LEFT` or `FAR`: Exit back to Main Menu.
  - `Inactivity Timeout`: If no gesture occurs for $T_{\text{timeout}}$ ($10\text{ s}$, $20\text{ s}$, or $30\text{ s}$), automatically exit to Main Menu.
