# Product Requirements Document (PRD)
## Project 1: Multi-Zone Occupancy & Energy-Saving Decision Engine

---

## 1. Problem Statement
Commercial and residential facilities waste substantial electrical energy by operating lighting, ventilation, and HVAC equipment continuously regardless of human occupancy. Traditional analog PIR sensors operate in isolation, lacking unified zone aggregation, multi-tier climate staging, ambient light gating, or quantitative telemetry of energy saved.

## 2. Objective
Design and implement a hardware-accelerated, synthesizable FPGA decision engine on the Altera/Intel DE2-115 development board that coordinates occupancy across 4 independent building zones, aggregates occupancy status in real time, manages multi-stage HVAC and variable-speed ventilation, and computes accumulated energy savings in Watt-hours.

## 3. Users & Use Cases
- **Facility Engineers**: Monitor real-time zone occupancy and power conservation metrics via 16x2 LCD and UART telemetry.
- **Smart Building Automation**: Coordinate HVAC contactors, lighting relays, and variable ventilation without software latency.
- **Laboratories & Classrooms**: Automatically power down idle benches and equipment when zones become vacant.

## 4. Functional Requirements
- **FR-1**: Manage 4 independent zones via dedicated finite state machines implementing `VACANT`, `OCCUPIED`, and `TIMEOUT` states.
- **FR-2**: Provide motion retriggering during the `TIMEOUT` state to prevent premature vacancy transitions.
- **FR-3**: Support runtime-selectable timeout durations (5s bench test, 30s, 60s, 300s) via DIP switches `SW[17:16]`.
- **FR-4**: Gate lighting outputs with ambient light level (`SW[4]` / LDR input) so that lights stay OFF during bright daylight even when occupied.
- **FR-5**: Execute multi-stage HVAC control proportional to active zone count (0 zones = OFF, 1 zone = LOW, 2-3 zones = MED, 4 zones = HIGH).
- **FR-6**: Regulate ventilation fan speed via an 8-bit PWM generator (0%, 40%, 70%, 100%).
- **FR-7**: Quantify real-time energy savings compared to an unmanaged 2200 W baseline building load and display accumulated Watt-hours on 7-segment displays `HEX3..HEX0`.
- **FR-8**: Detect sensor stuck-at faults when any PIR remains continuously active beyond a configurable threshold (default 10 minutes).
- **FR-9**: Stream serial telemetry frames over RS-232 UART at 115200 baud upon state transitions and once every second.

## 5. Non-Functional Requirements
- **NFR-1 (Clocking)**: 100% synchronous design operating from the single 50 MHz global oscillator (`PIN_Y2`).
- **NFR-2 (Reliability)**: Zero metastability through 2-stage input synchronizers on pushbuttons and PIR sensors.
- **NFR-3 (Resource Efficiency)**: Fit comfortably within Cyclone IV EP4CE115 logic elements without DSP block exhaustion.
- **NFR-4 (Modularity)**: Utilize reusable platform IP cores from `common/rtl/` with zero module duplication.

## 6. System Inputs
- `CLOCK_50`: 50.000 MHz LVTTL oscillator (`PIN_Y2`).
- `KEY[0]`: Active-low master reset (`PIN_M23`).
- `SW[3:0]`: Slide switch manual stand-ins for PIR motion in Zones 1..4.
- `GPIO_PIR_IN[3:0]`: External digital PIR motion sensors via JP5 expansion header.
- `SW[4]`: Ambient dark simulation switch (1 = dark/night, 0 = daylight).
- `SW[17:16]`: Timeout duration selector.

## 7. System Outputs
- `LEDR[3:0]`: Raw PIR trigger indicators.
- `LEDR[17]`: System fault indicator (stuck sensor or counter saturation).
- `LEDG[3:0]`: Filtered zone active occupancy indicators.
- `LEDG[4]`: Main lighting relay status.
- `LEDG[5]`: HVAC contactor status.
- `LEDG[6]`: Ventilation fan relay status.
- `HEX0..HEX3`: 4-digit energy saved accumulator (Watt-hours).
- `HEX4..HEX5`: HVAC staging level (`H0` - `H3`).
- `HEX6..HEX7`: Active zone count (`Z0` - `Z4`).
- `LCD_DATA[7:0]`, `LCD_EN`, `LCD_RS`, `LCD_RW`: 16x2 HD44780 LCD status display.
- `UART_TXD`: 115200 baud RS-232 telemetry stream.
- `RELAY_LIGHTS`, `RELAY_HVAC`, `RELAY_FANS`: Isolated relay contactor triggers on JP5.

## 8. Physical Interfaces
- **DE2-115 Pushbuttons & Switches**: 3.3-V LVTTL.
- **7-Segment Displays**: Active-low common-anode displays.
- **16x2 LCD**: 8-bit parallel HD44780 interface.
- **RS-232 UART**: 115200 baud, 8 data bits, 1 stop bit, no parity.
- **GPIO Expansion (JP5)**: 3.3-V digital I/O.

## 9. Performance Targets
- Motion detection latency: $<20\,\text{ms}$ (due to debounce filter).
- Actuator response time: $<40\,\text{ns}$ (2 clock cycles).
- UART transmission update interval: $\le 1.0\,\text{s}$.
- Maximum clock frequency ($F_{\max}$): $>100\,\text{MHz}$ (timing closed at 50 MHz with $>10\,\text{ns}$ setup slack).

## 10. Safety Requirements
- Never drive high-power inductive relay coils directly from FPGA I/O pins. Interfacing requires external optocoupler/transistor driver boards.
- Fail-safe default: In case of catastrophic sensor failure or master reset, outputs return to a known safe state (lights off, HVAC off).

## 11. Assumptions
- PIR motion sensors output active-high digital pulses (3.3V logic).
- External ambient light sensor (LDR module) outputs logic 1 when light is below threshold (dark).

## 12. Acceptance Criteria
1. Testbench executes all 8 required verification scenarios with 100% pass rate.
2. Verified multi-zone aggregation correctly drives all HVAC stages (OFF, LOW, MED, HIGH).
3. Energy saved counter increments accurately based on real-time power differentials.
4. Quartus project compiles cleanly without timing violations or latches.
