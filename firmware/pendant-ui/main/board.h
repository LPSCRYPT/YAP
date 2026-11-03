// Pin map for the Waveshare ESP32-S3-Touch-LCD-1.46.
// Taken from Waveshare's official demo and xiaozhi-esp32 (MIT).
#pragma once
#include "driver/gpio.h"

#define LCD_W 412
#define LCD_H 412

// QSPI display (SPD2010)
#define LCD_HOST        SPI2_HOST
#define LCD_PIN_CS      GPIO_NUM_21
#define LCD_PIN_SCK     GPIO_NUM_40
#define LCD_PIN_D0      GPIO_NUM_46
#define LCD_PIN_D1      GPIO_NUM_45
#define LCD_PIN_D2      GPIO_NUM_42
#define LCD_PIN_D3      GPIO_NUM_41
#define LCD_PIN_BL      GPIO_NUM_5
#define LCD_SPI_HZ      (80 * 1000 * 1000)  // Waveshare demo value. Drop to 40 MHz if the screen shows noise.

// Shared I2C bus: IO expander, touch, RTC, IMU
#define I2C_PIN_SDA     GPIO_NUM_11
#define I2C_PIN_SCL     GPIO_NUM_10
#define TOUCH_ADDR      0x53
#define TOUCH_PIN_INT   GPIO_NUM_4
#define RTC_ADDR        0x51
#define EXPANDER_ADDR   0x20    // TCA9554. EXIO1 = touch reset, EXIO2 = LCD reset

// Buttons and power latch
#define BTN_BOOT        GPIO_NUM_0  // active low
#define BTN_PWR         GPIO_NUM_6  // active low (side button)
#define PWR_LATCH       GPIO_NUM_7  // keep high to stay on when running on battery

// Battery: GPIO8 = ADC1 channel 7, 3:1 divider
#define BAT_ADC_CH      ADC_CHANNEL_7

// Microphone (I2S, right slot)
#define MIC_PIN_SCK     GPIO_NUM_15
#define MIC_PIN_WS      GPIO_NUM_2
#define MIC_PIN_DIN     GPIO_NUM_39

// Speaker DAC (PCM5101)
#define SPK_PIN_BCK     GPIO_NUM_48
#define SPK_PIN_WS      GPIO_NUM_38
#define SPK_PIN_DOUT    GPIO_NUM_47

// microSD (SDMMC 1-bit)
#define SD_PIN_CLK      GPIO_NUM_14
#define SD_PIN_CMD      GPIO_NUM_17
#define SD_PIN_D0       GPIO_NUM_16

#define AUDIO_RATE      16000
#define FW_VERSION      "0.1.0"
