# Hardware Setup & Execution Guide
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### 1. Hardware Requirements
1. **Target Board:** Terasic DE2-115 Development Board (Altera / Intel Cyclone IV EP4CE115F29C7).
2. **Power Supply:** 12V DC, 2A center-positive power adapter.
3. **Programming Interface:** Built-in USB-Blaster (Type-B USB cable to PC).
4. **External Sensor Module (Optional for Physical Mode):**
   - Microchip MCP3008 (8-channel 10-bit SPI ADC in DIP-16 or breakout).
   - MQ-2 / MQ-5 / MQ-7 Combustible Gas & Smoke Sensor.
   - Optical IR Flame Sensor (Phototransistor or Comparator module).
   - LM35 / TMP36 Analog Temperature Sensor.
   - Analog Soil / Air Humidity Sensor.
   - 5V Piezoelectric Buzzer (driven via 2N2222 or MOSFET buffer on GPIO).
5. **No External Hardware Required for Synthetic Mode:**
   - The FPGA design includes a fully functional **Synthetic Simulation Mode (`SW[17] = 1`)** allowing complete hardware execution using onboard slide switches, pushbuttons, LEDs, LCD, and 7-segment displays!

### 2. External Hardware Wiring (JP5 Header)

```
DE2-115 JP5 Header                   External Module / MCP3008 ADC
------------------                   -----------------------------
Pin 1  (GPIO[0]  - PIN_AB22) ------> Piezo Buzzer Signal (via Transistor Buffer)
Pin 2  (GPIO[1]  - PIN_AC15) ------> MCP3008 Pin 10 (CS / SHDN)
Pin 4  (GPIO[3]  - PIN_Y17)  ------> MCP3008 Pin 13 (SCLK)
Pin 6  (GPIO[5]  - PIN_Y16)  ------> MCP3008 Pin 11 (DIN / MOSI)
Pin 8  (GPIO[7]  - PIN_AE16) <------ MCP3008 Pin 12 (DOUT / MISO)
Pin 11 (GND)                 ------> Common Ground
Pin 29 (VCC3P3)              ------> MCP3008 Pin 15, 16 (VDD, VREF)
```

> [!CAUTION]
> **ELECTRICAL ISOLATION:** Never connect a high-current piezo buzzer, siren coil, or heater element directly to FPGA GPIO pins. Always route the PWM signal through an NPN transistor (e.g. 2N2222) or N-channel MOSFET with flyback protection.

### 3. Quick-Start Hardware Execution

#### Step 1: Program the Bitstream
Open Intel Quartus Prime Programmer, select the USB-Blaster, and load `fire_gas_top.sof` into the EP4CE115 FPGA.

#### Step 2: Running in Synthetic Mode (Safe Bench Testing)
1. Turn ON `SW[17]` (Synthetic Mode enabled, `LEDG[8]` lights up).
2. Select sensor to stimulate using `SW[14:13]`:
   - `00`: Gas Sensor (adjust raw value using `SW[9:0]`)
   - `01`: Temperature Sensor (adjust raw value using `SW[9:0]`)
   - `10`: Flame Sensor (adjust raw value using `SW[9:0]`)
   - `11`: Humidity Sensor (adjust raw value using `SW[9:0]`)
3. Observe live readings:
   - `HEX1-0`: Risk score ($0..100$)
   - `HEX3-2`: Gas percentage ($0..99\%$)
   - `HEX5-4`: Temperature in °C
   - `HEX7-6`: Flame percentage ($0..99\%$)
   - `LCD`: 16x2 text displaying live status
   - `LEDG`: Green Safe indicator
   - `LEDR[17:15]`: Red flashing Danger alarm
4. Inject synthetic faults using `SW[16:15]`:
   - `01`: Inject gas sensor open-circuit fault.
   - `10`: Inject temperature sensor short-circuit fault.
   - `11`: Inject SPI communication fault.
5. Press `KEY[1]` to mute active alarm buzzer.
6. Press `KEY[2]` to toggle dynamic weight profiles (Balanced $\rightarrow$ Flame-Centric $\rightarrow$ Gas-Centric).
