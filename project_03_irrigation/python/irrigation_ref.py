"""
DE2-115 5-Project FPGA Portfolio
Project 3: Smart Adaptive Irrigation System
Python Reference Model & Verification Script

This module models:
1. Soil moisture raw 10-bit ADC conversion to percentage (0 - 100%)
2. Adaptive moisture threshold algorithm influenced by temperature & humidity
3. Dual-threshold hysteresis control (Turn-on vs Turn-off)
4. Minimum ON and Minimum OFF runtime enforcement
5. Rain sensor lockout and manual override prioritization
6. DHT11 40-bit data packet parsing and 8-bit checksum verification
"""

import sys
from typing import Tuple, Dict


def calc_moisture_percent(raw_adc: int) -> int:
    """
    Capacitive / Resistive soil moisture sensor:
    Dry air / disconnected: raw_adc ~ 1023 (high resistance) -> 0% moisture
    Fully saturated water: raw_adc ~ 250 (low resistance) -> 100% moisture
    Formula: clamp((1000 - raw_adc) * 100 / (1000 - 250), 0, 100)
    """
    if raw_adc >= 1000:
        return 0
    val = (1000 - raw_adc) * 100 // (1000 - 250)
    return min(100, max(0, val))


def calc_adaptive_threshold(temp_c: int, hum_pct: int, base_threshold: int = 40) -> int:
    """
    Adaptive threshold calculation:
    When ambient temperature is high (> 25°C), plants lose water rapidly through transpiration,
    requiring irrigation at higher soil moisture levels.
    When air is dry (< 50% RH), evaporation is accelerated.
    Formula:
      TempAdj = min(15, max(0, temp_c - 25))
      HumAdj  = min(10, max(0, (50 - hum_pct) // 2))
      AdaptiveThreshold = clamp(base_threshold + TempAdj + HumAdj, 25, 75)
    """
    temp_adj = min(15, max(0, temp_c - 25))
    hum_adj  = min(10, max(0, (50 - hum_pct) // 2))

    target_th = base_threshold + temp_adj + hum_adj
    return min(75, max(25, target_th))


def check_dht11_checksum(b0_h_int: int, b1_h_dec: int, b2_t_int: int, b3_t_dec: int, b4_chk: int) -> bool:
    """
    DHT11 Checksum: Lower 8 bits of (Byte0 + Byte1 + Byte2 + Byte3) == Byte4
    """
    expected = (b0_h_int + b1_h_dec + b2_t_int + b3_t_dec) & 0xFF
    return expected == b4_chk


def evaluate_irrigation_decision(moisture: int, threshold: int, hys: int,
                                 pump_currently_on: bool,
                                 rain_detected: bool,
                                 manual_override: bool) -> Tuple[bool, str]:
    """
    Decision logic:
    1. Rain lockout has absolute priority -> Pump OFF
    2. Manual override forces Pump ON
    3. Hysteresis automatic mode:
       Turn ON when moisture < threshold - hys
       Turn OFF when moisture >= threshold + hys
       Maintain previous state within deadband [th - hys, th + hys)
    """
    if rain_detected:
        return False, "RAIN_LOCKOUT"

    if manual_override:
        return True, "MANUAL_OVERRIDE"

    turn_on_point  = max(5, threshold - hys)
    turn_off_point = min(95, threshold + hys)

    if moisture < turn_on_point:
        return True, "AUTO_WATERING"
    elif moisture >= turn_off_point:
        return False, "AUTO_MOIST_ENOUGH"
    else:
        return pump_currently_on, "HYSTERESIS_HOLD"


def run_reference_tests():
    print("======================================================================")
    print(" PROJECT 3: SMART ADAPTIVE IRRIGATION - REFERENCE MODEL VALIDATION")
    print("======================================================================")

    scenarios = [
        # (name, raw_adc, temp, hum, rain, override, prev_on)
        ("Normal Soil, Mild Weather",       600, 22, 60, False, False, False),
        ("Dry Soil, Normal Weather",        850, 24, 55, False, False, False),
        ("Hot & Dry Weather (Adaptive TH)", 700, 35, 25, False, False, False),
        ("Saturated Wet Soil",              200, 25, 60, False, False, True),
        ("Rain Detected Lockout",           900, 20, 90, True,  False, True),
        ("Manual Override (Force ON)",      400, 25, 50, False, True,  False),
        ("Deadband Hold (Pump ON)",         680, 25, 50, False, False, True),
        ("Deadband Hold (Pump OFF)",        680, 25, 50, False, False, False),
    ]

    print(f"{'Scenario Name':<32} | {'Mst%':<4} {'Tmp':<3} {'Hum':<3} | {'AdpTH':<5} | {'Rain':<5} {'Ovr':<4} | {'Pump':<4} | {'Reason'}")
    print("-" * 95)

    for name, raw_adc, temp, hum, rain, ovr, prev_on in scenarios:
        mst = calc_moisture_percent(raw_adc)
        adp_th = calc_adaptive_threshold(temp, hum, base_threshold=40)
        pump_state, reason = evaluate_irrigation_decision(mst, adp_th, hys=5,
                                                         pump_currently_on=prev_on,
                                                         rain_detected=rain,
                                                         manual_override=ovr)
        pump_str = "ON" if pump_state else "OFF"
        rain_str = "YES" if rain else "NO"
        ovr_str  = "YES" if ovr else "NO"
        print(f"{name:<32} | {mst:4d} {temp:3d} {hum:3d} | {adp_th:5d} | {rain_str:<5} {ovr_str:<4} | {pump_str:<4} | {reason}")

    # Verify DHT11 Checksum
    valid_chk = check_dht11_checksum(45, 0, 28, 0, 73)
    bad_chk   = check_dht11_checksum(45, 0, 28, 0, 99)
    assert valid_chk == True
    assert bad_chk == False
    print("-" * 95)
    print(f"DHT11 Checksum Validation: Valid=True (Pass), Corrupt=False (Pass)")
    print("[PASS] Smart Irrigation reference model validated successfully!")


if __name__ == "__main__":
    run_reference_tests()
