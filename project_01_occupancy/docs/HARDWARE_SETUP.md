# Hardware Setup & Bench Testing Guide
## Project 1 - Multi-Zone Occupancy & Energy Decision Engine

---

## 1. Required Hardware
1. **Terasic DE2-115 Development Board** with Cyclone IV EP4CE115F29C7.
2. 12V DC power adapter (supplied with DE2-115).
3. USB Type-B cable for USB-Blaster II JTAG programming.
4. **Benchtop PIR Motion Sensors** (e.g. HC-SR501, 3.3V digital output mode).
5. **Relay Module** (optically isolated 4-channel 5V/3.3V relay board).
6. RS-232 to USB serial adapter (or connecting DE2-115 RS-232 port to PC).

---

## 2. Wiring & Pin Interconnects

### JP5 GPIO Header Wiring:
```
DE2-115 JP5 Header                   Sensor / Actuator Module
-------------------------------------------------------------
Pin 1  (PIN_AB22) ------------------> PIR Sensor 1 (OUT)
Pin 2  (PIN_AC15) ------------------> PIR Sensor 2 (OUT)
Pin 3  (PIN_AB21) ------------------> PIR Sensor 3 (OUT)
Pin 4  (PIN_Y17)  ------------------> PIR Sensor 4 (OUT)
Pin 6  (PIN_Y16)  ------------------> Relay 1 IN (Lighting Contactor)
Pin 7  (PIN_AD21) ------------------> Relay 2 IN (HVAC Contactor)
Pin 8  (PIN_AE16) ------------------> Relay 3 IN (Fan PWM Driver)
Pin 11 (GND)      ------------------> Common GND
Pin 29 (VCC3P3)   ------------------> Sensor VCC (3.3V)
```

> [!CAUTION]
> Never connect 5V output sensors directly to Cyclone IV FPGA I/O pins without a level-shifter or resistor divider. Set HC-SR501 jumper to 3.3V logic or power sensor from 3.3V rail.

---

## 3. Step-by-Step Programming & Execution Procedure

1. **Powering the Board**:
   - Plug the 12V DC power supply into the DE2-115 DC jack and press the red **POWER** switch.
   - Connect the USB cable between the PC and the DE2-115 USB-Blaster port.

2. **Compiling in Quartus Prime**:
   - Open Quartus Prime (v18.1 or later).
   - Open `project_01_occupancy/quartus/occupancy_top.qpf`.
   - Click **Processing -> Start Compilation** (Ctrl+L).

3. **Programming the FPGA**:
   - Open **Tools -> Programmer**.
   - Select **USB-Blaster [USB-0]** in Hardware Setup.
   - Click **Add File...** and select `project_01_occupancy/quartus/output_files/occupancy_top.sof`.
   - Check the **Program/Configure** box and click **Start**.

4. **Benchtop Testing without External Sensors**:
   - Flip `SW[4]` UP (sets Dark ambient mode).
   - Set `SW[17:16]` to `00` (5-second timeout).
   - Flip `SW[0]` UP: Notice `LEDR[0]` lights up immediately. `LEDG[0]` and `LEDG[4]` (Lights) turn ON. `HEX7..HEX6` display `Z1`, and `HEX5..HEX4` display `H1` (HVAC LOW).
   - Flip `SW[0]` DOWN: Notice Zone 1 enters TIMEOUT countdown. After 5 seconds, `LEDG[0]` turns OFF, `HEX7..HEX6` returns to `Z0`, and HVAC returns to `H0` (OFF).
   - Observe energy savings accumulation on `HEX3..HEX0` and telemetry streaming in serial terminal (115200 baud, 8-N-1).
