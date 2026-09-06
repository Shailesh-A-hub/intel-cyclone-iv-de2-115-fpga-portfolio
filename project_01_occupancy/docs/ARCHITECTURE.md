# System Architecture: Multi-Zone Occupancy & Energy Decision Engine
## Project 1 - DE2-115 FPGA Portfolio

---

## 1. Top-Level System Architecture

The system coordinates four independent physical building zones through a hierarchical, pipelined architecture implemented entirely in synthesizable Verilog:

```
+-----------------------------------------------------------------------------------------------+
|                                      DE2-115 FPGA TOP LEVEL                                    |
|                                                                                               |
|  CLOCK_50 ---> [ timer_ms ] ---> tick_1ms                                                      |
|           ---> [ timer_sec ] --> tick_1s                                                      |
|                                                                                               |
|  KEY[0] -----> [ reset_synchronizer ] ---> rst (Synchronous)                                  |
|                                                                                               |
|  SW[3:0]    ---+                                                                              |
|  GPIO_PIR --+--> [ button_debounce x4 ] ---> debounced_motion[3:0]                            |
|                                                     |                                         |
|                       +-----------------------------+                                         |
|                       |                                                                       |
|                       v                                                                       |
|             +-------------------+                                                             |
|             |   zone_fsm (Z1)   | ---> zone_occupied[0], zone_light_req[0], zone_hvac_req[0]   |
|             +-------------------+                                                             |
|             |   zone_fsm (Z2)   | ---> zone_occupied[1], zone_light_req[1], zone_hvac_req[1]   |
|             +-------------------+                                                             |
|             |   zone_fsm (Z3)   | ---> zone_occupied[2], zone_light_req[2], zone_hvac_req[2]   |
|             +-------------------+                                                             |
|             |   zone_fsm (Z4)   | ---> zone_occupied[3], zone_light_req[3], zone_hvac_req[3]   |
|             +-------------------+                                                             |
|                       |                                                                       |
|                       +-----------------------------+                                         |
|                                                     v                                         |
|                                      +-------------------------------+                        |
|  SW[4] (Ambient Dark) -------------> |     energy_decision_engine    |                        |
|  tick_1s --------------------------> |                               |                        |
|                                      +-------------------------------+                        |
|                                            |   |   |   |   |                                  |
|                      +---------------------+   |   |   |   +------------------+               |
|                      |                         |   |   +----------+           |               |
|                      v                         v   v              v           v               |
|              [ zone_lights[3:0] ]             HVAC Fan        Fan PWM    Energy Saved         |
|                      |                        Relay Relay    Generator    Accumulator         |
|                      v                          |    |            |           |               |
|               [ LEDG[4], JP5 ]                  v    v            v           v               |
|                                              LEDG[5] LEDG[6]  LEDG[6]/JP5  [ HEX3..0 ]        |
|                                                                                               |
|  zone_occupied + hvac_level + energy_wh ------> [ occupancy_uart_logger ] ---> UART_TXD       |
|  zone_occupied + hvac_level + energy_wh ------> [ lcd_hd44780_controller ] --> 16x2 LCD       |
|                                                                                               |
+-----------------------------------------------------------------------------------------------+
```

---

## 2. Zone Controller FSM

Each zone is governed by a 4-state Mealy/Moore hybrid FSM:

```
            +---------------+
            |    S_FAULT    | <------+ (motion_in active > fault_timeout)
            +---------------+        |
               ^         |           |
 (fault detected)        | (!fault)  |
               |         v           |
            +---------------+        |
 +--------> |   S_VACANT    | -------+
 |          +---------------+
 |            |          ^
 | (timeout   | motion   | timeout
 |  expired)  v          | expired
 |          +---------------+
 |          |  S_OCCUPIED   | <------+
 |          +---------------+        |
 |            |          ^           |
 | (!motion)  |          | motion    | motion
 |            v          | retrigger | retrigger
 |          +---------------+        |
 +--------- |   S_TIMEOUT   | -------+
            +---------------+
```

### State Descriptions:
1. **`S_VACANT` (00)**: Zone is idle. No motion detected. Zone lighting and climate demands are de-asserted.
2. **`S_OCCUPIED` (01)**: Active motion detected. Zone requests lighting and climate. Timeout timer is held reloaded.
3. **`S_TIMEOUT` (10)**: Motion has ceased. Zone remains logically occupied while countdown timer decrements on each 1-second pulse. Any new motion pulse immediately returns state to `S_OCCUPIED`.
4. **`S_FAULT` (11)**: Sensor has been continuously high for longer than `fault_timeout` (stuck-at fault). System isolates zone demand and asserts warning LED.

---

## 3. Mathematical Formulation of Energy Calculation

### Baseline Unmanaged Building Model:
In an unmanaged facility, all loads run continuously 24 hours a day:
$$P_{\text{baseline}} = 4 \times P_{\text{light}} + P_{\text{HVAC,full}} + P_{\text{fan,full}} = 4 \times 100\,\text{W} + 1600\,\text{W} + 200\,\text{W} = 2200\,\text{W}$$

### Active Power Consumption:
Depending on total occupied zones $N_{\text{active}} \in \{0, 1, 2, 3, 4\}$ and ambient illumination:
$$P_{\text{active}}(N_{\text{active}}) = N_{\text{active}} \cdot P_{\text{light}} \cdot \text{ambient\_dark} + P_{\text{HVAC}}(N_{\text{active}}) + P_{\text{fan}}(N_{\text{active}})$$

| Active Zones ($N_{\text{active}}$) | HVAC Stage | HVAC Power | Fan Duty | Fan Power | Active Power | Instantaneous Power Saved ($\Delta P$) |
|---|---|---|---|---|---|---|
| **0 (All Vacant)** | OFF | 0 W | 0% | 0 W | **0 W** | **2200 W** |
| **1 Zone** | LOW | 600 W | 40% | 100 W | **800 W** | **1400 W** |
| **2 Zones** | MED | 1100 W | 70% | 140 W | **1440 W** | **760 W** |
| **3 Zones** | MED | 1100 W | 70% | 140 W | **1540 W** | **660 W** |
| **4 Zones (Full)** | HIGH | 1600 W | 100% | 200 W | **2200 W** | **0 W** |

### Discrete Integration into Watt-hours:
Accumulation occurs every second ($T_{\text{sample}} = 1\,\text{s}$):
$$E_{\text{ws}}(k) = E_{\text{ws}}(k-1) + \Delta P(k)$$
When $E_{\text{ws}} \ge 3600\,\text{W}\cdot\text{s}$, the accumulator increments the output register and retains the residual:
$$E_{\text{wh}} \leftarrow E_{\text{wh}} + 1, \quad E_{\text{ws}} \leftarrow E_{\text{ws}} - 3600$$

---

## 4. Telemetry Format

The UART engine formats fixed-width ASCII telemetry frames every second and upon state transitions:
```
[P1] Z:1000 H:1 E:0014Wh\r\n
```
- `[P1]`: Project 1 packet header.
- `Z:1000`: Binary occupancy flags for Zones 4, 3, 2, 1.
- `H:1`: Active HVAC stage (0=OFF, 1=LOW, 2=MED, 3=HIGH).
- `E:0014Wh`: 4-digit hexadecimal energy savings accumulator in Watt-hours.
- `\r\n`: Standard CRLF line terminator.
