# Project 3: Smart Adaptive Irrigation System — Architecture Specification

## 1. System Architecture Overview

The Smart Adaptive Irrigation System implements a real-time, closed-loop environmental feedback controller implemented on an Intel Cyclone IV EP4CE115 FPGA. The system addresses water resource conservation and agricultural crop health by replacing primitive static moisture threshold switches with an **adaptive threshold decision engine** that accounts for ambient atmospheric drying potential (temperature and vapor pressure deficit via relative humidity).

```
                     +---------------------------------------+
                     |            DE2-115 FPGA               |
                     |                                       |
+-----------------+  |  +---------------------------------+  |
| Analog Moisture |  |  |   soil_moisture_adc_reader      |  |
| Sensor (Soil)   |---> | - SPI Master (MCP3008 Ch 0)     |  |
+-----------------+  |  | - 10-bit raw to 0-100% moisture|  |
                     |  +----------------+----------------+  |
                     |                   |                   |
+-----------------+  |  +----------------v----------------+  |
| DHT11 Sensor    |<--->|   dht11_controller              |  |
| (1-Wire Bus)    |  |  | - 18ms Start Pulse / 40-bit RX  |  |
+-----------------+  |  | - CRC-8 & Bus Error Detection   |  |
                     |  +----------------+----------------+  |
                     |                   | (Temp & Humid)    |
+-----------------+  |  +----------------v----------------+  |
| Rain Sensor     |---> |   adaptive_threshold_engine     |  |
| (Digital Pin)   |  |  | - Q8.8 Fixed-Point Correction   |  |
+-----------------+  |  | - Dynamic Threshold Calculation |  |
                     |  +----------------+----------------+  |
                     |                   | (T_adaptive)      |
+-----------------+  |  +----------------v----------------+  |  +--------------------+
| Pushbuttons &   |---> |   pump_controller_fsm           |---> | Relay Output (GPIO)|
| Slide Switches  |  |  | - Hysteresis (+/- 3%)           |  |  +--------------------+
+-----------------+  |  | - Min Run / Min Rest Interlocks |  |
                     |  | - Manual Override / Rain Abort  |  |  +--------------------+
                     |  +----------------+----------------+  |  | 16x2 HD44780 LCD   |
                     |                   |                   |  +--------------------+
                     |  +----------------v----------------+  |  | 7-Seg Decimal Disp |
                     |  |   Telemetry & Display Drivers   |---> +--------------------+
                     |  | - UART (115200) Logger          |  |  | Status LEDs        |
                     |  +---------------------------------+  |  +--------------------+
                     +---------------------------------------+
```

---

## 2. Mathematical Decision Model

### 2.1 Soil Moisture Inversion & Normalization
Commercial capacitive and resistive soil moisture probes output an analog voltage inversely proportional to soil water content:
- **Dry Soil in Air:** High resistance, $V_{\text{out}} \approx V_{\text{DD}}$ ($ADC_{\text{raw}} \approx 1023$).
- **Saturated Soil in Water:** Low resistance, $V_{\text{out}} \approx 0.2\text{ V}$ ($ADC_{\text{raw}} \le 200$).

The module normalizes the 10-bit reading ($0–1023$) to volumetric moisture percentage ($0–100\%$):
$$M_{\text{soil}} = \text{clamp}\left( \frac{1023 - ADC_{\text{raw}}}{1023 - 200} \times 100,\; 0,\; 100 \right)$$
In synthesizable integer arithmetic:
$$M_{\text{soil}} = \begin{cases} 
0 & \text{if } ADC_{\text{raw}} \ge 1023 \\
100 & \text{if } ADC_{\text{raw}} \le 200 \\
\left\lfloor \frac{(1023 - ADC_{\text{raw}}) \times 100}{823} \right\rfloor & \text{otherwise}
\end{cases}$$

### 2.2 Adaptive Threshold Formulation
Evapotranspiration rate increases with ambient temperature and decreases with atmospheric humidity. If ambient air is dry and hot, water evaporates rapidly from topsoil; the system preemptively raises the watering trigger threshold to prevent water stress:
$$T_{\text{adaptive}} = T_{\text{base}} + \Delta T_{\text{temp}} - \Delta H_{\text{humid}}$$

Where:
- $T_{\text{base}}$: Baseline trigger threshold (programmable, default $= 35\%$).
- $\Delta T_{\text{temp}} = \begin{cases} 0.5 \times (T_{\text{ambient}} - 25^\circ\text{C}) & \text{if } T_{\text{ambient}} > 25^\circ\text{C} \\ 0 & \text{otherwise} \end{cases}$
- $\Delta H_{\text{humid}} = \begin{cases} 0.2 \times (H_{\text{ambient}} - 60\%) & \text{if } H_{\text{ambient}} > 60\% \\ 0 & \text{otherwise} \end{cases}$
- Dynamic Safety Bounds:
  $$20\% \le T_{\text{adaptive}} \le 75\%$$

### 2.3 Hysteresis Band
To avoid rapid bang-bang hunting around the threshold:
- **Turn ON Condition:**
  $$M_{\text{soil}} < (T_{\text{adaptive}} - \text{HYST}) \quad (\text{where } \text{HYST} = 3\%)$$
- **Turn OFF Condition:**
  $$M_{\text{soil}} \ge (T_{\text{adaptive}} + \text{HYST})$$

---

## 3. Subsystem Architecture

### 3.1 DHT11 Single-Wire Protocol Engine (`dht11_controller.v`)
The DHT11 uses a proprietary bidirectional asynchronous single-wire protocol:
1. **FPGA Host Drive:** Master pulls line low for at least $18\text{ ms}$ (`18,000 us`), then releases line high for $20–40\text{ us}$.
2. **Sensor Response:** Sensor pulls line low for $80\text{ us}$, then pulls high for $80\text{ us}$.
3. **Data Bits (40 bits):**
   - Each bit begins with a $50\text{ us}$ low pulse.
   - Bit 0: $26–28\text{ us}$ high pulse.
   - Bit 1: $70\text{ us}$ high pulse.
4. **Checksum Verification:**
   $$\text{Checksum} = (\text{Byte}_0 + \text{Byte}_1 + \text{Byte}_2 + \text{Byte}_3) \pmod{256}$$
   Where $\text{Byte}_0$ is Humidity Integral, $\text{Byte}_2$ is Temperature Integral, and $\text{Byte}_4$ is Checksum.

### 3.2 SPI ADC Interface (`soil_moisture_adc_reader.v`)
Queries external 8-channel 10-bit MCP3008 ADC over SPI Mode 0 (CPOL=0, CPHA=0):
- Initiates 3-byte SPI transfer: `0x01` (start bit), `0x80` (single-ended Channel 0), `0x00` (dummy byte).
- Samples data at $50\text{ kHz}$ SPI clock with a $100\text{ ms}$ refresh period.
- Reports `adc_fault` if readings stay at rail limits continuously (`0x000` or `0x3FF`).

### 3.3 Pump Controller FSM (`pump_controller_fsm.v`)
Ensures safe physical motor control via strict state flow:
- `ST_IDLE_READY`: Pump is idle. Awaits start condition.
- `ST_PUMP_ON`: Pump relay active. Hardware enforces $T_{\text{min\_on}} \ge 15\text{ s}$ before allowing shutdown.
- `ST_MIN_OFF_WAIT`: Once turned off, pump cannot restart until $T_{\text{min\_off}} \ge 30\text{ s}$ elapses.
- `ST_RAIN_LOCKOUT`: Rain sensor tripped; pump immediately disabled.
- `ST_SENSOR_FAULT`: Sensor fault active; system holds in safe state.
- `ST_MANUAL_OVERRIDE`: Manual switch active; pump forced ON regardless of moisture.
