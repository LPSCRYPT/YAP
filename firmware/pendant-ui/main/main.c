// AI Pendant firmware: UI + local recording. Notes leave the device only over Bluetooth to the paired phone app.
#include "audio.h"
#include "display.h"
#include "hw.h"
#include "storage.h"
#include "ui.h"
#include "ble.h"
#include "nvs_flash.h"
#include "esp_log.h"

void app_main(void)
{
    esp_err_t r = nvs_flash_init();
    if (r == ESP_ERR_NVS_NO_FREE_PAGES || r == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    hw_init();             // power latch first, then I2C, LCD/touch reset, RTC
    hw_backlight_init();   // starts dark; UI fades it in
    storage_init();        // SD card, or internal flash until the card arrives
    audio_init();
    display_start(ui_create);
    ble_start();           // phone app link
    ESP_LOGI("main", "ready");
}
