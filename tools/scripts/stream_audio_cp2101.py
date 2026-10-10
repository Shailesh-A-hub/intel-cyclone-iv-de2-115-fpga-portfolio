#!/usr/bin/env python3
"""
=============================================================================
DE2-115 Project 5: Audio Streamer to FPGA via CP2101 USB-to-UART Module
=============================================================================
Streams 8-bit PCM audio samples (or synthetic sine sweeps) over UART into the
DE2-115 FPGA via the CP2101 TX pin (connected to JP5 Pin 2).
Usage:
  python stream_audio_cp2101.py --tone 440       # Stream 440 Hz test tone
  python stream_audio_cp2101.py --tone 1000      # Stream 1 kHz test tone
  python stream_audio_cp2101.py --sweep          # Frequency sweep (100 Hz to 4 kHz)
"""

import sys
import time
import math
import argparse
import wave
import struct

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

def generate_tone_bytes(freq_hz, duration_sec, sample_rate=8000):
    total_samples = int(duration_sec * sample_rate)
    samples = bytearray(total_samples)
    for i in range(total_samples):
        t = float(i) / sample_rate
        # Generate 8-bit unsigned PCM (0 to 255, center 128)
        val = int(128.0 + 115.0 * math.sin(2.0 * math.pi * freq_hz * t))
        samples[i] = max(0, min(255, val))
    return samples

def stream_wav_file(filename, ser):
    try:
        wf = wave.open(filename, 'rb')
    except Exception as e:
        print(f"[ERROR] Could not open WAV file {filename}: {e}")
        return

    nchannels = wf.getnchannels()
    sampwidth = wf.getsampwidth()
    framerate = wf.getframerate()
    
    print(f"[INFO] Streaming WAV: {framerate}Hz, {nchannels} ch, {sampwidth*8}-bit")
    print("[INFO] Converting to 8-bit Mono stream for FPGA on the fly...")
    
    chunk_size = 128
    dt = float(chunk_size) / framerate
    
    try:
        while True:
            frames = wf.readframes(chunk_size)
            if not frames:
                break
                
            out_chunk = bytearray()
            
            # Convert format to 8-bit mono for UART
            if sampwidth == 1:
                for i in range(0, len(frames), nchannels):
                    out_chunk.append(frames[i])
            elif sampwidth == 2:
                for i in range(0, len(frames), 2 * nchannels):
                    val = struct.unpack('<h', frames[i:i+2])[0]
                    # Map signed 16-bit to unsigned 8-bit
                    val8 = int(((val + 32768) / 65535.0) * 255)
                    out_chunk.append(max(0, min(255, val8)))
            else:
                print(f"[ERROR] Unsupported sample width: {sampwidth*8} bits. Use 8 or 16-bit WAV.")
                return
                
            if len(out_chunk) > 0:
                ser.write(out_chunk)
                
            # Sleep to maintain realtime acoustic speed
            time.sleep(dt)
            
    except KeyboardInterrupt:
        print("\\n[INFO] Stopped WAV playback.")

def main():
    parser = argparse.ArgumentParser(description="Stream audio samples over CP2101 to DE2-115")
    parser.add_argument("--port", type=str, default=None, help="Serial COM port (e.g. COM4)")
    parser.add_argument("--baud", type=int, default=115200, help="UART Baud Rate (default 115200)")
    parser.add_argument("--tone", type=float, default=440.0, help="Sine frequency in Hz (default 440)")
    parser.add_argument("--duration", type=float, default=10.0, help="Duration in seconds (default 10)")
    parser.add_argument("--sweep", action="store_true", help="Perform a frequency sweep")
    parser.add_argument("--file", type=str, default=None, help="Path to a .wav audio file to play")
    args = parser.parse_args()

    port = args.port or find_cp210x_port()
    if not port:
        print("[ERROR] No serial ports found. Please connect your CP2101 USB-UART module.")
        sys.exit(1)

    print("=" * 65)
    print(" DE2-115 PROJECT 5: AUDIO STREAMER OVER CP2101 UART")
    print(f" Port: {port} | Baud: {args.baud}")
    print(" Important: Set SW[13]=1 on the DE2-115 board for UART Audio Mode!")
    print("=" * 65)

    try:
        ser = serial.Serial(port, args.baud, timeout=0.1)
    except Exception as e:
        print(f"[ERROR] Could not open {port}: {e}")
        sys.exit(1)

    sample_rate = 8000
    chunk_size = 64
    dt = float(chunk_size) / sample_rate

    try:
        if args.file:
            stream_wav_file(args.file, ser)
        elif args.sweep:
            print("[INFO] Streaming frequency sweep: 200 Hz -> 3000 Hz...")
            freq = 200.0
            phase = 0.0
            while True:
                chunk = bytearray(chunk_size)
                for i in range(chunk_size):
                    phase += 2.0 * math.pi * freq / sample_rate
                    val = int(128.0 + 115.0 * math.sin(phase))
                    chunk[i] = max(0, min(255, val))
                ser.write(chunk)
                freq += 15.0
                if freq > 3000.0:
                    freq = 200.0
                time.sleep(dt)
        else:
            print(f"[INFO] Streaming {args.tone:.1f} Hz sine wave...")
            audio_data = generate_tone_bytes(args.tone, args.duration, sample_rate)
            offset = 0
            while offset < len(audio_data):
                chunk = audio_data[offset:offset+chunk_size]
                ser.write(chunk)
                offset += chunk_size
                time.sleep(dt)
            print("[INFO] Done streaming tone.")
    except KeyboardInterrupt:
        print("\n[INFO] Stopped by user.")
    finally:
        ser.close()

if __name__ == "__main__":
    main()
