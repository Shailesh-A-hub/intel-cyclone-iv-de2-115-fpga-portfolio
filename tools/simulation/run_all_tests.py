#!/usr/bin/env python3
"""
=============================================================================
DE2-115 FPGA Portfolio - Master Automated Test Runner
=============================================================================
Discovers and executes unit and integration testbenches across common IP
and all 5 projects. Compatible with Icarus Verilog (iverilog/vvp) and ModelSim (vlog/vsim).
"""

import os
import sys
import subprocess
import time
import glob
from pathlib import Path

# Paths relative to repository root
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
COMMON_RTL = REPO_ROOT / "common" / "rtl"
COMMON_SIM = REPO_ROOT / "common" / "sim"

TEST_SUITES = [
    {
        "name": "tb_reset_synchronizer",
        "tb": COMMON_SIM / "tb_reset_synchronizer.v",
        "rtl": [COMMON_RTL / "reset_synchronizer.v"]
    },
    {
        "name": "tb_clock_divider",
        "tb": COMMON_SIM / "tb_clock_divider.v",
        "rtl": [COMMON_RTL / "clock_divider.v"]
    },
    {
        "name": "tb_button_debounce",
        "tb": COMMON_SIM / "tb_button_debounce.v",
        "rtl": [COMMON_RTL / "button_debounce.v"]
    },
    {
        "name": "tb_edge_detector",
        "tb": COMMON_SIM / "tb_edge_detector.v",
        "rtl": [COMMON_RTL / "edge_detector.v"]
    },
    {
        "name": "tb_seven_seg",
        "tb": COMMON_SIM / "tb_seven_seg.v",
        "rtl": [COMMON_RTL / "seven_seg_hex.v", COMMON_RTL / "seven_seg_dec.v"]
    },
    {
        "name": "tb_timers",
        "tb": COMMON_SIM / "tb_timers.v",
        "rtl": [COMMON_RTL / "timer_ms.v", COMMON_RTL / "periodic_timer.v", COMMON_RTL / "timeout_timer.v"]
    },
    {
        "name": "tb_pwm_generator",
        "tb": COMMON_SIM / "tb_pwm_generator.v",
        "rtl": [COMMON_RTL / "pwm_generator.v"]
    },
    {
        "name": "tb_uart",
        "tb": COMMON_SIM / "tb_uart.v",
        "rtl": [COMMON_RTL / "uart_tx.v", COMMON_RTL / "uart_rx.v"]
    },
    {
        "name": "tb_spi_master",
        "tb": COMMON_SIM / "tb_spi_master.v",
        "rtl": [COMMON_RTL / "spi_master.v"]
    },
    {
        "name": "tb_i2c_master",
        "tb": COMMON_SIM / "tb_i2c_master.v",
        "rtl": [COMMON_RTL / "i2c_master.v"]
    },
    {
        "name": "tb_vga_timing_controller",
        "tb": COMMON_SIM / "tb_vga_timing_controller.v",
        "rtl": [COMMON_RTL / "vga_timing_controller.v"]
    },
    {
        "name": "tb_i2s_receiver",
        "tb": COMMON_SIM / "tb_i2s_receiver.v",
        "rtl": [COMMON_RTL / "i2s_receiver.v"]
    },
    {
        "name": "tb_occupancy_top (Project 1 Integration)",
        "tb": REPO_ROOT / "project_01_occupancy" / "sim" / "tb_occupancy_top.v",
        "rtl": [
            REPO_ROOT / "project_01_occupancy" / "rtl" / "occupancy_top.v",
            REPO_ROOT / "project_01_occupancy" / "rtl" / "zone_fsm.v",
            REPO_ROOT / "project_01_occupancy" / "rtl" / "energy_decision_engine.v",
            REPO_ROOT / "project_01_occupancy" / "rtl" / "occupancy_uart_logger.v",
            COMMON_RTL / "reset_synchronizer.v",
            COMMON_RTL / "button_debounce.v",
            COMMON_RTL / "timer_ms.v",
            COMMON_RTL / "timer_sec.v",
            COMMON_RTL / "seven_seg_hex.v",
            COMMON_RTL / "seven_seg_dec.v",
            COMMON_RTL / "pwm_generator.v",
            COMMON_RTL / "lcd_hd44780_controller.v",
            COMMON_RTL / "uart_tx.v"
        ]
    },
    {
        "name": "tb_fire_gas_top (Project 2 Integration)",
        "tb": REPO_ROOT / "project_02_fire_gas" / "sim" / "tb_fire_gas_top.v",
        "rtl": [
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "fire_gas_top.v",
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "mcp3008_adc_controller.v",
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "sensor_normalizer.v",
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "risk_engine_q8_8.v",
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "alarm_buzzer_controller.v",
            REPO_ROOT / "project_02_fire_gas" / "rtl" / "fire_gas_uart_logger.v",
            COMMON_RTL / "reset_synchronizer.v",
            COMMON_RTL / "button_debounce.v",
            COMMON_RTL / "spi_master.v",
            COMMON_RTL / "pwm_generator.v",
            COMMON_RTL / "lcd_hd44780_controller.v",
            COMMON_RTL / "seven_seg_dec.v",
            COMMON_RTL / "periodic_timer.v",
            COMMON_RTL / "uart_tx.v"
        ]
    },
    {
        "name": "tb_irrigation_top (Project 3 Integration)",
        "tb": REPO_ROOT / "project_03_irrigation" / "sim" / "tb_irrigation_top.v",
        "rtl": [
            REPO_ROOT / "project_03_irrigation" / "rtl" / "irrigation_top.v",
            REPO_ROOT / "project_03_irrigation" / "rtl" / "dht11_controller.v",
            REPO_ROOT / "project_03_irrigation" / "rtl" / "soil_moisture_adc_reader.v",
            REPO_ROOT / "project_03_irrigation" / "rtl" / "adaptive_threshold_engine.v",
            REPO_ROOT / "project_03_irrigation" / "rtl" / "pump_controller_fsm.v",
            REPO_ROOT / "project_03_irrigation" / "rtl" / "irrigation_uart_logger.v",
            COMMON_RTL / "reset_synchronizer.v",
            COMMON_RTL / "button_debounce.v",
            COMMON_RTL / "spi_master.v",
            COMMON_RTL / "lcd_hd44780_controller.v",
            COMMON_RTL / "seven_seg_dec.v",
            COMMON_RTL / "periodic_timer.v",
            COMMON_RTL / "uart_tx.v"
        ]
    },
    {
        "name": "tb_gesture_top (Project 4 Integration)",
        "tb": REPO_ROOT / "project_04_gesture" / "sim" / "tb_gesture_top.v",
        "rtl": [
            REPO_ROOT / "project_04_gesture" / "rtl" / "gesture_top.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "ir_cross_gesture_decoder.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "apds9960_i2c_driver.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "gesture_decoder.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "menu_fsm.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "vga_menu_display.v",
            REPO_ROOT / "project_04_gesture" / "rtl" / "gesture_uart_logger.v",
            COMMON_RTL / "reset_synchronizer.v",
            COMMON_RTL / "button_debounce.v",
            COMMON_RTL / "edge_detector.v",
            COMMON_RTL / "i2c_master.v",
            COMMON_RTL / "lcd_hd44780_controller.v",
            COMMON_RTL / "vga_timing_controller.v",
            COMMON_RTL / "seven_seg_hex.v",
            COMMON_RTL / "seven_seg_dec.v",
            COMMON_RTL / "periodic_timer.v",
            COMMON_RTL / "uart_tx.v"
        ]
    },
    {
        "name": "tb_audio_top (Project 5 Integration)",
        "tb": REPO_ROOT / "project_05_audio" / "sim" / "tb_audio_top.v",
        "rtl": [
            REPO_ROOT / "project_05_audio" / "rtl" / "audio_top.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "sine_lut_generator.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "audio_pingpong_buffer.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "hanning_window.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "fft_radix2_core.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "magnitude_approximator.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "spectral_band_extractor.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "noise_classifier.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "vga_spectrum_display.v",
            REPO_ROOT / "project_05_audio" / "rtl" / "audio_uart_logger.v",
            COMMON_RTL / "reset_synchronizer.v",
            COMMON_RTL / "button_debounce.v",
            COMMON_RTL / "periodic_timer.v",
            COMMON_RTL / "wm8731_configurator.v",
            COMMON_RTL / "i2c_master.v",
            COMMON_RTL / "i2s_receiver.v",
            COMMON_RTL / "vga_timing_controller.v",
            COMMON_RTL / "lcd_hd44780_controller.v",
            COMMON_RTL / "seven_seg_hex.v",
            COMMON_RTL / "seven_seg_dec.v",
            COMMON_RTL / "uart_tx.v"
        ]
    }
]

def run_iverilog_test(test):
    test_name = test["name"]
    tb_path = str(test["tb"])
    rtl_paths = [str(p) for p in test["rtl"]]
    clean_name = test_name.replace(" ", "_").replace("(", "").replace(")", "")
    out_vvp = str(REPO_ROOT / f"sim_{clean_name}.vvp")

    cmd_compile = ["iverilog", "-g2001", "-o", out_vvp, tb_path] + rtl_paths
    t0 = time.time()
    try:
        proc_c = subprocess.run(cmd_compile, capture_output=True, text=True, timeout=30)
        if proc_c.returncode != 0:
            return False, f"Compilation Error:\n{proc_c.stderr}\n{proc_c.stdout}", time.time() - t0

        cmd_run = ["vvp", out_vvp]
        proc_r = subprocess.run(cmd_run, capture_output=True, text=True, timeout=60)
        elapsed = time.time() - t0

        # Clean up vvp file
        if os.path.exists(out_vvp):
            os.remove(out_vvp)

        output = proc_r.stdout + "\n" + proc_r.stderr
        is_success = (
            proc_r.returncode == 0 and
            ("STATUS: FAIL" not in output) and
            ("*** ERROR ***" not in output) and
            ("FAIL:" not in output or "FAIL: 0" in output) and
            ("FAILED:" not in output or "FAILED: 0" in output) and
            ("PASS" in output)
        )
        if is_success:
            return True, output.strip(), elapsed
        else:
            return False, output.strip(), elapsed
    except Exception as e:
        if os.path.exists(out_vvp):
            os.remove(out_vvp)
        return False, str(e), time.time() - t0

def main():
    print("=" * 70)
    print(" DE2-115 FPGA PORTFOLIO - COMMON PLATFORM REGRESSION SUITE")
    print("=" * 70)

    passed = 0
    failed = 0
    results = []

    for test in TEST_SUITES:
        name = test["name"]
        print(f"[*] Running testbench: {name} ... ", end="", flush=True)
        ok, log, elapsed = run_iverilog_test(test)
        if ok:
            print(f"PASS ({elapsed:.2f}s)")
            passed += 1
            results.append((name, "PASS", elapsed, log))
        else:
            print(f"FAIL ({elapsed:.2f}s)")
            failed += 1
            results.append((name, "FAIL", elapsed, log))

    print("\n" + "=" * 70)
    print(" TEST RESULTS SUMMARY")
    print("=" * 70)
    print(f"{'Testbench Name':<32} | {'Status':<8} | {'Duration':<8}")
    print("-" * 70)
    for name, status, elapsed, _ in results:
        print(f"{name:<32} | {status:<8} | {elapsed:>6.2f}s")
    print("=" * 70)
    print(f"Total: {len(TEST_SUITES)} | Passed: {passed} | Failed: {failed}")
    print("=" * 70)

    if failed > 0:
        print("\n--- Failure Logs ---")
        for name, status, _, log in results:
            if status == "FAIL":
                print(f"\n[FAIL LOG] {name}:")
                print(log)
        sys.exit(1)
    else:
        print("\n[SUCCESS] All common platform unit testbenches PASSED!")
        sys.exit(0)

if __name__ == "__main__":
    main()
