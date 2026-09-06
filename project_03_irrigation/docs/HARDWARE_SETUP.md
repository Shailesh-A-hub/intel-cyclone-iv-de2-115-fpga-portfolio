# Project 3: Smart Adaptive Irrigation System — Hardware Setup Guide

## 1. Safety Warnings & Electrical Isolation

> [!CAUTION]
> **HIGH VOLTAGE / INDUCTIVE LOAD WARNING:**  
> Never connect an AC water pump or DC motor directly to FPGA GPIO pins. The Cyclone IV I/O buffers are rated for $3.3\text{ V}$ with a maximum current of $8\text{ mA}$. Directly driving an inductive pump motor or raw relay coil will destroy the FPGA through back-EMF flyback spikes. Always use an optically isolated relay module or MOSFET driver board with an active freewheeling diode.

> [!TIP]
> **INITIAL BENCH TESTING:**  
> For bench testing and verification, observe onboard green LED `LEDG[0]` (which tracks the pump relay output) and status LEDs `LEDR[17:0]` before connecting any high-power pump or external solenoid.

---

## 2. External Hardware Wiring

The DE2-115 provides two 40-pin expansion headers (`JP5` = GPIO, `JP1` = GPIO). Connections use header `JP5`:

| Peripheral Device | Signal Name | DE2-115 JP5 Pin | FPGA Pin | Signal Type | Notes |
|---|---|---|---|---|---|
| **MCP3008 ADC** | `ADC_CS_N` | Pin 1 | `PIN_AB22` | Output (3.3V) | Active-low chip select |
| **MCP3008 ADC** | `ADC_SCLK` | Pin 2 | `PIN_AC15` | Output (3.3V) | SPI Clock ($50\text{ kHz}$) |
| **MCP3008 ADC** | `ADC_MOSI` | Pin 3 | `PIN_AB21` | Output (3.3V) | Master Out Slave In |
| **MCP3008 ADC** | `ADC_MISO` | Pin 4 | `PIN_Y17` | Input (3.3V) | Master In Slave Out |
| **DHT11 Sensor** | `DHT_DATA` | Pin 5 | `PIN_AC21` | Inout (3.3V) | Bidirectional with $4.7\text{ k}\Omega$ pull-up to $3.3\text{ V}$ |
| **Rain Sensor** | `RAIN_PIN` | Pin 6 | `PIN_Y16` | Input (3.3V) | Digital active-high (rain detected) |
| **Relay Driver** | `RELAY_CTRL`| Pin 7 | `PIN_AD21` | Output (3.3V) | Optocoupler input anode via $220\Omega$ resistor |
| **Power Supply** | `+3.3V` | Pin 29 | N/A | Power | 3.3V sensor supply |
| **Ground** | `GND` | Pin 12 / 30 | N/A | Ground | Common system ground |

---

## 3. Sensor Wiring Details

### 3.1 Soil Moisture Probe & MCP3008
- Connect moisture probe analog output to MCP3008 `CH0` (Pin 1 of IC).
- Connect MCP3008 `VDD` and `VREF` to $3.3\text{ V}$ (Pin 29 of `JP5`).
- Connect MCP3008 `AGND` and `DGND` to Ground (Pin 12 of `JP5`).

### 3.2 DHT11 Sensor
- Pin 1 (VCC) $\rightarrow 3.3\text{ V}$
- Pin 2 (DATA) $\rightarrow$ JP5 Pin 5 (`PIN_AC21`) with a $4.7\text{ k}\Omega$ resistor between DATA and VCC.
- Pin 3 (NC) $\rightarrow$ Not connected.
- Pin 4 (GND) $\rightarrow$ Ground.

### 3.3 Optically Isolated Relay Module
- Connect `VCC` of relay module to external $5\text{ V}$ supply.
- Connect `IN1` of relay module to JP5 Pin 7 (`PIN_AD21`).
- Connect `GND` of relay module to common ground.
- The relay contact switches the 12V DC water pump or AC valve solenoid.

---

## 4. Operational Controls on DE2-115

| Control | Description | Function |
|---|---|---|
| `KEY[0]` | Pushbutton 0 | Active-low asynchronous master system reset |
| `KEY[1]` | Pushbutton 1 | Force manual trigger / reset error condition |
| `KEY[2]` | Pushbutton 2 | Cycle base moisture threshold ($25\% \rightarrow 35\% \rightarrow 45\% \rightarrow 55\%$) |
| `SW[17]` | Slide Switch 17 | `0`: Physical sensor inputs (ADC/DHT11); `1`: Synthetic simulation override mode |
| `SW[16]` | Slide Switch 16 | Manual pump override switch (`1`: Force ON) |
| `SW[15]` | Slide Switch 15 | Rain sensor manual override / test input |
| `SW[12:8]` | Slide Switch 12-8 | Synthetic soil moisture value ($0–31$, scaled $0–100\%$) |
| `SW[7:4]` | Slide Switch 7-4 | Synthetic temperature offset ($+0^\circ\text{C}$ to $+15^\circ\text{C}$ over $20^\circ\text{C}$) |
| `SW[3:0]` | Slide Switch 3-0 | Synthetic humidity offset ($0–90\%$) |
| `HEX7-6` | 7-Segment Displays | Current soil moisture percentage ($00–99\%$) |
| `HEX5-4` | 7-Segment Displays | Current adaptive trigger threshold ($00–99\%$) |
| `HEX3-2` | 7-Segment Displays | Ambient temperature ($^\circ\text{C}$) |
| `HEX1-0` | 7-Segment Displays | Ambient relative humidity ($\%$) |
| `LEDG[0]` | Green LED 0 | Pump active relay indicator (`ON` = watering active) |
| `LEDR[17]` | Red LED 17 | Rain lockout indicator |
| `LEDR[16]` | Red LED 16 | Sensor fault indicator |
