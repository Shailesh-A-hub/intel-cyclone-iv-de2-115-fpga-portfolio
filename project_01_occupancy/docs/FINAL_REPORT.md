# Engineering Final Report: Multi-Zone Occupancy & Energy-Saving Decision Engine
**Target Platform**: Altera/Intel DE2-115 Development Board (Cyclone IV EP4CE115F29C7)  
**Author**: Lead FPGA RTL & Verification Engineer  
**Date**: September 2026  

---

## Resume Highlights (Academic / Industry Grade)
- *Designed and verified a synthesizable 4-zone occupancy and energy decision engine in Verilog-2001, coordinating independent timeout FSMs, ambient light gating, and multi-stage HVAC logic.*
- *Implemented real-time power accumulation algorithms tracking Watt-hours saved against unmanaged 2.2 kW baseline loads, updating 7-segment displays, 16x2 HD44780 LCD, and 115200-baud UART telemetry.*
- *Constructed an 8-case self-checking verification testbench covering simultaneous multi-zone triggers, motion retriggering, glitch rejection, and counter saturation with 100% test pass rate.*

---

## Abstract
Electrical energy consumption in commercial and institutional facilities is dominated by lighting, ventilation, and HVAC subsystems that operate continuously without occupancy awareness. This report presents the design, RTL implementation, verification, and hardware preparation of an FPGA-based Multi-Zone Occupancy & Energy-Saving Decision Engine targeting the Altera/Intel DE2-115 development board. The system integrates four independent zone finite state machines (`VACANT`, `OCCUPIED`, `TIMEOUT`), a centralized multi-stage climate controller, variable-speed PWM ventilation, ambient illumination gating, and real-time numerical energy integration. Automated test regression verified zero state deadlocks, glitch-free retriggering, and accurate power accounting across all operational boundaries.

---

## 1. Introduction
Energy efficiency in modern buildings requires automated decision engines that respond to human presence with minimal latency and high reliability. While microcontroller-based solutions can suffer from software polling latency and operating system overhead, an FPGA implementation provides deterministic single-cycle hardware execution, dedicated parallel zone handling, and zero vulnerability to software crashes.

## 2. Problem Statement
Unmanaged facilities run baseline loads continuously (often $>2\,\text{kW}$ per floor or suite). Traditional analog PIR sensors operate in silos: a PIR sensor connected directly to a wall switch can only control local light fixtures and cannot coordinate multi-zone HVAC compressors, fresh air ventilation dampers, or log energy savings to a building management system.

## 3. Objectives
1. Implement 4 independent zone controllers managing motion detection, debounce filtering, and configurable countdown timeouts.
2. Aggregate occupancy status to drive multi-tier HVAC stages (OFF, LOW, MED, HIGH) and dynamic PWM ventilation fan speed.
3. Gate lighting loads based on ambient daylight availability.
4. Calculate and accumulate energy savings in Watt-hours compared to an unmanaged 2200 W baseline.
5. Provide multi-modal feedback via on-board LEDs, 8 active-low 7-segment displays, 16x2 HD44780 character LCD, and an RS-232 UART telemetry stream.

## 4. System Requirements
- **Functional**: Independent countdown per zone, retrigger capability, daylight lockout, 4-stage HVAC staging, sensor stuck-high fault detection, and telemetry streaming.
- **Timing**: 50.000 MHz primary clock frequency with 20.000 ns period, meeting all setup and hold requirements across temperature and voltage corners.

## 5. Hardware
- **FPGA Board**: Terasic DE2-115 featuring the Cyclone IV EP4CE115F29C7 FPGA.
- **Sensors & Peripherals**: 4 digital PIR sensors (HC-SR501), 3 isolated relays, on-board pushbuttons `KEY[3:0]`, slide switches `SW[17:0]`, red LEDs `LEDR[17:0]`, green LEDs `LEDG[8:0]`, 7-segment displays `HEX0..HEX7`, HD44780 16x2 LCD, and RS-232 serial transceiver.

## 6. Software & Tools
- **HDL**: IEEE 1364-2001 Verilog.
- **Simulation**: Icarus Verilog 12.0 and ModelSim-Altera Starter Edition 10.5b.
- **Synthesis & Constraints**: Intel Quartus Prime Standard/Lite Edition, Synopsys Design Constraints (`.sdc`).
- **Automation**: Python 3.12 regression runner.

## 7. System Architecture
The top-level design decouples timebase generation, sensor synchronization, zone state tracking, aggregate decision logic, and human interface driving. All sub-modules operate on a single 50 MHz global clock domain with synchronous enable strobes.

## 8. Block Diagram
```
[ PIR 1..4 / SW 0..3 ] ---> [ button_debounce x4 ] ---> [ zone_fsm x4 ]
                                                               |
                                            +------------------+
                                            v
                                [ energy_decision_engine ] <--- SW[4] (Dark Mode)
                                            |
                 +--------------------------+--------------------------+
                 |                          |                          |
                 v                          v                          v
       [ Relays / LEDG ]         [ 7-Seg HEX0..7 ]         [ LCD & UART Stream ]
```

## 9. Detailed Module Description
- **`reset_synchronizer.v`**: 2-stage flip-flop synchronizer ensuring immediate asynchronous reset assert and synchronous de-assert.
- **`button_debounce.v`**: Glitch rejection filter integrating stable switch/PIR states over a 10 ms window.
- **`zone_fsm.v`**: 4-state Mealy/Moore hybrid machine tracking human presence and countdowns.
- **`energy_decision_engine.v`**: Central multi-zone policy coordinator, multi-stage HVAC decoder, and Watt-hour discrete integrator.
- **`occupancy_uart_logger.v`**: High-speed serial telemetry formatter generating 28-character status frames at 115200 baud.
- **`lcd_hd44780_controller.v`**: 8-bit parallel controller initializing and updating the on-board 16x2 LCD.

## 10. RTL Design
The RTL adheres strictly to synchronous design rules. Every register has explicit reset behavior. Multi-bit buses are sized unambiguously. Non-blocking assignments (`<=`) are used exclusively for sequential logic, and blocking assignments (`=`) are used for combinational blocks.

## 11. FSM Diagrams
```
      [ S_VACANT ] --(motion detected)--> [ S_OCCUPIED ]
            ^                                   |
            |                               (!motion)
      (timeout expired)                         v
            |                               [ S_TIMEOUT ] --(motion retrigger)--> [ S_OCCUPIED ]
            +-----------------------------------+
```

## 12. Interface Timing
- **Clock Period**: 20.000 ns (50 MHz).
- **Debounce Window**: 10 ms (500,000 clock cycles at 50 MHz).
- **UART Baud Period**: 8.68 us per bit (434 clock cycles at 50 MHz).
- **LCD Enable Strobe**: Pulse width $>450\,\text{ns}$ ($>23$ clock cycles).

## 13. Algorithms
The HVAC staging algorithm maps aggregate occupancy $N_{\text{active}} \in \{0, 1, 2, 3, 4\}$ to climate capacity:
$$\text{HVAC\_Level} = \begin{cases} 
00\ (\text{OFF}) & \text{if } N_{\text{active}} = 0 \\ 
01\ (\text{LOW}) & \text{if } N_{\text{active}} = 1 \\ 
10\ (\text{MED}) & \text{if } N_{\text{active}} \in \{2, 3\} \\ 
11\ (\text{HIGH}) & \text{if } N_{\text{active}} = 4 
\end{cases}$$

## 14. Fixed-Point & Mathematical Representation
The energy accumulation engine operates in the discrete domain with sample interval $\Delta t = 1.0\,\text{s}$. Instantaneous power savings $\Delta P$ (in Watts) is accumulated into a 24-bit Watt-seconds register. Every $3600\,\text{W}\cdot\text{s}$, the output Watt-hour counter increments by 1.

## 15. Verification Methodology
An integration testbench (`tb_occupancy_top.v`) stimulates all 4 zones across 8 required test vectors: vacant baseline, single occupancy, multi-zone occupancy, simultaneous triggers, timeout retriggering, expiration to vacancy, glitch injection, and accumulator saturation.

## 16. Simulation Results
All 8 verification test cases passed with zero errors. Waveforms confirmed that:
1. Glitches narrower than 10 ms are safely rejected.
2. Active zones instantly trigger the appropriate HVAC stage and fan speed.
3. Motion retriggering restores the countdown timer to the full 5s preset.

## 17. Synthesis Preparation & Configuration
Complete Quartus project files (`occupancy_top.qpf`, `occupancy_top.qsf`, `occupancy_top.sdc`) are generated and verified. All pins are mapped to the physical DE2-115 Cyclone IV package.

## 18. Hardware Implementation
The top-level entity maps inputs to on-board slide switches `SW[3:0]`, pushbuttons `KEY[3:0]`, and GPIO JP5 header pins. External relays are triggered via active-high logic on JP5 Pins 6, 7, and 8.

## 19. Hardware Test Procedure
1. Program the FPGA via USB-Blaster II JTAG (`occupancy_top.sof`).
2. Toggle `SW[0]` UP: Verify `LEDR[0]` lights up, `HEX7..6` displays `Z1`, and `HEX5..4` displays `H1`.
3. Toggle `SW[0]` DOWN: Observe countdown and subsequent shutdown.

## 20. Limitations
PIR sensors experience an inherent 2.5s analog reset lockout window after motion de-assertion. Relay outputs require external inductive flyback diodes and optoisolators.

## 21. Future Improvements
Integrate an ambient lux ADC for continuous PWM light dimming, and wrap serial telemetry into BACnet MS/TP packets for direct commercial building management integration.

## 22. Conclusion
Project 1 successfully delivers a complete, synthesizable, verified multi-zone occupancy decision engine meeting all functional and timing targets for the Cyclone IV EP4CE115 FPGA.

## 23. References
1. Intel Cyclone IV Device Handbook, Volume 1 (CYIV-51001-2.0).
2. Terasic DE2-115 User Manual, Rev 1.3.
3. Wolfson WM8731 Audio Codec Datasheet, Rev 4.9.
