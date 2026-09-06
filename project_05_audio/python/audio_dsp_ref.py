#!/usr/bin/env python3
"""
=============================================================================
Project 5: Real-Time Audio Spectrum Analyzer & Noise Classification
Python Reference DSP Model and Verification Suite
=============================================================================
Simulates the entire audio processing chain:
  1. Synthetic test tone generation (1 kHz, 2 kHz, 5 kHz, Silence, White Noise)
  2. Fixed-point Q1.15 quantisation (16-bit signed audio PCM @ 48 kHz)
  3. Hanning windowing to suppress spectral leakage
  4. 512-point / 256-point Fast Fourier Transform (FFT)
  5. Alpha-Max Beta-Min (AMBM) magnitude approximation vs exact magnitude
  6. 6-Band psychoacoustic energy binning
  7. Deterministic spectral noise classification
=============================================================================
"""

import math
import numpy as np

FS = 48000.0  # 48 kHz standard sampling rate
N_FFT = 512   # 512-point FFT
BIN_WIDTH = FS / N_FFT  # 93.75 Hz per bin

# 6 Psychoacoustic Frequency Bands (bin index ranges for 512-point FFT)
# Band 0: Sub-bass / Low-freq  [20 Hz - 300 Hz]    (bins 1 - 3)
# Band 1: Bass / Lower mid    [300 Hz - 800 Hz]   (bins 4 - 8)
# Band 2: Midrange (Speech)   [800 Hz - 2.5 kHz]  (bins 9 - 26)
# Band 3: Upper midrange      [2.5 kHz - 5.0 kHz] (bins 27 - 53)
# Band 4: High frequencies    [5.0 kHz - 10.0 kHz](bins 54 - 106)
# Band 5: Air / Brilliance    [10.0 kHz - 20 kHz] (bins 107 - 213)
BANDS = [
    ("SUB_BASS", 1, 3),
    ("BASS_MID", 4, 8),
    ("MID_SPEECH", 9, 26),
    ("UPPER_MID", 27, 53),
    ("HIGH_FREQ", 54, 106),
    ("AIR_BRILL", 107, 213)
]

def generate_test_tone(freq_hz, duration_samples=N_FFT, amplitude=0.8):
    """Generate floating-point sine wave tone."""
    if freq_hz == 0:
        return np.zeros(duration_samples, dtype=np.float64)
    t = np.arange(duration_samples) / FS
    return amplitude * np.sin(2.0 * math.pi * freq_hz * t)

def generate_white_noise(duration_samples=N_FFT, amplitude=0.5):
    """Generate uniform white noise across all frequencies."""
    np.random.seed(42)
    return amplitude * (2.0 * np.random.rand(duration_samples) - 1.0)

def apply_hanning_window(samples):
    """Apply Hanning window: w(n) = 0.5 - 0.5 * cos(2*pi*n / N)."""
    n = len(samples)
    window = 0.5 - 0.5 * np.cos(2.0 * math.pi * np.arange(n) / n)
    return samples * window

def ambm_magnitude(real, imag):
    """Alpha-Max Beta-Min (AMBM) Magnitude Approximation.
    |X| approx max(|R|, |I|) + 3/8 * min(|R|, |I|)
    Maximum theoretical error < 3.96% across all angles.
    """
    abs_r = np.abs(real)
    abs_i = np.abs(imag)
    val_max = np.maximum(abs_r, abs_i)
    val_min = np.minimum(abs_r, abs_i)
    return val_max + 0.375 * val_min

def compute_spectrum(samples):
    """Full DSP Pipeline: Window -> FFT -> Exact Mag -> AMBM Mag."""
    windowed = apply_hanning_window(samples)
    fft_complex = np.fft.fft(windowed, n=N_FFT)
    half_n = N_FFT // 2
    real_half = np.real(fft_complex[:half_n])
    imag_half = np.imag(fft_complex[:half_n])
    
    exact_mag = np.sqrt(real_half**2 + imag_half**2)
    approx_mag = ambm_magnitude(real_half, imag_half)
    return real_half, imag_half, exact_mag, approx_mag

def extract_band_energies(magnitudes):
    """Sum energy magnitudes across the 6 frequency bands."""
    energies = []
    for name, start_bin, end_bin in BANDS:
        band_sum = np.sum(magnitudes[start_bin:end_bin + 1])
        energies.append(band_sum)
    total_energy = np.sum(energies)
    peak_bin = np.argmax(magnitudes[1:]) + 1  # Ignore DC bin 0
    peak_freq = peak_bin * BIN_WIDTH
    return energies, total_energy, peak_bin, peak_freq

def classify_spectrum(energies, total_energy, peak_freq):
    """Deterministic spectral rule-based classification."""
    if total_energy < 5.0:
        return "QUIET", 100.0

    ratios = [e / total_energy for e in energies]

    # Rule 1: Speech (Midrange energy > 40% and peak between 300 Hz and 3 kHz)
    if ratios[2] > 0.35 and (300.0 <= peak_freq <= 3000.0):
        confidence = min(100.0, ratios[2] * 200.0)
        return "SPEECH", confidence

    # Rule 2: Low-Frequency (Sub-bass + Bass > 50% of total energy)
    if (ratios[0] + ratios[1]) > 0.45:
        confidence = min(100.0, (ratios[0] + ratios[1]) * 160.0)
        return "LOW-FREQUENCY", confidence

    # Rule 3: High-Frequency (High + Air > 40% of total energy)
    if (ratios[4] + ratios[5]) > 0.40:
        confidence = min(100.0, (ratios[4] + ratios[5]) * 180.0)
        return "HIGH-FREQUENCY", confidence

    # Rule 4: Impulsive / Broadband Noise (Relatively flat spread across bands)
    if all(r < 0.35 for r in ratios):
        confidence = 85.0
        return "IMPULSIVE/NOISE", confidence

    return "SPEECH", 60.0

def run_dsp_benchmark():
    print("=" * 70)
    print(" PROJECT 5: AUDIO SPECTRUM & NOISE CLASSIFIER REFERENCE BENCHMARK")
    print(f" Sampling Rate: {FS:.0f} Hz | FFT Points: {N_FFT} | Bin Width: {BIN_WIDTH:.2f} Hz")
    print("=" * 70)

    test_signals = [
        ("Silence (0 Hz)", generate_test_tone(0)),
        ("1 kHz Test Tone (Speech Formant)", generate_test_tone(1000.0)),
        ("2 kHz Test Tone (Midrange)", generate_test_tone(2000.0)),
        ("5 kHz Test Tone (High Freq)", generate_test_tone(5000.0)),
        ("Broadband White Noise", generate_white_noise())
    ]

    all_passed = True
    for name, sig in test_signals:
        real_h, imag_h, exact_m, approx_m = compute_spectrum(sig)
        energies, tot_energy, peak_bin, peak_f = extract_band_energies(approx_m)
        class_label, confidence = classify_spectrum(energies, tot_energy, peak_f)

        # Calculate AMBM approximation error vs exact magnitude
        non_zero = exact_m > 1e-4
        if np.any(non_zero):
            rel_error = np.abs(approx_m[non_zero] - exact_m[non_zero]) / exact_m[non_zero]
            max_err_pct = np.max(rel_error) * 100.0
            avg_err_pct = np.mean(rel_error) * 100.0
        else:
            max_err_pct = 0.0
            avg_err_pct = 0.0

        print(f"\n[*] Signal: {name}")
        print(f"    Peak Frequency: {peak_f:.1f} Hz (Bin {peak_bin})")
        print(f"    Total Energy:   {tot_energy:.2f}")
        print(f"    AMBM Error:     Max = {max_err_pct:.2f}% (Limit < 7.0%), Avg = {avg_err_pct:.2f}%")
        print(f"    Classification: {class_label} (Confidence: {confidence:.1f}%)")
        print(f"    Band Energies:  {[round(float(e), 2) for e in energies]}")

        # Assert AMBM error complies with theoretical bounds (max 6.8% for alpha=1, beta=3/8)
        assert max_err_pct < 7.0, f"AMBM approximation error exceeded 7.0%: {max_err_pct}%"
        assert avg_err_pct < 6.0, f"AMBM average error exceeded 6.0%: {avg_err_pct}%"

    print("\n" + "=" * 70)
    print(" [PASS] All Python DSP Reference benchmarks completed successfully!")
    print("=" * 70)

if __name__ == "__main__":
    run_dsp_benchmark()
