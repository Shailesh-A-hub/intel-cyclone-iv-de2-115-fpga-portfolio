# Project 5: Real-Time Audio Spectrum Analyzer & Noise Classifier — Known Limitations

## 1. Algorithmic & Mathematical Boundaries

1. **AMBM Magnitude Approximation Variance:**
   - The Alpha-Max Beta-Min algorithm introduces a small systematic error ($\le 3.96\%$) compared to exact floating-point Euclidean magnitude ($\sqrt{I^2 + Q^2}$). This trade-off was deliberately chosen to eliminate multi-cycle square root hardware and DSP multipliers, and has negligible effect on visual equalizer bar display and noise classification accuracy.
2. **Frequency Bin Granularity:**
   - At a 48 kHz sampling rate with a 256-point FFT, the frequency bin resolution is $\Delta f = 48000 / 256 = 187.5\text{ Hz}$. Low frequencies below $100\text{ Hz}$ are grouped into the first bin (DC/Sub-Bass). Increasing resolution to 1024 points would narrow $\Delta f$ to $46.875\text{ Hz}$ at the cost of additional block RAM and latency.
3. **Deterministic vs. Machine Learning Classification:**
   - The noise classifier uses a deterministic decision-tree based on psychoacoustic sub-band energy ratios rather than a multi-layer neural network or convolutional neural network (CNN). While deterministic rules execute in a single clock cycle with zero memory overhead, highly complex overlapping acoustic scenes (e.g. speech masked by loud machinery) may be classified under the dominant energy band.

---

## 2. Hardware & Electrical Considerations

1. **Analog Line-In Signal Level:**
   - The Wolfson WM8731 codec line input expects a standard line-level signal ($1.0\text{ V}_{\text{RMS}}$). Direct connection of un-amplified dynamic microphones to the Line-In jack may result in low signal amplitude and require digital gain boosting (`SW[3:0]`).
2. **I2C Codec Acknowledgment on Board Power-Up:**
   - If the audio daughterboard power rails experience slow ramp times, the initial I2C configuration packet may rarely NACK. The architecture provides a dedicated hardware re-configuration pushbutton (`KEY[1]`) that allows instant re-initialization without requiring FPGA reprogramming.
3. **VGA Pixel Clock Generation:**
   - The 25 MHz pixel clock is derived from the 50 MHz master clock via a synchronous toggle flip-flop rather than an analog Phase-Locked Loop (PLL). While compliant with VESA 640x480 @ 60Hz timing on all modern monitors, strict $25.175\text{ MHz}$ broadcast studio video equipment can use an Altera ALTPLL MegaFunction if desired.
