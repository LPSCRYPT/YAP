# Pendant UI firmware (v0.1)

For the Waveshare ESP32-S3-Touch-LCD-1.46. ESP-IDF 5.4 + LVGL 9. No network: recordings stay on the device.

## Flash on a Mac (first time ~15 min)

```sh
brew install cmake ninja dfu-util python3
git clone -b v5.4.2 --recursive https://github.com/espressif/esp-idf.git ~/esp/esp-idf
~/esp/esp-idf/install.sh esp32s3
```

Every time:

```sh
. ~/esp/esp-idf/export.sh
cd pendant-ui
idf.py build flash monitor     # Ctrl+] to quit monitor
```

If it can't find the port: `idf.py -p /dev/cu.usbmodem* flash`. If it still fails, hold BOOT, tap RESET, release BOOT, then flash again.

## How to use

- **Side button (PWR) or BOOT:** press to start recording, press again to stop. It reacts on press, so it feels instant.
- **Hold side button 3 s:** power off (on battery only).
- **Swipe left/right:** Home, Notes, Settings.
- **Notes:** tap a note to play it on the speaker, tap again to stop.
- A blue dot at the top breathes while recording. The screen dims after 15 s and turns off after 30 s, except while recording, when it stays dimmed so the blue dot is always visible.

## Where audio goes

- 16 kHz, 16-bit mono WAV files named `N0001_YYYYMMDD_HHMMSS.wav` in `/notes`.
- With a microSD card inserted (FAT32), files go to the card.
- Without a card, they go to a 12 MB area of the internal flash (about 6 minutes in total). Good enough to test now.

## Tuning

| What | Where |
|---|---|
| Mic loudness | `MIC_GAIN_SHIFT` in `main/audio.c` (lower = louder) |
| Screen dim/off times | `DIM_AFTER_MS`, `SLEEP_AFTER_MS` in `main/ui.c` |
| Colors | `C_*` defines at the top of `main/ui.c` |
| Screen shows noise or flickers | set `LCD_SPI_HZ` to 40 MHz in `main/board.h` |

The clock is set from the build time on first flash and kept by the board's RTC chip.

## Files

- `main/board.h` pins
- `main/display.c` screen, touch, LVGL
- `main/ui.c` all screens
- `main/audio.c` recording and playback
- `main/storage.c` SD card / internal flash
- `main/hw.c` battery, backlight, buttons, RTC
- `main/fonts/` Inter font (OFL), generated with lv_font_conv
