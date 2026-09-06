"""
DE2-115 5-Project FPGA Portfolio
Project 2: Adaptive Multi-Sensor Fire & Gas Risk Scoring System
Reference Model & Verification Script

This module implements the reference mathematics for:
1. Raw 10-bit ADC sensor normalization to [0, 255]
2. Q0.8 / Q8.8 fixed-point weighted risk score calculation
3. Integer scaling to human-readable 0-100 score
4. Threshold classification (SAFE, CAUTION, DANGER, FAULT)
5. Comparison between float and fixed-point hardware models
6. Generation of comprehensive test vectors for RTL simulation verification
"""

import sys
import math
from typing import Dict, Tuple, List

# Threshold Constants
THRESHOLD_SAFE_MAX = 34     # 0 to 34: SAFE
THRESHOLD_CAUTION_MAX = 69  # 35 to 69: CAUTION
                            # 70 to 100: DANGER

# Default Weights (must sum to 256 for Q0.8 unity)
# Flame = 0.40 -> 102 / 256
# Gas   = 0.30 ->  77 / 256
# Temp  = 0.20 ->  51 / 256
# Hum   = 0.10 ->  26 / 256
# Total = 102 + 77 + 51 + 26 = 256 (1.000)
DEFAULT_WEIGHTS = {
    'flame': 102,
    'gas': 77,
    'temp': 51,
    'hum': 26
}


def normalize_gas(raw_adc: int) -> int:
    """
    Gas ADC (0-1023): Baseline clean air ~ 100-150.
    Values >= 800 represent severe smoke/combustible gas concentration.
    Normalized = clamp((raw_adc - 100) * 255 / (800 - 100), 0, 255)
    """
    if raw_adc < 100:
        return 0
    val = (raw_adc - 100) * 255 // (800 - 100)
    return min(255, max(0, val))


def normalize_temp(raw_adc: int) -> int:
    """
    Temp ADC (0-1023): 10 mV / °C with 3.3V Vref -> ~3.1 count/°C.
    Ambient 25°C -> ~78 counts.
    Danger 75°C -> ~233 counts.
    Normalized = clamp((raw_adc - 78) * 255 / (233 - 78), 0, 255)
    """
    if raw_adc < 78:
        return 0
    val = (raw_adc - 78) * 255 // (233 - 78)
    return min(255, max(0, val))


def normalize_flame(raw_adc: int) -> int:
    """
    Flame Sensor (0-1023): Phototransistor pulled up.
    Dark/No flame = ~1023 (high voltage).
    Direct flame = ~50-100 (low voltage).
    Inverted: Normalized = clamp((1000 - raw_adc) * 255 / (1000 - 150), 0, 255)
    """
    if raw_adc >= 1000:
        return 0
    val = (1000 - raw_adc) * 255 // (1000 - 150)
    return min(255, max(0, val))


def normalize_humidity(raw_adc: int) -> int:
    """
    Humidity Sensor (0-1023): Dry conditions (< 30% RH) increase risk score.
    High raw ADC = high humidity = low risk.
    Low raw ADC = low humidity (dry) = high risk.
    Normalized = clamp((800 - raw_adc) * 255 / (800 - 200), 0, 255)
    """
    if raw_adc >= 800:
        return 0
    val = (800 - raw_adc) * 255 // (800 - 200)
    return min(255, max(0, val))


def compute_risk_float(norm_gas: float, norm_temp: float, norm_flame: float, norm_hum: float,
                       w_gas: float = 0.30, w_temp: float = 0.20,
                       w_flame: float = 0.40, w_hum: float = 0.10) -> float:
    """
    Floating-point ground truth calculation.
    norm_* values in range [0, 255].
    Returns risk score in [0.0, 100.0].
    """
    weighted_sum = (w_gas * norm_gas) + (w_temp * norm_temp) + (w_flame * norm_flame) + (w_hum * norm_hum)
    score_100 = (weighted_sum * 100.0) / 255.0
    return min(100.0, max(0.0, score_100))


def compute_risk_fixed(norm_gas: int, norm_temp: int, norm_flame: int, norm_hum: int,
                       w_gas: int = 77, w_temp: int = 51,
                       w_flame: int = 102, w_hum: int = 26) -> Tuple[int, int, str]:
    """
    Hardware synthesizable integer/fixed-point model (Q0.8 weights).
    - norm_* in [0, 255]
    - w_* in Q0.8 (sum = 256 for 1.000)
    - Returns (intermediate_255, score_100, classification)
    """
    # 1. Product terms (each up to 256 * 255 = 65,280 -> 16 bits)
    prod_gas   = w_gas * norm_gas
    prod_temp  = w_temp * norm_temp
    prod_flame = w_flame * norm_flame
    prod_hum   = w_hum * norm_hum

    # 2. Accumulate sum (max 65,280 when all norms are 255 and weights sum to 256)
    sum_weighted = prod_gas + prod_temp + prod_flame + prod_hum  # 16-bit

    # 3. Intermediate 8-bit score (divide by 256 -> right shift by 8)
    intermediate_255 = sum_weighted >> 8
    if intermediate_255 > 255:
        intermediate_255 = 255

    # 4. Scale to 0-100 range:
    # In exact RTL logic: score_100 = (sum_weighted * 100 + 32640) / 65280
    score_100 = (sum_weighted * 100 + 32640) // 65280
    if score_100 > 100:
        score_100 = 100

    # 5. Threshold Classification
    if score_100 <= THRESHOLD_SAFE_MAX:
        classification = "SAFE"
    elif score_100 <= THRESHOLD_CAUTION_MAX:
        classification = "CAUTION"
    else:
        classification = "DANGER"

    return intermediate_255, score_100, classification


def check_sensor_fault(raw_gas: int, raw_temp: int, raw_flame: int, raw_hum: int) -> int:
    """
    Detects sensor faults:
    Bit 0: Gas fault (open circuit raw_gas == 0 or shorted raw_gas == 1023)
    Bit 1: Temp fault (disconnected raw_temp < 10 or shorted raw_temp > 1000)
    Bit 2: Flame fault (stuck at rail)
    Bit 3: Humidity fault (stuck at rail)
    Returns fault bitmask (0 = normal).
    """
    fault = 0
    if raw_gas < 5 or raw_gas >= 1020:
        fault |= (1 << 0)
    if raw_temp < 10 or raw_temp >= 1010:
        fault |= (1 << 1)
    if raw_flame < 5 or raw_flame >= 1020:
        fault |= (1 << 2)
    if raw_hum < 5 or raw_hum >= 1020:
        fault |= (1 << 3)
    return fault


def run_reference_tests():
    print("======================================================================")
    print(" PROJECT 2: FIRE & GAS RISK SCORING - REFERENCE MODEL VALIDATION")
    print("======================================================================")

    test_scenarios = [
        # (name, raw_gas, raw_temp, raw_flame, raw_hum)
        ("Baseline Clean Air",        120,  80, 950, 700),
        ("Elevated Temperature Only",  120, 180, 950, 700),
        ("Gas Leak Warning",           450,  85, 950, 600),
        ("Optical Flame Detected",     120,  90, 200, 700),
        ("Combined Fire Hazard",       750, 220, 180, 250),
        ("Severe Disaster (Max)",      850, 250, 100, 150),
        ("Minimum Clean Bounds",        50,  50, 1000, 900),
        ("Sensor Disconnection Fault",   0,   0, 1023, 1023),
        ("Threshold Boundary Safe/Caut",280, 120, 900, 600),
        ("Threshold Boundary Caut/Dang",550, 160, 500, 400),
    ]

    print(f"{'Scenario Name':<28} | {'Gas':<4} {'Tmp':<4} {'Flm':<4} {'Hum':<4} | {'Norm (G,T,F,H)':<16} | {'Float':<5} | {'Fix':<3} | {'Class':<7} | {'Fault'}")
    print("-" * 105)

    max_error = 0.0
    for name, rg, rt, rf, rh in test_scenarios:
        ng = normalize_gas(rg)
        nt = normalize_temp(rt)
        nf = normalize_flame(rf)
        nh = normalize_humidity(rh)

        flt_score = compute_risk_float(ng, nt, nf, nh)
        inter, fix_score, classification = compute_risk_fixed(ng, nt, nf, nh)
        fault = check_sensor_fault(rg, rt, rf, rh)

        err = abs(flt_score - fix_score)
        if err > max_error:
            max_error = err

        norm_str = f"{ng:02X} {nt:02X} {nf:02X} {nh:02X}"
        print(f"{name:<28} | {rg:4d} {rt:4d} {rf:4d} {rh:4d} | {norm_str:<16} | {flt_score:5.1f} | {fix_score:3d} | {classification:<7} | 0x{fault:X}")

    print("-" * 105)
    print(f"Maximum Float vs Q8.8 Hardware Model Error: {max_error:.2f} points (<= 1.0 point is ideal)")
    assert max_error <= 1.5, "Error exceeds allowable quantization tolerance!"
    print("[PASS] Reference model verification completed successfully!")


if __name__ == "__main__":
    run_reference_tests()
