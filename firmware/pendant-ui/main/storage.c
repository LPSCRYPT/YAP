#include "storage.h"
#include "board.h"
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "esp_log.h"
#include "esp_vfs_fat.h"
#include "driver/sdmmc_host.h"
#include "sdmmc_cmd.h"
#include "ff.h"

static const char *TAG = "storage";
#define MOUNT "/data"

static bool s_ready, s_sd;
static wl_handle_t s_wl = WL_INVALID_HANDLE;

bool storage_ready(void) { return s_ready; }
bool storage_on_sd(void) { return s_sd; }

static bool mount_sd(void)
{
    sdmmc_host_t host = SDMMC_HOST_DEFAULT();
    host.max_freq_khz = SDMMC_FREQ_HIGHSPEED;
    sdmmc_slot_config_t slot = SDMMC_SLOT_CONFIG_DEFAULT();
    slot.width = 1;
    slot.clk = SD_PIN_CLK;
    slot.cmd = SD_PIN_CMD;
    slot.d0 = SD_PIN_D0;
    slot.d1 = slot.d2 = slot.d3 = GPIO_NUM_NC;
    slot.flags |= SDMMC_SLOT_FLAG_INTERNAL_PULLUP;
    esp_vfs_fat_sdmmc_mount_config_t mc = {.format_if_mount_failed = false, .max_files = 4,
                                          .allocation_unit_size = 32 * 1024};
    sdmmc_card_t *card;
    esp_err_t r = esp_vfs_fat_sdmmc_mount(MOUNT, &host, &slot, &mc, &card);
    if (r != ESP_OK) {
        ESP_LOGW(TAG, "no SD card (%s)", esp_err_to_name(r));
        return false;
    }
    return true;
}

static bool mount_flash(void)
{
    esp_vfs_fat_mount_config_t mc = {.format_if_mount_failed = true, .max_files = 4,
                                     .allocation_unit_size = 4096};
    esp_err_t r = esp_vfs_fat_spiflash_mount_rw_wl(MOUNT, "storage", &mc, &s_wl);
    if (r != ESP_OK) ESP_LOGE(TAG, "flash FAT mount failed (%s)", esp_err_to_name(r));
    return r == ESP_OK;
}

void storage_init(void)
{
    s_sd = mount_sd();
    s_ready = s_sd || mount_flash();
    if (s_ready) {
        mkdir(NOTES_DIR, 0775);
        ESP_LOGI(TAG, "storage on %s, %llu KB free", s_sd ? "SD" : "flash", storage_free_bytes() / 1024);
    }
}

static void fs_info(uint64_t *total, uint64_t *free_b)
{
    *total = *free_b = 0;
    FATFS *fs;
    DWORD free_clust;
    if (s_ready && f_getfree(s_sd ? "0:" : "0:", &free_clust, &fs) == FR_OK) {
        uint64_t csz = (uint64_t)fs->csize * fs->ssize;
        *total = (uint64_t)(fs->n_fatent - 2) * csz;
        *free_b = (uint64_t)free_clust * csz;
    }
}

uint64_t storage_free_bytes(void) { uint64_t t, f; fs_info(&t, &f); return f; }
uint64_t storage_total_bytes(void) { uint64_t t, f; fs_info(&t, &f); return t; }

// Names look like N0007_20261031_140210.wav
static bool parse_name(const char *n, int *idx, time_t *when)
{
    int i, Y, M, D, h, m, s;
    size_t len = strlen(n);
    if (len < 5 || strcmp(n + len - 4, ".wav") != 0) return false;   // skip the .opus twins
    if (sscanf(n, "N%4d_%4d%2d%2d_%2d%2d%2d.wav", &i, &Y, &M, &D, &h, &m, &s) != 7) return false;
    struct tm tm = {.tm_year = Y - 1900, .tm_mon = M - 1, .tm_mday = D, .tm_hour = h, .tm_min = m, .tm_sec = s};
    *idx = i;
    *when = mktime(&tm);
    return true;
}

static int cmp_newest(const void *a, const void *b)
{
    const note_info_t *x = a, *y = b;
    return strcmp(y->name, x->name);  // names sort by index
}

int storage_list(note_info_t *out, int max)
{
    if (!s_ready) return 0;
    DIR *d = opendir(NOTES_DIR);
    if (!d) return 0;
    int n = 0;
    struct dirent *e;
    char path[300];
    while ((e = readdir(d)) && n < max) {
        int idx;
        time_t when;
        if (!parse_name(e->d_name, &idx, &when)) continue;
        snprintf(path, sizeof(path), NOTES_DIR "/%s", e->d_name);
        struct stat st;
        if (stat(path, &st) != 0 || st.st_size <= 44) continue;
        strlcpy(out[n].name, e->d_name, sizeof(out[n].name));
        out[n].when = when;
        out[n].seconds = (st.st_size - 44) / (AUDIO_RATE * 2);
        n++;
    }
    closedir(d);
    qsort(out, n, sizeof(*out), cmp_newest);
    return n;
}

int storage_next_index(void)
{
    int best = 0;
    DIR *d = opendir(NOTES_DIR);
    if (!d) return 1;
    struct dirent *e;
    while ((e = readdir(d))) {
        int idx;
        time_t w;
        if (parse_name(e->d_name, &idx, &w) && idx > best) best = idx;
    }
    closedir(d);
    return best + 1;
}

void storage_opus_path(const char *wav_name, char *out, size_t out_len)
{
    size_t n = strlen(wav_name);
    if (n > 4 && strcmp(wav_name + n - 4, ".wav") == 0) n -= 4;
    snprintf(out, out_len, NOTES_DIR "/%.*s.opus", (int)n, wav_name);
}

bool storage_remove_note(const char *wav_name)
{
    char path[96];
    storage_opus_path(wav_name, path, sizeof(path));
    remove(path);   // may not exist (older notes)
    snprintf(path, sizeof(path), NOTES_DIR "/%.47s", wav_name);
    return remove(path) == 0;
}
