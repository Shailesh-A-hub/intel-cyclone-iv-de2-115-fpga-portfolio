# Project 4: FPGA-Based Gesture-Controlled Menu Interface — Known Limitations

## 1. Optical & Environmental Limitations

### 1.1 Ambient Infrared Interference
- **Limitation:** The APDS-9960 relies on reflected 950nm infrared light from an integrated IR LED. Direct sunlight, incandescent bulbs, or halogen lighting containing strong infrared spectral components can saturate the photodiode receivers, causing false triggers or reduced detection range.
- **Mitigation:** The sensor driver configures maximum gain (`GGAIN = 4x`) and narrow optical pulse widths (`GPULSE = 32us`). An optical bandpass filter (transmitting only 950nm) should be mounted over the sensor aperture in high-ambient environments.

### 1.2 Target Velocity & Sensing Distance Envelope
- **Limitation:** The optimal gesture detection distance is between $5\text{ cm}$ and $20\text{ cm}$ directly perpendicular to the sensor package. Swipes faster than $1.5\text{ m/s}$ or slower than $0.05\text{ m/s}$ may distort the phase differential vectors, causing them to be classified as `GESTURE_INVALID`.
- **Mitigation:** The RTL gesture decoder includes a temporal timeout window and requires at least two valid sample datasets before committing a directional classification decision.

---

## 2. Interface & Bus Timing Considerations

### 2.1 I2C Bus Pull-Up Resistance
- **Limitation:** The physical I2C open-drain bus lines on expansion header `JP5` require stiff pull-up resistors ($3.3\text{ k}\Omega$ to $4.7\text{ k}\Omega$). Using internal FPGA weak pull-ups alone results in slow rise times, limiting SCL frequency.
- **Mitigation:** External pull-up resistors are mandated on the daughterboard between SCL/SDA and the $3.3\text{ V}$ supply rail.

### 2.2 VGA Pixel Clock Domain Crossing
- **Limitation:** The VGA controller operates on a derived 25.175 MHz pixel clock (`vga_clk`), while menu states and sensor counts update in the 50.0 MHz system clock domain (`clk_50`).
- **Mitigation:** Display registers are double-buffered or statically latched during the vertical blanking interval (`VGA_VS = 0`), eliminating visual tearing and synchronization artifacts.
