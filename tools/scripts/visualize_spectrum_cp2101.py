#!/usr/bin/env python3
"""
=============================================================================
DE2-115 Project 5: Real-Time Audio Spectrum Visualizer via CP2101 USB-UART
=============================================================================
Reads real-time audio analysis packets from the FPGA over the CP2101 bridge:
  Format: "[AUDIO] CLS=VOIC BIN=012 MAG=04820 [######..........]\r\n"
Displays live, colorized audio classification and VU meter in your terminal.
"""

import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("[ERROR] 'pyserial' is not installed.")
    print("        Please run: pip install pyserial")
    sys.exit(1)

def find_cp210x_port():
    ports = serial.tools.list_ports.comports()
    for port, desc, hwid in sorted(ports):
        if "CP210" in desc or "Silicon Labs" in desc or "UART" in desc:
            return port
    return ports[0].device if ports else None

def main():
    port = find_cp210x_port()
    if not port:
        print("[ERROR] No serial ports found. Please connect your CP2101 USB-UART module.")
        sys.exit(1)

    baud = 115200
    print("=" * 65)
    print(" DE2-115 PROJECT 5: LIVE AUDIO SPECTRUM VISUALIZER")
    print(f" Connecting to: {port} @ {baud} baud (8N1)")
    print("=" * 65)

    try:
        ser = serial.Serial(port, baud, timeout=1)
    except Exception as e:
        print(f"[ERROR] Could not open {port}: {e}")
        sys.exit(1)

    print("[INFO] Listening for real-time telemetry from FPGA...\n")

    try:
        while True:
            raw_line = ser.readline().decode("ascii", errors="ignore").strip()
            if not raw_line or "[AUDIO]" not in raw_line:
                continue

            # Example: "[AUDIO] CLS=VOIC BIN=012 MAG=04820 [######..........]"
            print(f"\r{raw_line}", end="", flush=True)
    except KeyboardInterrupt:
        print("\n\n[INFO] Exiting visualizer.")
        ser.close()

if __name__ == "__main__":
    main()
