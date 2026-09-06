# RTL Design Document
## Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System

### 1. Clock and Reset Strategy
- **Master Clock:** $50.000\text{ MHz}$ oscillator directly connected to Cyclone IV dedicated clock pin `PIN_Y2`.
- **Master Reset:** Active-low pushbutton `KEY[0]` synchronized via a 2-stage flip-flop synchronizer (`reset_synchronizer.v`). Internal synchronous reset `rst_n` and active-high `rst_sync` ensure clean assertion and deassertion without metastable transients.
- **Timing Constraint:** All internal flip-flops belong to the primary $50\text{ MHz}$ clock domain, eliminating clock domain crossing (CDC) hazards.

### 2. Fixed-Point Arithmetic & Q0.8 Representation
Floating-point arithmetic introduces severe resource penalties, variable latency, and verification complexity on FPGA targets. Project 2 strictly enforces Q0.8 unsigned fixed-point representation:

$$\text{Weight} = \lfloor \text{Fractional Weight} \times 256 \rfloor$$

| Sensor Parameter | Symbol | Normalized Weight | Q0.8 Integer | Bit Width |
|---|---|---|---|---|
| Optical Flame | $W_f$ | 0.40 | 102 | 8 bits |
| Combustible Gas | $W_g$ | 0.30 | 77 | 8 bits |
| Temperature | $W_t$ | 0.20 | 51 | 8 bits |
| Humidity | $W_h$ | 0.10 | 26 | 8 bits |
| **Sum of Weights** | $\sum W_i$ | **1.00** | **256** | **9 bits** |

#### Weighted Sum Calculation
1. Each normalized sensor reading $N_i \in [0, 255]$ is an 8-bit unsigned integer.
2. The product $P_i = W_i \times N_i$ produces an unsigned 16-bit number:
   $$\max(P_i) = 256 \times 255 = 65,280$$
3. The sum of all four products:
   $$S = P_g + P_t + P_f + P_h \le 65,280 \quad (\text{fits comfortably in 17 bits})$$
4. Integer scaling to human-readable percentage ($0..100$):
   $$\text{Score}_{100} = \left\lfloor \frac{S \times 100 + 32,640}{65,280} \right\rfloor$$
   The constant offset $+32,640$ implements unbiased round-to-nearest integer rounding.

### 3. Pipelined Normalization Pipeline
The normalizer operates over a 2-stage pipeline to achieve $F_{max} > 120\text{ MHz}$:
- **Stage 1 (Baseline & Difference):**
  - Subtracts sensor baseline calibration thresholds.
  - Inverts optical flame and humidity sensors (low resistance / voltage indicates hazard).
  - Evaluates open/short boundary conditions:
    $$(\text{raw} < 5) \lor (\text{raw} \ge 1020) \implies \text{Fault}$$
- **Stage 2 (Scaling & Clamping):**
  - Scales difference by dynamic range constant using synthesizable multiplier logic.
  - Saturated clamping prevents overflow:
    $$\text{if } (\text{val} > 255) \implies \text{val} = 255$$
  - Derives engineering units for display:
    $$\text{Temp}_{°C} = \frac{\text{raw} \times 165}{512}$$

### 4. Hardware Fault Handling & Diagnostic States
The system includes comprehensive fault diagnostics encoded in a 5-bit status register:
- **Bit 0:** Gas sensor disconnection / short-circuit.
- **Bit 1:** Temperature sensor out-of-range ($< -10°C$ or $> 85°C$).
- **Bit 2:** Flame sensor phototransistor stuck at power rail.
- **Bit 3:** Humidity sensor saturation / open circuit.
- **Bit 4:** SPI ADC communication watchdog timeout ($> 10\text{ ms}$ without response).

When any fault bit is active:
- Risk level is forced to `LVL_FAULT` (2'b11).
- 7-segment display shows `--` on affected sensor displays.
- LCD displays `FAULT: ERR 0xXX`.
- Buzzer pulses at a diagnostic $500\text{ Hz}$ tone.
- Telemetry packet reports fault code.
