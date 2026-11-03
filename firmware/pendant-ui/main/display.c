// SPD2010 QSPI panel + SPD2010 touch + LVGL 9 port.
// Two DMA buffers in internal RAM; LVGL renders one while the other is sent.
#include "display.h"
#include "board.h"
#include "hw.h"
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "driver/spi_master.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_spd2010.h"

static const char *TAG = "display";

#define BUF_ROWS 24  // 412 x 24 x 2 B = 20 KB per buffer (Bluetooth needs internal RAM too)

static esp_lcd_panel_handle_t s_panel;
static lv_display_t *s_disp;
static SemaphoreHandle_t s_lock;
static i2c_master_dev_handle_t s_touch;
static void (*s_ui_create)(void);
static volatile bool s_asleep;
static void (*s_on_wake_touch)(void);

void display_lock(void) { xSemaphoreTakeRecursive(s_lock, portMAX_DELAY); }
void display_unlock(void) { xSemaphoreGiveRecursive(s_lock); }

void display_set_asleep(bool asleep, void (*on_wake_touch)(void))
{
    s_asleep = asleep;
    s_on_wake_touch = on_wake_touch;
}

/* ---------- Panel ---------- */
static bool IRAM_ATTR on_flush_done(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *e, void *ctx)
{
    lv_display_flush_ready((lv_display_t *)ctx);
    return false;
}

static void flush_cb(lv_display_t *disp, const lv_area_t *a, uint8_t *px)
{
    lv_draw_sw_rgb565_swap(px, lv_area_get_size(a));  // panel wants big-endian RGB565
    esp_lcd_panel_draw_bitmap(s_panel, a->x1, a->y1, a->x2 + 1, a->y2 + 1, px);
}

// SPD2010 needs x start/end aligned to 4 pixels
static void rounder_cb(lv_event_t *e)
{
    lv_area_t *a = lv_event_get_param(e);
    a->x1 = a->x1 & ~3;
    a->x2 = (a->x2 & ~3) + 3;
}

static void panel_init(void)
{
    spi_bus_config_t bus = {
        .sclk_io_num = LCD_PIN_SCK, .data0_io_num = LCD_PIN_D0, .data1_io_num = LCD_PIN_D1,
        .data2_io_num = LCD_PIN_D2, .data3_io_num = LCD_PIN_D3,
        .max_transfer_sz = LCD_W * BUF_ROWS * 2,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(LCD_HOST, &bus, SPI_DMA_CH_AUTO));

    esp_lcd_panel_io_handle_t io;
    esp_lcd_panel_io_spi_config_t io_cfg = {
        .cs_gpio_num = LCD_PIN_CS, .dc_gpio_num = -1, .spi_mode = 0, .pclk_hz = LCD_SPI_HZ,
        .trans_queue_depth = 10, .lcd_cmd_bits = 32, .lcd_param_bits = 8,
        .on_color_trans_done = on_flush_done, .user_ctx = s_disp,
        .flags.quad_mode = true,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_cfg, &io));

    spd2010_vendor_config_t vendor = {.flags.use_qspi_interface = 1};
    esp_lcd_panel_dev_config_t pcfg = {
        .reset_gpio_num = -1, .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16, .vendor_config = &vendor,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_spd2010(io, &pcfg, &s_panel));
    esp_lcd_panel_reset(s_panel);
    esp_lcd_panel_init(s_panel);
    esp_lcd_panel_disp_on_off(s_panel, true);
}

/* ---------- Touch (SPD2010 touch protocol, ported from Waveshare demo) ---------- */
static esp_err_t tp_write(uint16_t reg, uint8_t d0, uint8_t d1)
{
    uint8_t b[4] = {reg >> 8, reg & 0xFF, d0, d1};
    esp_err_t r = i2c_master_transmit(s_touch, b, 4, 20);
    esp_rom_delay_us(200);
    return r;
}

static esp_err_t tp_read(uint16_t reg, uint8_t *buf, size_t len)
{
    uint8_t r[2] = {reg >> 8, reg & 0xFF};
    return i2c_master_transmit_receive(s_touch, r, 2, buf, len, 20);
}

// Returns true while a finger is down
static bool tp_get(int *x, int *y)
{
    static bool down;
    static int lx, ly;
    static int64_t last_pkt;
    uint8_t st[4];
    *x = lx;
    *y = ly;
    if (tp_read(0x2000, st, 4) != ESP_OK) return down;
    bool pt_exist = st[0] & 0x01, gesture = st[0] & 0x02, aux = st[0] & 0x08;
    bool in_bios = st[1] & 0x40, in_cpu = st[1] & 0x20, cpu_run = st[1] & 0x08;
    uint16_t len = st[3] << 8 | st[2];

    if (in_bios) {
        tp_write(0x0200, 0x01, 0x00);  // clear int
        tp_write(0x0400, 0x01, 0x00);  // cpu start
    } else if (in_cpu) {
        tp_write(0x5000, 0x00, 0x00);  // point mode
        tp_write(0x4600, 0x00, 0x00);  // start
        tp_write(0x0200, 0x01, 0x00);
    } else if (cpu_run && len == 0) {
        tp_write(0x0200, 0x01, 0x00);
    } else if (pt_exist || gesture) {
        uint8_t d[64];
        if (len > sizeof(d)) len = sizeof(d);
        if (len >= 4 && tp_read(0x0003, d, len) == ESP_OK) {
            if (d[4] <= 0x0A && pt_exist && len >= 10) {
                lx = ((d[7] & 0xF0) << 4) | d[5];
                ly = ((d[7] & 0x0F) << 8) | d[6];
                down = d[8] != 0;  // weight 0 = finger lifted
                last_pkt = esp_timer_get_time();
            } else {
                down = false;
            }
        }
        for (int i = 0; i < 4; i++) {  // drain HDP
            uint8_t hs[8];
            if (tp_read(0xFC02, hs, 8) != ESP_OK) break;
            if (hs[5] == 0x82) { tp_write(0x0200, 0x01, 0x00); break; }
            if (hs[5] != 0x00) break;
            uint16_t n = hs[2] | hs[3] << 8;
            uint8_t junk[32];
            tp_read(0x0003, junk, n > 32 ? 32 : n);
        }
    } else if (cpu_run && aux) {
        tp_write(0x0200, 0x01, 0x00);
    }
    // No new report for a while: treat as lifted
    if (down && esp_timer_get_time() - last_pkt > 90000) down = false;
    *x = lx;
    *y = ly;
    return down;
}

static void touch_read_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    static bool swallow;
    int x = 0, y = 0;
    bool down = tp_get(&x, &y);
    if (down && s_asleep) {
        swallow = true;
        if (s_on_wake_touch) s_on_wake_touch();
    }
    if (!down) swallow = false;
    if (x >= LCD_W) x = LCD_W - 1;
    if (y >= LCD_H) y = LCD_H - 1;
    data->point.x = x;
    data->point.y = y;
    data->state = (down && !swallow) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}

static void touch_init(void)
{
    i2c_device_config_t cfg = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = TOUCH_ADDR,
                               .scl_speed_hz = 400000};
    ESP_ERROR_CHECK(i2c_master_bus_add_device(hw_i2c_bus(), &cfg, &s_touch));
    gpio_config_t g = {.pin_bit_mask = 1ULL << TOUCH_PIN_INT, .mode = GPIO_MODE_INPUT,
                       .pull_up_en = GPIO_PULLUP_ENABLE};
    gpio_config(&g);
}

/* ---------- LVGL ---------- */
static uint32_t tick_cb(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static void lvgl_task(void *arg)
{
    display_lock();
    s_ui_create();
    display_unlock();
    while (1) {
        display_lock();
        uint32_t wait = lv_timer_handler();
        display_unlock();
        if (wait < 2) wait = 2;
        if (wait > 20) wait = 20;
        vTaskDelay(pdMS_TO_TICKS(wait));
    }
}

void display_start(void (*ui_create)(void))
{
    s_ui_create = ui_create;
    s_lock = xSemaphoreCreateRecursiveMutex();

    lv_init();
    lv_tick_set_cb(tick_cb);
    s_disp = lv_display_create(LCD_W, LCD_H);

    panel_init();
    touch_init();

    size_t sz = LCD_W * BUF_ROWS * 2;
    void *b1 = heap_caps_malloc(sz, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    void *b2 = heap_caps_malloc(sz, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    assert(b1 && b2);
    lv_display_set_color_format(s_disp, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(s_disp, b1, b2, sz, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(s_disp, flush_cb);
    lv_display_add_event_cb(s_disp, rounder_cb, LV_EVENT_INVALIDATE_AREA, NULL);

    lv_indev_t *tp = lv_indev_create();
    lv_indev_set_type(tp, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(tp, touch_read_cb);
    lv_indev_set_display(tp, s_disp);

    // UI on core 1; audio and storage live on core 0
    xTaskCreatePinnedToCore(lvgl_task, "lvgl", 8192, NULL, 4, NULL, 1);
    ESP_LOGI(TAG, "display up");
}
