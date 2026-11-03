#include "hw.h"
#include "board.h"
#include <string.h>
#include <sys/time.h>
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_io_expander_tca9554.h"

static const char *TAG = "hw";
static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_rtc;
static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static int s_bat_mv_filt;

i2c_master_bus_handle_t hw_i2c_bus(void) { return s_bus; }

/* ---------- RTC (PCF85063) ---------- */
static uint8_t bcd2dec(uint8_t v) { return (v >> 4) * 10 + (v & 0x0F); }
static uint8_t dec2bcd(uint8_t v) { return ((v / 10) << 4) | (v % 10); }

static bool rtc_read(struct tm *tm)
{
    uint8_t reg = 0x04, d[7];
    if (i2c_master_transmit_receive(s_rtc, &reg, 1, d, 7, 50) != ESP_OK) return false;
    if (d[0] & 0x80) return false;  // oscillator stopped: time not valid
    memset(tm, 0, sizeof(*tm));
    tm->tm_sec  = bcd2dec(d[0] & 0x7F);
    tm->tm_min  = bcd2dec(d[1] & 0x7F);
    tm->tm_hour = bcd2dec(d[2] & 0x3F);
    tm->tm_mday = bcd2dec(d[3] & 0x3F);
    tm->tm_mon  = bcd2dec(d[5] & 0x1F) - 1;
    tm->tm_year = bcd2dec(d[6]) + 100;  // 20xx
    return true;
}

void hw_rtc_save(time_t t)
{
    struct tm tm;
    localtime_r(&t, &tm);
    uint8_t d[8] = {0x04, dec2bcd(tm.tm_sec), dec2bcd(tm.tm_min), dec2bcd(tm.tm_hour),
                    dec2bcd(tm.tm_mday), (uint8_t)tm.tm_wday, dec2bcd(tm.tm_mon + 1),
                    dec2bcd(tm.tm_year % 100)};
    i2c_master_transmit(s_rtc, d, sizeof(d), 50);
}

// Build time, so a freshly flashed board shows roughly the right time.
static time_t build_time(void)
{
    static const char *mons = "JanFebMarAprMayJunJulAugSepOctNovDec";
    char m[4] = {0};
    int d, y, hh, mm, ss;
    sscanf(__DATE__, "%3s %d %d", m, &d, &y);
    sscanf(__TIME__, "%d:%d:%d", &hh, &mm, &ss);
    struct tm tm = {.tm_year = y - 1900, .tm_mon = (int)((strstr(mons, m) - mons) / 3),
                    .tm_mday = d, .tm_hour = hh, .tm_min = mm, .tm_sec = ss};
    return mktime(&tm);
}

static void rtc_init(void)
{
    i2c_device_config_t cfg = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = RTC_ADDR,
                               .scl_speed_hz = 400000};
    i2c_master_bus_add_device(s_bus, &cfg, &s_rtc);

    struct tm tm;
    time_t now = 0, built = build_time();
    if (rtc_read(&tm)) now = mktime(&tm);
    if (now < built) {  // RTC empty or older than this firmware: use build time
        now = built;
        hw_rtc_save(now);
        ESP_LOGI(TAG, "RTC set from build time");
    }
    struct timeval tv = {.tv_sec = now};
    settimeofday(&tv, NULL);
}

/* ---------- Backlight ---------- */
void hw_backlight_init(void)
{
    ledc_timer_config_t t = {.speed_mode = LEDC_LOW_SPEED_MODE, .duty_resolution = LEDC_TIMER_10_BIT,
                             .timer_num = LEDC_TIMER_0, .freq_hz = 20000, .clk_cfg = LEDC_AUTO_CLK};
    ledc_timer_config(&t);
    ledc_channel_config_t c = {.gpio_num = LCD_PIN_BL, .speed_mode = LEDC_LOW_SPEED_MODE,
                               .channel = LEDC_CHANNEL_0, .timer_sel = LEDC_TIMER_0, .duty = 0};
    ledc_channel_config(&c);
    ledc_fade_func_install(0);
}

void hw_backlight_set(int percent)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    // Perceptual curve: low values stay usable
    uint32_t duty = (uint32_t)(percent * percent * 1023 / 10000);
    if (percent > 0 && duty < 4) duty = 4;
    ledc_set_fade_time_and_start(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, duty, 220, LEDC_FADE_NO_WAIT);
}

/* ---------- Buttons / power ---------- */
bool hw_btn_pwr_down(void) { return gpio_get_level(BTN_PWR) == 0; }
bool hw_btn_boot_down(void) { return gpio_get_level(BTN_BOOT) == 0; }

void hw_power_off(void)
{
    hw_backlight_set(0);
    vTaskDelay(pdMS_TO_TICKS(250));
    gpio_set_level(PWR_LATCH, 0);
}

/* ---------- Battery ---------- */
static int battery_read_mv(void)
{
    int raw = 0, mv = 0;
    if (adc_oneshot_read(s_adc, BAT_ADC_CH, &raw) != ESP_OK) return 0;
    if (s_cali) adc_cali_raw_to_voltage(s_cali, raw, &mv);
    else mv = raw * 3100 / 4095;
    return (int)(mv * 3 / 0.990476f);  // 3:1 divider + Waveshare calibration
}

int hw_battery_mv(void)
{
    int mv = battery_read_mv();
    if (s_bat_mv_filt == 0) s_bat_mv_filt = mv;
    s_bat_mv_filt = (s_bat_mv_filt * 7 + mv) / 8;
    return s_bat_mv_filt;
}

int hw_battery_percent(void)
{
    static const int curve[][2] = {{4180, 100}, {4100, 92}, {4000, 82}, {3900, 70}, {3800, 55},
                                   {3750, 45}, {3700, 33}, {3650, 22}, {3600, 14}, {3500, 6}, {3300, 0}};
    int mv = s_bat_mv_filt ? s_bat_mv_filt : hw_battery_mv();
    if (mv < 2500) return -1;  // no battery connected
    if (mv >= curve[0][0]) return 100;
    for (int i = 1; i < 11; i++) {
        if (mv >= curve[i][0]) {
            int dv = curve[i - 1][0] - curve[i][0], dp = curve[i - 1][1] - curve[i][1];
            return curve[i][1] + (mv - curve[i][0]) * dp / dv;
        }
    }
    return 0;
}

static void adc_init(void)
{
    adc_oneshot_unit_init_cfg_t u = {.unit_id = ADC_UNIT_1};
    adc_oneshot_new_unit(&u, &s_adc);
    adc_oneshot_chan_cfg_t c = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    adc_oneshot_config_channel(s_adc, BAT_ADC_CH, &c);
    adc_cali_curve_fitting_config_t cc = {.unit_id = ADC_UNIT_1, .chan = BAT_ADC_CH,
                                          .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    if (adc_cali_create_scheme_curve_fitting(&cc, &s_cali) != ESP_OK) s_cali = NULL;
    for (int i = 0; i < 8; i++) hw_battery_mv();
}

/* ---------- Init ---------- */
void hw_init(void)
{
    // Hold power on first, so releasing the button doesn't cut power on battery
    gpio_config_t out = {.pin_bit_mask = 1ULL << PWR_LATCH, .mode = GPIO_MODE_OUTPUT};
    gpio_config(&out);
    gpio_set_level(PWR_LATCH, 1);

    gpio_config_t in = {.pin_bit_mask = (1ULL << BTN_PWR) | (1ULL << BTN_BOOT), .mode = GPIO_MODE_INPUT,
                        .pull_up_en = GPIO_PULLUP_ENABLE};
    gpio_config(&in);

    i2c_master_bus_config_t bc = {.i2c_port = I2C_NUM_0, .sda_io_num = I2C_PIN_SDA, .scl_io_num = I2C_PIN_SCL,
                                  .clk_source = I2C_CLK_SRC_DEFAULT, .glitch_ignore_cnt = 7,
                                  .flags.enable_internal_pullup = true};
    ESP_ERROR_CHECK(i2c_new_master_bus(&bc, &s_bus));

    // Reset LCD and touch through the IO expander. Other pins stay high (SD D3 etc).
    esp_io_expander_handle_t io = NULL;
    if (esp_io_expander_new_i2c_tca9554(s_bus, EXPANDER_ADDR, &io) == ESP_OK) {
        uint32_t rst = IO_EXPANDER_PIN_NUM_0 | IO_EXPANDER_PIN_NUM_1;
        esp_io_expander_set_dir(io, 0xFF, IO_EXPANDER_OUTPUT);   // same as Waveshare demo: all outputs, high
        esp_io_expander_set_level(io, 0xFF, 1);
        esp_io_expander_set_level(io, rst, 0);
        vTaskDelay(pdMS_TO_TICKS(20));
        esp_io_expander_set_level(io, rst, 1);
        vTaskDelay(pdMS_TO_TICKS(120));
    } else {
        ESP_LOGE(TAG, "IO expander not found");
    }

    adc_init();
    rtc_init();
}
