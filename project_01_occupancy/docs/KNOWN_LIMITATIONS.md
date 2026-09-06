# Known Limitations & Engineering Assumptions
## Project 1 - Multi-Zone Occupancy & Energy Decision Engine

---

## 1. Sensor & Interface Limitations
- **PIR Sensor Blanking Time**: Physical PIR sensors (e.g. HC-SR501) feature an internal analog retrigger lock-out window (~2.5s) after an output transition. Rapid motion events within this analog lock-out window are filtered at the sensor hardware level before reaching the FPGA GPIO pins.
- **Relay Switching Speeds**: Mechanical relays require 5–15 ms to close or open. To prevent contact arcing or rapid relay cycling ("chatter"), software and hardware thresholds must maintain minimum on/off intervals.

## 2. Model Assumptions
- **Static Building Baseline**: The energy savings calculation models an average commercial baseline load of 2200 W (4x100W lights + 1600W HVAC + 200W fan). In facilities with variable daylight harvesting or varying ambient temperatures, the baseline power shifts dynamically.
- **Sensor Coverage Overlap**: The algorithm treats the 4 zones as disjoint geometric regions. Overlapping PIR fields-of-view may cause simultaneous triggers across two adjacent zone controllers.

## 3. Future Enhancements
- **Ambient Light ADC Integration**: Incorporate external SPI ADC readings from an analog light sensor to implement smooth continuous PWM light dimming rather than binary on/off switching.
- **Modbus / BACnet Gateway**: Wrap UART telemetry frames into BACnet MS/TP or Modbus RTU packets for seamless plug-and-play integration with commercial Building Management Systems (BMS).
