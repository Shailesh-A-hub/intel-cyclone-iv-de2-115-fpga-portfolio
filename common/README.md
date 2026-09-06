# DE2-115 Reusable Hardware Platform IP Layer

This directory contains the verified, parameterized, reusable IP platform layer shared across all five projects in the DE2-115 FPGA portfolio.

---

## Module Index

| Category | Module | Primary Purpose | Key Parameters |
|---|---|---|---|
| **Clock / Reset** | [`reset_synchronizer.v`](rtl/reset_synchronizer.v) | Metastability-free reset assert/de-assert | `STAGES`, `ACTIVE_LOW_IN`, `ACTIVE_LOW_OUT` |
| **Clock / Reset** | [`clock_divider.v`](rtl/clock_divider.v) | 50% duty clock & 1-cycle enable strobe | `DIVISOR` |
| **Human Input** | [`button_debounce.v`](rtl/button_debounce.v) | Glitch rejection filter & edge strobes | `CLK_FREQ_HZ`, `DEBOUNCE_MS`, `ACTIVE_LOW_IN` |
| **Human Input** | [`edge_detector.v`](rtl/edge_detector.v) | Multi-bit rising/falling/both edge pulses | `WIDTH` |
| **Display** | [`seven_seg_hex.v`](rtl/seven_seg_hex.v) | Hexadecimal active-low decoder (0-F) | N/A |
| **Display** | [`seven_seg_dec.v`](rtl/seven_seg_dec.v) | Decimal active-low decoder (0-9, dash) | N/A |
| **Display** | [`led_driver.v`](rtl/led_driver.v) | Multi-mode solid & multi-rate blink driver | `NUM_LEDS`, `CLK_FREQ_HZ` |
| **Display** | [`lcd_hd44780_controller.v`](rtl/lcd_hd44780_controller.v) | 16x2 HD44780 character LCD controller | `CLK_FREQ_HZ` |
| **Timing** | [`timer_ms.v`](rtl/timer_ms.v) | 1 ms periodic tick generator | `CLK_FREQ_HZ` |
| **Timing** | [`timer_sec.v`](rtl/timer_sec.v) | 1 second periodic tick generator | `CLK_FREQ_HZ` |
| **Timing** | [`periodic_timer.v`](rtl/periodic_timer.v) | Configurable periodic interval timer | `PERIOD`, `WIDTH` |
| **Timing** | [`timeout_timer.v`](rtl/timeout_timer.v) | Retriggerable countdown timeout counter | `WIDTH` |
| **Control** | [`pwm_generator.v`](rtl/pwm_generator.v) | Variable frequency & duty cycle PWM | `RESOLUTION_BITS` |
| **Communication** | [`uart_tx.v`](rtl/uart_tx.v) | UART transmitter with start/stop bits | `CLK_FREQ_HZ`, `BAUD_RATE`, `DATA_BITS` |
| **Communication** | [`uart_rx.v`](rtl/uart_rx.v) | 16x oversampling UART receiver | `CLK_FREQ_HZ`, `BAUD_RATE`, `DATA_BITS` |
| **Communication** | [`spi_master.v`](rtl/spi_master.v) | SPI Master supporting Modes 0, 1, 2, 3 | `DATA_WIDTH`, `CPOL`, `CPHA`, `CLK_DIV` |
| **Communication** | [`i2c_master.v`](rtl/i2c_master.v) | 100/400 kHz open-drain I2C Master core | `CLK_FREQ_HZ`, `I2C_FREQ_HZ` |
| **VGA** | [`vga_timing_controller.v`](rtl/vga_timing_controller.v) | 640x480 @ 60Hz video timing generator | N/A |
| **VGA** | [`vga_pattern_gen.v`](rtl/vga_pattern_gen.v) | Color bars, grid, border, gradient gen | N/A |
| **Audio** | [`i2s_receiver.v`](rtl/i2s_receiver.v) | Philips 16/24-bit stereo I2S receiver | `AUDIO_WIDTH` |
| **Audio** | [`wm8731_configurator.v`](rtl/wm8731_configurator.v) | Automated I2C WM8731 codec initializer | `CLK_FREQ_HZ`, `I2C_FREQ_HZ` |

---

## Design Standards & FPGA Methodology

1. **Synchronous Single-Domain Design**:
   All sequential logic operates on the 50 MHz global clock (`PIN_Y2`). Gated clocks are prohibited; timebases are delivered as single-cycle clock enable strobes.
2. **Synchronous Reset with Asynchronous Assert**:
   External reset inputs (`KEY[0]`) assert resets asynchronously to ensure immediate circuit shutdown, and are de-asserted through 2-stage synchronizers on the rising edge of `clk`.
3. **Open-Drain Bidirectional Tristates**:
   I2C buses (`scl`, `sda`) use active-low pull-down tristate drivers (`assign sda = sda_oen ? 1'bz : 1'b0;`) matching FPGA I/O ring architecture with external or internal weak pull-up resistors.
