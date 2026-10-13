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
| **Relay Driver** | `GPIO_0` | Pin 1 | `PIN_AB22` | Output (3.3V) | Active-high pump relay driver |
| **MCP3008 ADC** | `GPIO_1` | Pin 2 | `PIN_AC15` | Output (3.3V) | SPI Chip Select (Active-low) |
| **MCP3008 ADC** | `GPIO_3` | Pin 4 | `PIN_Y17`  | Output (3.3V) | SPI Clock ($1\text{ MHz}$) |
| **MCP3008 ADC** | `GPIO_5` | Pin 6 | `PIN_Y16`  | Output (3.3V) | SPI MOSI (Data In) |
| **Soil Sensor (LM393)**| `GPIO_7` | Pin 8 | `PIN_AE16` | Input (3.3V) | **LM393 DO pin** (or MCP3008 MISO) |
| **DHT11 Sensor** | `GPIO_9` | Pin 10 | `PIN_AF16` | Inout (3.3V) | 1-Wire Data with $4.7\text{ k}\Omega$ pull-up to $3.3\text{ V}$ |
| **Rain Sensor** | `GPIO_11` | Pin 13 | `PIN_AE15` | Input (3.3V) | Digital active-high (rain detected) |
| **Power Supply** | `+3.3V` | Pin 29 | N/A | Power | 3.3V DC Sensor Supply |
| **Ground** | `GND` | Pin 12 / 30 | N/A | Ground | Common System Ground |

---

## 3. Sensor Wiring Details

### 3.1 Soil Moisture Probe & LM393 Module (Direct 3-Wire Connection — No ADC IC Required)
This project directly supports the standard **YL-69 probe + LM393 comparator breakout module**:
1. Connect the 2 pins of the fork probe to the 2-pin header on the blue LM393 module using the 2-pin jumper cable.
2. Wire the 4-pin interface of the blue module directly to DE2-115 Header `JP5`:
   - **`VCC`** $\rightarrow$ **JP5 Pin 29** (+3.3V Power)
   - **`GND`** $\rightarrow$ **JP5 Pin 12 or 30** (System Ground)
   - **`DO`**  $\rightarrow$ **JP5 Pin 8 (`PIN_AE16`, GPIO_7)** (Direct digital moisture threshold signal)
   - **`AO`**  $\rightarrow$ *Leave unconnected* (or connect to MCP3008 Pin 1 CH0 if using external ADC mode)

#### Calibration & Operation:
- **Default State (Dry Soil / Air):** The onboard green indicator LED on the sensor module turns OFF, the `DO` line is driven HIGH (1), the FPGA reads $20\%$ moisture, and the pump relay activates (`LEDG[0]` turns ON).
- **Watered State (Moist Soil / Water):** The green indicator LED on the sensor module turns ON, the `DO` line drops LOW (0), the FPGA reads $85\%$ moisture, and the pump turns OFF.
- **Potentiometer Adjustment:** Use a small flat-head screwdriver on the blue trimmer potentiometer to calibrate the exact sensitivity between moist and dry soil.
- **Mode Toggle:** `LEDR[12]` is illuminated when Direct LM393 DO mode is active. (Optional toggle via `SW[12]`).

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
