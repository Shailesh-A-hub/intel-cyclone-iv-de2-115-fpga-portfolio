# Project 3: Smart Adaptive Irrigation System — Known Limitations & Mitigations

## 1. Hardware & Sensor Limitations

### 1.1 DHT11 Precision & Sampling Bandwidth
- **Limitation:** The DHT11 temperature and humidity sensor has an internal capacitive polymer element with a minimum sampling interval of $1–2\text{ seconds}$ and modest resolution ($\pm 1^\circ\text{C}$ temperature, $\pm 5\%$ relative humidity).
- **Mitigation:** The RTL controller enforces a hardware $2000\text{ ms}$ sampling watchdog. It ignores redundant read requests and latches previous valid readings during active readout cycles. For higher precision agricultural setups, the controller architecture directly accommodates the pin-compatible DHT22 ($0.1^\circ\text{C}$ / $0.1\%$ resolution) by adjusting scaling factors.

### 1.2 Soil Moisture Probe Electrolysis & Degradation
- **Limitation:** Resistive DC-excited soil moisture probes suffer rapid galvanic corrosion when powered continuously in moist soil.
- **Mitigation:** Capacitive soil moisture sensors (e.g., v1.2 corrosion-resistant analog probes) are strongly recommended over bare resistive prongs. In addition, an auxiliary GPIO pin on the DE2-115 can switch probe power via a P-MOSFET only during the $50\text{ ms}$ ADC sampling window.

### 1.3 Water Valve Water Hammer Effect
- **Limitation:** Abrupt closure of fast-acting 12V solenoid valves induces hydraulic shock ("water hammer"), which can damage plumbing lines.
- **Mitigation:** The RTL pump controller is designed to interface with solid-state relay drivers with zero-crossing triac switches or slow-closing motorized ball valves rather than rapid snap-action solenoids.

---

## 2. FPGA Resource & Timing Constraints

### 2.1 Single-Wire Line Contention
- **Limitation:** The DHT11 bidirectional single-wire bus uses an open-drain emulation with FPGA internal/external pull-up. If external cabling exhibits high capacitance ($>500\text{ pF}$ on long runs $>2\text{ m}$), rise times exceed $10\text{ us}$, corrupting bit pulse widths.
- **Mitigation:** A stiff external $3.3\text{ k}\Omega$ or $4.7\text{ k}\Omega$ pull-up resistor must be mounted directly adjacent to the DE2-115 GPIO header pin.

### 2.2 Relational State Synchronization
- **Limitation:** Status logging over UART at 115200 baud occurs periodically every $1000\text{ ms}$.
- **Mitigation:** All event flags (such as rain lockout or emergency stop) trigger immediate high-priority asynchronous packets to the UART buffer to eliminate telemetry latency.
