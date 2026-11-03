// Mic -> 16 kHz 16-bit mono WAV, and WAV playback through the speaker.
// While recording, the same audio is also compressed with Opus into a twin .opus file,
// which is what the phone downloads (about 12x smaller, so sync is much faster).
// The mic task never touches storage: it pushes into a PSRAM ring buffer,
// and a separate writer task drains it, so slow SD/flash writes never drop audio.
#include "audio.h"
#include "board.h"
#include "storage.h"
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/stream_buffer.h"
#include "driver/i2s_std.h"
#include "opus.h"
#include "ble.h"

static const char *TAG = "audio";

#define MIC_GAIN_SHIFT  12            // lower = louder. 16 = no gain
#define FRAME_SAMPLES   320           // 20 ms
#define RING_BYTES      (128 * 1024)  // 4 s of audio
#define MIN_FREE_BYTES  (256 * 1024)
#define PLAY_VOLUME     1024           // 256 = 1x. Clipped, so >256 is safe

static i2s_chan_handle_t s_rx, s_tx;
static StreamBufferHandle_t s_ring;
static TaskHandle_t s_mic_task, s_writer_task, s_play_task;

static volatile bool s_rec, s_stop_req;
static volatile int s_level;
static int64_t s_rec_start_us;
static FILE *s_file;
static uint32_t s_data_bytes;
static char s_last[64];

/* Opus twin file. Format (all little endian):
 *   "PDO1"  u16 sample_rate  u16 frame_samples      then for each 20 ms frame:  u16 len  <len bytes>   */
#define OPUS_BITRATE    24000         // plenty for speech; ~3 KB/s instead of 32 KB/s
#define OPUS_COMPLEXITY 3             // 0..10. Keep low so encoding stays far ahead of the mic
static OpusEncoder *s_enc;
static FILE *s_opus;
static int16_t s_pend[FRAME_SAMPLES];
static int s_pend_n;
static uint32_t s_opus_bytes;

// Everything written to the .opus file also goes to the phone live (if it's connected)
static void opus_write(const void *data, size_t len)
{
    if (ble_live_join_pending()) {
        fflush(s_opus);
        fsync(fileno(s_opus));   // so the phone can read everything before this point
        ble_live_join(s_last, s_opus_bytes);
    }
    fwrite(data, 1, len, s_opus);
    s_opus_bytes += len;
    ble_live_data(data, len);
}

static void opus_frame(const int16_t *pcm)
{
    uint8_t pkt[2 + 400];
    int n = opus_encode(s_enc, pcm, FRAME_SAMPLES, pkt + 2, sizeof(pkt) - 2);
    if (n <= 0) return;
    pkt[0] = n & 0xFF;
    pkt[1] = n >> 8;
    opus_write(pkt, n + 2);
}

// Takes any number of samples; encodes every full 20 ms frame.
static void opus_feed(const int16_t *pcm, int count)
{
    if (!s_opus) return;
    while (count > 0) {
        int take = FRAME_SAMPLES - s_pend_n;
        if (take > count) take = count;
        memcpy(s_pend + s_pend_n, pcm, take * 2);
        s_pend_n += take;
        pcm += take;
        count -= take;
        if (s_pend_n == FRAME_SAMPLES) {
            opus_frame(s_pend);
            s_pend_n = 0;
        }
    }
}

static void opus_close(void)
{
    if (!s_opus) return;
    if (s_pend_n > 0) {   // pad the last frame with silence
        memset(s_pend + s_pend_n, 0, (FRAME_SAMPLES - s_pend_n) * 2);
        opus_frame(s_pend);
        s_pend_n = 0;
    }
    fclose(s_opus);
    s_opus = NULL;
    ble_live_end(s_opus_bytes);
}

static void opus_open(const char *wav_name)
{
    s_pend_n = 0;
    if (!s_enc) return;
    opus_encoder_ctl(s_enc, OPUS_RESET_STATE);
    char path[96];
    storage_opus_path(wav_name, path, sizeof(path));
    s_opus = fopen(path, "wb");
    if (!s_opus) return;
    setvbuf(s_opus, NULL, _IOFBF, 4096);
    uint8_t h[8] = {'P', 'D', 'O', '1', AUDIO_RATE & 0xFF, AUDIO_RATE >> 8, FRAME_SAMPLES & 0xFF, FRAME_SAMPLES >> 8};
    s_opus_bytes = 0;
    ble_live_start(wav_name);
    opus_write(h, sizeof(h));
}

static volatile bool s_play, s_play_stop;
static char s_play_name[40];

bool audio_recording(void) { return s_rec; }
int audio_level(void) { return s_level; }
const char *audio_last_file(void) { return s_last; }
bool audio_playing(void) { return s_play; }
const char *audio_playing_name(void) { return s_play_name; }

uint32_t audio_rec_ms(void)
{
    return s_rec ? (uint32_t)((esp_timer_get_time() - s_rec_start_us) / 1000) : 0;
}

/* ---------- WAV ---------- */
static void wav_header(uint8_t *h, uint32_t data_bytes)
{
    uint32_t rate = AUDIO_RATE, byte_rate = AUDIO_RATE * 2, riff = 36 + data_bytes;
    memcpy(h, "RIFF", 4); memcpy(h + 4, &riff, 4); memcpy(h + 8, "WAVEfmt ", 8);
    uint32_t fmt_len = 16; uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
    memcpy(h + 16, &fmt_len, 4); memcpy(h + 20, &pcm, 2); memcpy(h + 22, &ch, 2);
    memcpy(h + 24, &rate, 4); memcpy(h + 28, &byte_rate, 4); memcpy(h + 32, &align, 2);
    memcpy(h + 34, &bits, 2); memcpy(h + 36, "data", 4); memcpy(h + 40, &data_bytes, 4);
}

/* ---------- Recording ---------- */
static void mic_task(void *arg)
{
    int32_t *raw = heap_caps_malloc(FRAME_SAMPLES * 4, MALLOC_CAP_INTERNAL);
    int16_t pcm[FRAME_SAMPLES];
    int32_t x1 = 0, y1 = 0;
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);  // wait for start
        x1 = y1 = 0;
        i2s_channel_enable(s_rx);
        while (s_rec && !s_stop_req) {
            size_t got = 0;
            if (i2s_channel_read(s_rx, raw, FRAME_SAMPLES * 4, &got, 100) != ESP_OK) continue;
            int n = got / 4, peak = 0;
            for (int i = 0; i < n; i++) {
                int32_t x = raw[i] >> MIC_GAIN_SHIFT;
                int32_t y = x - x1 + ((y1 * 255) >> 8);  // remove DC offset
                x1 = x;
                y1 = y;
                if (y > 32767) y = 32767;
                if (y < -32768) y = -32768;
                pcm[i] = (int16_t)y;
                int a = y < 0 ? -y : y;
                if (a > peak) peak = a;
            }
            // Level for the UI: rough log scale, fast attack, slow release
            int lvl = 0;
            for (int p = peak; p > 64 && lvl < 100; p >>= 1) lvl += 11;
            s_level = lvl > s_level ? lvl : (s_level * 3 + lvl) / 4;
            if (s_file) xStreamBufferSend(s_ring, pcm, n * 2, 0);
        }
        i2s_channel_disable(s_rx);
        s_level = 0;
        xTaskNotifyGive(s_writer_task);  // tell writer the mic is done
    }
}

static void writer_task(void *arg)
{
    const size_t chunk = 16 * 1024;
    uint8_t *buf = heap_caps_malloc(chunk, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    while (1) {
        bool mic_done = ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(50)) > 0;
        if (!s_file) continue;
        size_t n;
        // Write in big chunks: far faster on SD/flash than many small writes
        while ((n = xStreamBufferReceive(s_ring, buf, chunk, 0)) > 0) {
            if (n < chunk && !mic_done && !s_stop_req) {
                // Not enough yet: put it back by waiting for a full chunk next round
                size_t more = xStreamBufferReceive(s_ring, buf + n, chunk - n, pdMS_TO_TICKS(400));
                n += more;
            }
            fwrite(buf, 1, n, s_file);
            s_data_bytes += n;
            opus_feed((const int16_t *)buf, n / 2);
        }
        // Stop when storage runs low
        static int check;
        if (++check % 40 == 0 && storage_free_bytes() < MIN_FREE_BYTES) s_stop_req = true;

        if (mic_done) {
            uint8_t h[44];
            wav_header(h, s_data_bytes);
            fseek(s_file, 0, SEEK_SET);
            fwrite(h, 1, 44, s_file);
            fclose(s_file);
            s_file = NULL;
            opus_close();
            ESP_LOGI(TAG, "saved %s (%lu bytes)", s_last, (unsigned long)s_data_bytes);
            s_rec = false;
        }
    }
}

bool audio_rec_start(void)
{
    if (s_rec) return true;
    if (s_play) audio_play_stop();
    if (!storage_ready() || storage_free_bytes() < MIN_FREE_BYTES) return false;

    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    snprintf(s_last, sizeof(s_last), "N%04d_%04d%02d%02d_%02d%02d%02d.wav", storage_next_index() % 10000,
             tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
    char path[96];
    snprintf(path, sizeof(path), NOTES_DIR "/%s", s_last);
    s_file = fopen(path, "wb");
    if (!s_file) return false;
    setvbuf(s_file, NULL, _IOFBF, 4096);
    uint8_t h[44];
    wav_header(h, 0);
    fwrite(h, 1, 44, s_file);
    opus_open(s_last);

    s_data_bytes = 0;
    xStreamBufferReset(s_ring);
    s_stop_req = false;
    s_rec_start_us = esp_timer_get_time();
    s_rec = true;
    xTaskNotifyGive(s_mic_task);
    return true;
}

void audio_rec_stop(void)
{
    if (s_rec) s_stop_req = true;
}

/* ---------- Playback ---------- */
static void play_task(void *arg)
{
    int16_t *buf = heap_caps_malloc(4096, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    char path[96];
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        snprintf(path, sizeof(path), NOTES_DIR "/%s", s_play_name);
        FILE *f = fopen(path, "rb");
        if (f) {
            fseek(f, 44, SEEK_SET);
            i2s_channel_enable(s_tx);
            size_t n;
            while (!s_play_stop && (n = fread(buf, 1, 4096, f)) > 0) {
                for (size_t i = 0; i < n / 2; i++) {
                    int32_t v = (buf[i] * PLAY_VOLUME) >> 8;
                    buf[i] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
                }
                size_t w;
                i2s_channel_write(s_tx, buf, n, &w, portMAX_DELAY);
            }
            memset(buf, 0, 4096);  // flush silence so the speaker doesn't pop
            size_t w;
            i2s_channel_write(s_tx, buf, 4096, &w, 100);
            i2s_channel_disable(s_tx);
            fclose(f);
        }
        s_play = false;
    }
}

bool audio_play(const char *name)
{
    if (s_rec) return false;
    if (s_play) audio_play_stop();
    strlcpy(s_play_name, name, sizeof(s_play_name));
    s_play_stop = false;
    s_play = true;
    xTaskNotifyGive(s_play_task);
    return true;
}

void audio_play_stop(void)
{
    if (!s_play) return;
    s_play_stop = true;
    for (int i = 0; i < 50 && s_play; i++) vTaskDelay(pdMS_TO_TICKS(10));
}

/* ---------- Init ---------- */
void audio_init(void)
{
    // Mic on I2S1
    i2s_chan_config_t rc = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
    rc.dma_desc_num = 6;
    rc.dma_frame_num = 320;
    ESP_ERROR_CHECK(i2s_new_channel(&rc, NULL, &s_rx));
    i2s_std_config_t rs = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {.mclk = I2S_GPIO_UNUSED, .bclk = MIC_PIN_SCK, .ws = MIC_PIN_WS,
                     .dout = I2S_GPIO_UNUSED, .din = MIC_PIN_DIN},
    };
    rs.slot_cfg.slot_mask = I2S_STD_SLOT_RIGHT;
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(s_rx, &rs));

    // Speaker on I2S0
    i2s_chan_config_t tc = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
    tc.auto_clear = true;
    ESP_ERROR_CHECK(i2s_new_channel(&tc, &s_tx, NULL));
    i2s_std_config_t ts = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {.mclk = I2S_GPIO_UNUSED, .bclk = SPK_PIN_BCK, .ws = SPK_PIN_WS,
                     .dout = SPK_PIN_DOUT, .din = I2S_GPIO_UNUSED},
    };
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(s_tx, &ts));

    uint8_t *ring_mem = heap_caps_malloc(RING_BYTES + 1, MALLOC_CAP_SPIRAM);
    static StaticStreamBuffer_t ring_struct;
    s_ring = xStreamBufferCreateStatic(RING_BYTES, 1, ring_mem, &ring_struct);

    xTaskCreatePinnedToCore(mic_task, "mic", 4096, NULL, 7, &s_mic_task, 0);
    int err = 0;
    s_enc = opus_encoder_create(AUDIO_RATE, 1, OPUS_APPLICATION_VOIP, &err);
    if (s_enc) {
        opus_encoder_ctl(s_enc, OPUS_SET_BITRATE(OPUS_BITRATE));
        opus_encoder_ctl(s_enc, OPUS_SET_COMPLEXITY(OPUS_COMPLEXITY));
        opus_encoder_ctl(s_enc, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    } else {
        ESP_LOGE(TAG, "opus init failed (%d), notes will sync as WAV", err);
    }

    // The writer also runs the Opus encoder, which needs a big stack
    xTaskCreatePinnedToCore(writer_task, "writer", 32 * 1024, NULL, 5, &s_writer_task, 0);
    xTaskCreatePinnedToCore(play_task, "play", 4096, NULL, 6, &s_play_task, 0);
}
