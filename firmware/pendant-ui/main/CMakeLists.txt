file(GLOB SRCS "*.c" "fonts/*.c")
idf_component_register(SRCS ${SRCS}
                       INCLUDE_DIRS "."
                       REQUIRES lvgl esp_lcd_spd2010 esp_io_expander_tca9554 driver esp_lcd esp_timer esp_adc fatfs sdmmc vfs wear_levelling nvs_flash esp_driver_i2s bt esp-opus)
