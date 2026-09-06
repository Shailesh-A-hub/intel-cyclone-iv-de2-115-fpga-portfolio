# Known Limitations & Hardware Considerations
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### 1. Gas Sensor Warm-up Drift (MQ Series)
- **Observation:** Metal oxide semiconductor (MOS) gas sensors (such as MQ-2, MQ-5, MQ-7) require a continuous internal heater ($5\text{V}$, $\approx 150\text{ mA}$) and exhibit a stabilization burn-in period of 24–48 hours for laboratory-grade accuracy, and 1–3 minutes upon power-up.
- **Hardware Impact:** During the initial 60 seconds of cold boot, raw ADC readings from cold sensors may read abnormally high or unstable before settling.
- **Mitigation:** The normalizer module baseline can be adjusted dynamically or a 60-second power-on blanking timer can be added before arming high-severity alerts.

### 2. External Analog Voltage Reference ($V_{ref}$)
- **Observation:** The DE2-115 development board GPIO headers provide $3.3\text{V}$ and $5.0\text{V}$ DC rails. Because the Cyclone IV I/O bank operating standard is $3.3\text{V}$ LVTTL, the MCP3008 ADC $V_{DD}$ and $V_{REF}$ must be supplied with $3.3\text{V}$ to prevent overvoltage damage to FPGA MISO input pin `GPIO_7`.
- **Mitigation:** If $5\text{V}$ sensors are utilized (e.g. standard MQ-2 module), a passive resistive voltage divider ($10\text{ k}\Omega / 20\text{ k}\Omega$) or level shifter must be placed between the sensor analog output and the MCP3008 input channels.

### 3. SPI Bus Multi-Drop Topology
- **Observation:** Currently, the `mcp3008_adc_controller` dedicated chip-select `GPIO_1` manages a single 8-channel ADC.
- **Future Expansion:** Additional SPI sensors (e.g. external EEPROM or thermocouple amplifiers like MAX31855) can be multiplexed by extending the chip-select decoder in RTL.

### 4. Acoustic Buzzer Driver Isolation
- **Observation:** Piezo buzzers and electromagnetic sounders draw inductive in-rush currents ($20\text{–}100\text{ mA}$) that exceed the absolute maximum DC output current ($25\text{ mA}$) of a single Cyclone IV I/O pin.
- **Rule:** Direct connection to `GPIO_0` without a driver circuit is strictly forbidden. A 2N2222 or 2N7000 transistor buffer circuit must be used.
