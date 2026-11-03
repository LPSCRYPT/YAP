#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "driver/i2c_master.h"

void hw_init(void);                      // power latch, I2C, IO expander, ADC, RTC -> system time
i2c_master_bus_handle_t hw_i2c_bus(void);

void hw_backlight_init(void);
void hw_backlight_set(int percent);      // 0..100, fades smoothly

bool hw_btn_pwr_down(void);
bool hw_btn_boot_down(void);
void hw_power_off(void);                 // releases power latch (works on battery only)

int  hw_battery_mv(void);                // smoothed battery voltage in mV
int  hw_battery_percent(void);           // 0..100, -1 if no battery detected

void hw_rtc_save(time_t t);              // write system time to RTC chip
