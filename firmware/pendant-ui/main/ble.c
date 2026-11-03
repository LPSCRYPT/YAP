// Bluetooth LE link to the phone app: list, download and delete notes, set the clock.
//
// One service, two characteristics:
//   CTRL (write)  ASCII commands from the phone:
//       "L"          list notes
//       "G:<name>"   send one note: the small .opus twin if there is one, else the WAV
//       "W:<name>"   send the WAV, always
//       "D:<name>"   delete one note
//       "T:<secs>"   set clock (phone sends local time as seconds since 1970)
//       "R:1" / "R:0" start / stop recording (the app's live button)
//       "O:<name>:<from>:<to>"  bytes from..to of a note's .opus file, even while it's recording
//                    (reply: 'P' size, 'C' chunks, 'F'), used to catch up after being out of range
//   DATA (notify) replies. First byte says what it is:
//       'L' + "name|bytes|seconds"   one note (list)
//       'E'                          end of list
//       'H' + u32 size (LE)          WAV file starts
//       'P' + u32 size (LE)          Opus file starts (format in audio.c)
//       'C' + bytes                  file chunk
//       'F'                          file done
//       'K'                          command ok
//       'X' + text                   error
//
// LIVE (notify), used while recording so nothing is left to download afterwards:
//       'S' + name                   live note starts
//       'A' + bytes                  next bytes of its .opus file
//       'Z' + u32 size (LE)          note done; size of the whole .opus file (0 = gave up)
//       'J' + u32 offset + name      phone (re)connected while recording: live bytes continue from
//                                    this offset of the .opus file. The phone fetches what it missed
//                                    with "O:<name>:<from>:<to>" (works while recording).
//   If the phone misses anything (size mismatch), it just downloads the note later with "G:".
//
// Speed: on connect we ask the phone for 2M PHY, 251-byte link packets and a 15 ms
// connection interval. Together with Opus this makes a 1 minute note take about a second.
#include "ble.h"
#include "audio.h"
#include "hw.h"
#include "storage.h"
#include "ui.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/message_buffer.h"
#include "esp_heap_caps.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "ble";

// Custom 128-bit UUIDs (bytes below are little endian)
// Service  : 9F2A0001-5C2B-4F3B-9C1E-7A1D5E0B1A01
// CTRL     : 9F2A0002-5C2B-4F3B-9C1E-7A1D5E0B1A01
// DATA     : 9F2A0003-5C2B-4F3B-9C1E-7A1D5E0B1A01
// LIVE     : 9F2A0004-5C2B-4F3B-9C1E-7A1D5E0B1A01
#define UUID_BYTES(x) 0x01, 0x1A, 0x0B, 0x5E, 0x1D, 0x7A, 0x1E, 0x9C, 0x3B, 0x4F, 0x2B, 0x5C, x, 0x00, 0x2A, 0x9F
static const ble_uuid128_t svc_uuid = BLE_UUID128_INIT(UUID_BYTES(0x01));
static const ble_uuid128_t ctrl_uuid = BLE_UUID128_INIT(UUID_BYTES(0x02));
static const ble_uuid128_t data_uuid = BLE_UUID128_INIT(UUID_BYTES(0x03));
static const ble_uuid128_t live_uuid = BLE_UUID128_INIT(UUID_BYTES(0x04));

static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_data_handle, s_live_handle;
static uint8_t s_own_addr_type;
static QueueHandle_t s_cmds;

typedef struct { char text[64]; } cmd_t;

static void advertise(void);

bool ble_connected(void) { return s_conn != BLE_HS_CONN_HANDLE_NONE; }

/* ---------- sending ---------- */
static int payload_max(void)
{
    uint16_t mtu = ble_att_mtu(s_conn);
    if (mtu < 23) mtu = 23;
    return mtu - 3;   // ATT notify header
}

// Sends one notification, waiting while the Bluetooth buffers are full.
static bool send_on(uint16_t handle, const void *data, size_t len)
{
    for (int tries = 0; tries < 500; tries++) {
        if (!ble_connected()) return false;
        struct os_mbuf *om = ble_hs_mbuf_from_flat(data, len);
        if (om) {
            int rc = ble_gatts_notify_custom(s_conn, handle, om);   // consumes om
            if (rc == 0) return true;
            if (rc != BLE_HS_ENOMEM && rc != BLE_HS_EBUSY) return false;
        }
        vTaskDelay(pdMS_TO_TICKS(4));
    }
    return false;
}

static bool send(const void *data, size_t len) { return send_on(s_data_handle, data, len); }

static void send_tag(char tag, const char *text)
{
    char b[96];
    b[0] = tag;
    size_t n = text ? strlcpy(b + 1, text, sizeof(b) - 1) : 0;
    if (n > sizeof(b) - 2) n = sizeof(b) - 2;
    send(b, n + 1);
}

/* ---------- commands ---------- */
static bool safe_name(const char *n)
{
    return n[0] && !strchr(n, '/') && !strstr(n, "..") && strlen(n) < 40;
}

static void cmd_list(void)
{
    static note_info_t notes[MAX_NOTES];
    int n = storage_list(notes, MAX_NOTES);
    const char *busy = audio_recording() ? audio_last_file() : "";
    for (int i = 0; i < n; i++) {
        if (strcmp(notes[i].name, busy) == 0) continue;   // still being written
        char path[96], line[80];
        struct stat st;
        snprintf(path, sizeof(path), NOTES_DIR "/%.39s", notes[i].name);
        if (stat(path, &st) != 0) continue;
        struct stat ost;   // report the size the phone will actually download
        storage_opus_path(notes[i].name, path, sizeof(path));
        if (stat(path, &ost) == 0 && ost.st_size > 8) st.st_size = ost.st_size;
        snprintf(line, sizeof(line), "%.39s|%ld|%lu", notes[i].name, (long)st.st_size,
                 (unsigned long)notes[i].seconds);
        send_tag('L', line);
    }
    send_tag('E', NULL);
}

static void cmd_get(const char *name, bool want_opus)
{
    if (!safe_name(name)) { send_tag('X', "bad name"); return; }
    if (audio_recording() && strcmp(name, audio_last_file()) == 0) { send_tag('X', "recording"); return; }
    char path[96];
    FILE *f = NULL;
    char kind = 'H';
    if (want_opus) {
        storage_opus_path(name, path, sizeof(path));
        f = fopen(path, "rb");
        if (f) kind = 'P';
    }
    if (!f) {
        snprintf(path, sizeof(path), NOTES_DIR "/%.47s", name);
        f = fopen(path, "rb");
    }
    if (!f) { send_tag('X', "not found"); return; }
    setvbuf(f, NULL, _IOFBF, 8192);   // fewer, bigger storage reads
    fseek(f, 0, SEEK_END);
    uint32_t size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t h[5] = {kind, size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, size >> 24};
    send(h, sizeof(h));

    int chunk = payload_max() - 1;
    if (chunk > 500) chunk = 500;
    uint8_t buf[512];
    buf[0] = 'C';
    int64_t t0 = esp_timer_get_time();
    size_t n, total = 0;
    while ((n = fread(buf + 1, 1, chunk, f)) > 0) {
        if (!send(buf, n + 1)) { fclose(f); ESP_LOGW(TAG, "send stopped at %u", (unsigned)total); return; }
        total += n;
    }
    fclose(f);
    send_tag('F', NULL);
    int ms = (int)((esp_timer_get_time() - t0) / 1000);
    ESP_LOGI(TAG, "sent %s (%s): %u bytes in %d ms (%d KB/s)", name, kind == 'P' ? "opus" : "wav", (unsigned)total, ms,
             ms ? (int)(total / ms) : 0);
}

// Part of a note's .opus file. Allowed while recording: the writer flushed everything
// before the join offset to storage when the phone joined.
static void cmd_range(char *args)
{
    char *a = strchr(args, ':');
    char *b = a ? strchr(a + 1, ':') : NULL;
    if (!a || !b) { send_tag('X', "bad range"); return; }
    *a = 0; *b = 0;
    const char *name = args;
    long from = atol(a + 1), to = atol(b + 1);
    if (!safe_name(name) || from < 0 || to < from) { send_tag('X', "bad range"); return; }
    char path[96];
    storage_opus_path(name, path, sizeof(path));
    FILE *f = fopen(path, "rb");
    if (!f) { send_tag('X', "not found"); return; }
    setvbuf(f, NULL, _IOFBF, 8192);
    if (fseek(f, from, SEEK_SET) != 0) { fclose(f); send_tag('X', "seek"); return; }
    uint32_t size = (uint32_t)(to - from);
    uint8_t h[5] = {'P', size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, size >> 24};
    send(h, sizeof(h));
    int chunk = payload_max() - 1;
    if (chunk > 500) chunk = 500;
    uint8_t buf[512];
    buf[0] = 'C';
    uint32_t left = size;
    while (left > 0) {
        size_t want = left < (uint32_t)chunk ? left : (size_t)chunk;
        size_t n = fread(buf + 1, 1, want, f);
        if (n == 0) break;
        if (!send(buf, n + 1)) { fclose(f); return; }
        left -= n;
    }
    fclose(f);
    send_tag('F', NULL);
    ESP_LOGI(TAG, "sent %s range %ld-%ld (%u missing)", name, from, to, (unsigned)left);
}

static void cmd_delete(const char *name)
{
    if (!safe_name(name)) { send_tag('X', "bad name"); return; }
    if (audio_recording() && strcmp(name, audio_last_file()) == 0) { send_tag('X', "recording"); return; }
    if (audio_playing() && strcmp(name, audio_playing_name()) == 0) audio_play_stop();
    if (storage_remove_note(name)) {
        ui_notes_changed();
        send_tag('K', NULL);
    } else {
        send_tag('X', "delete failed");
    }
}

static void cmd_time(const char *secs)
{
    long long t = atoll(secs);
    if (t < 1700000000LL) { send_tag('X', "bad time"); return; }
    struct timeval tv = {.tv_sec = (time_t)t};
    settimeofday(&tv, NULL);
    hw_rtc_save((time_t)t);
    send_tag('K', NULL);
}

static void worker_task(void *arg)
{
    cmd_t c;
    while (1) {
        if (xQueueReceive(s_cmds, &c, portMAX_DELAY) != pdTRUE) continue;
        ESP_LOGI(TAG, "cmd %s", c.text);
        if (c.text[0] == 'L') cmd_list();
        else if (!strncmp(c.text, "G:", 2)) cmd_get(c.text + 2, true);
        else if (!strncmp(c.text, "W:", 2)) cmd_get(c.text + 2, false);
        else if (!strncmp(c.text, "D:", 2)) cmd_delete(c.text + 2);
        else if (!strncmp(c.text, "T:", 2)) cmd_time(c.text + 2);
        else if (!strncmp(c.text, "O:", 2)) cmd_range(c.text + 2);
        else if (!strncmp(c.text, "R:", 2)) { ui_request_record(c.text[2] == '1'); send_tag('K', NULL); }
        else send_tag('X', "unknown");
    }
}

/* ---------- live sync ---------- */
// The audio writer hands us ready-made messages; a separate task sends them, so a slow
// radio never holds up recording. If the queue overflows, this note is dropped from live
// sync (the phone downloads it normally later).
#define LIVE_CHUNK   480
#define LIVE_QUEUE   (48 * 1024)   // ~2 minutes of Opus at 24 kbps
static MessageBufferHandle_t s_live_q;
static uint8_t s_live_buf[1 + LIVE_CHUNK];
static size_t s_live_n;
static bool s_live_on, s_live_broken;
static volatile bool s_join_req;   // phone subscribed while recording: join at the next write

static void live_put(const void *msg, size_t len)
{
    if (s_live_broken) return;
    if (xMessageBufferSend(s_live_q, msg, len, 0) != len) s_live_broken = true;
}

static void live_flush(void)
{
    if (s_live_n == 0) return;
    s_live_buf[0] = 'A';
    live_put(s_live_buf, s_live_n + 1);
    s_live_n = 0;
}

void ble_live_start(const char *wav_name)
{
    s_live_on = ble_connected() && s_live_q;
    s_live_broken = false;
    s_live_n = 0;
    if (!s_live_on) return;
    char m[48];
    m[0] = 'S';
    size_t n = strlcpy(m + 1, wav_name, sizeof(m) - 1);
    live_put(m, 1 + (n < sizeof(m) - 1 ? n : sizeof(m) - 2));
}

void ble_live_data(const void *data, size_t len)
{
    if (!s_live_on) return;
    const uint8_t *p = data;
    while (len > 0) {
        size_t take = LIVE_CHUNK - s_live_n;
        if (take > len) take = len;
        memcpy(s_live_buf + 1 + s_live_n, p, take);
        s_live_n += take;
        p += take;
        len -= take;
        if (s_live_n == LIVE_CHUNK) live_flush();
    }
}

bool ble_live_join_pending(void) { return s_join_req && s_live_q && ble_connected(); }

void ble_live_join(const char *wav_name, uint32_t offset)
{
    s_join_req = false;
    s_live_on = true;
    s_live_broken = false;
    s_live_n = 0;
    uint8_t m[56];
    m[0] = 'J';
    m[1] = offset & 0xFF; m[2] = (offset >> 8) & 0xFF; m[3] = (offset >> 16) & 0xFF; m[4] = offset >> 24;
    size_t n = strlcpy((char *)m + 5, wav_name, sizeof(m) - 5);
    if (n > sizeof(m) - 6) n = sizeof(m) - 6;
    live_put(m, 5 + n);
}

void ble_live_end(uint32_t total)
{
    if (!s_live_on) return;
    live_flush();
    if (s_live_broken) total = 0;   // tells the phone to download this note normally
    uint8_t m[5] = {'Z', total & 0xFF, (total >> 8) & 0xFF, (total >> 16) & 0xFF, total >> 24};
    // Wait a little for room: the end marker matters, or the phone keeps a half note open
    xMessageBufferSend(s_live_q, m, sizeof(m), pdMS_TO_TICKS(500));
    s_live_on = false;
}

static void live_task(void *arg)
{
    static uint8_t msg[1 + LIVE_CHUNK];
    while (1) {
        size_t n = xMessageBufferReceive(s_live_q, msg, sizeof(msg), portMAX_DELAY);
        if (n == 0 || !ble_connected()) continue;   // phone gone: drop; it will download later
        // Keep each notification within the link's packet size
        size_t max = payload_max();
        if (n <= max) { send_on(s_live_handle, msg, n); continue; }
        uint8_t part[1 + LIVE_CHUNK];
        part[0] = msg[0];
        for (size_t off = 1; off < n; off += max - 1) {
            size_t k = n - off < max - 1 ? n - off : max - 1;
            memcpy(part + 1, msg + off, k);
            send_on(s_live_handle, part, k + 1);
        }
    }
}

/* ---------- GATT ---------- */
static int ctrl_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    cmd_t c = {0};
    uint16_t len = 0;
    if (ble_hs_mbuf_to_flat(ctxt->om, c.text, sizeof(c.text) - 1, &len) != 0) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    c.text[len] = 0;
    xQueueSend(s_cmds, &c, 0);
    return 0;
}

static int data_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static const struct ble_gatt_svc_def s_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]){
            {.uuid = &ctrl_uuid.u, .access_cb = ctrl_access,
             .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP},
            {.uuid = &data_uuid.u, .access_cb = data_access, .flags = BLE_GATT_CHR_F_NOTIFY,
             .val_handle = &s_data_handle},
            {.uuid = &live_uuid.u, .access_cb = data_access, .flags = BLE_GATT_CHR_F_NOTIFY,
             .val_handle = &s_live_handle},
            {0},
        },
    },
    {0},
};

/* ---------- GAP ---------- */
// Ask for the fastest link the phone allows. Each step is a request; the phone may refuse.
static void go_fast(uint16_t conn)
{
    // 2M PHY: twice the radio speed
    int rc = ble_gap_set_prefered_le_phy(conn, BLE_GAP_LE_PHY_2M_MASK, BLE_GAP_LE_PHY_2M_MASK,
                                         BLE_GAP_LE_PHY_CODED_ANY);
    if (rc) ESP_LOGW(TAG, "2M phy request %d", rc);
    // Data length extension: 251-byte link packets instead of 27
    rc = ble_gap_set_data_len(conn, 251, 2120);
    if (rc) ESP_LOGW(TAG, "data len request %d", rc);
    // 15-30 ms interval (Apple's minimum is 15 ms), no latency, 4 s timeout
    struct ble_gap_upd_params p = {.itvl_min = 12, .itvl_max = 24, .latency = 0,
                                   .supervision_timeout = 400};
    rc = ble_gap_update_params(conn, &p);
    if (rc) ESP_LOGW(TAG, "conn params request %d", rc);
}

static int gap_event(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (ev->connect.status == 0) {
            s_conn = ev->connect.conn_handle;
            ESP_LOGI(TAG, "phone connected");
            go_fast(s_conn);
        } else {
            advertise();
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "phone disconnected");
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        s_live_on = false;     // keep recording to storage; the phone catches up when it's back
        s_join_req = false;
        advertise();
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        break;
    case BLE_GAP_EVENT_PHY_UPDATE_COMPLETE:
        ESP_LOGI(TAG, "phy tx %d rx %d (2 = 2M)", ev->phy_updated.tx_phy, ev->phy_updated.rx_phy);
        break;
    case BLE_GAP_EVENT_CONN_UPDATE: {
        struct ble_gap_conn_desc d;
        if (ble_gap_conn_find(ev->conn_update.conn_handle, &d) == 0)
            ESP_LOGI(TAG, "conn interval %d.%02d ms", d.conn_itvl * 125 / 100, d.conn_itvl * 125 % 100);
        break;
    }
    case BLE_GAP_EVENT_SUBSCRIBE:
        // Phone turned on live notifications while we're already recording: join in
        if (ev->subscribe.attr_handle == s_live_handle && ev->subscribe.cur_notify && audio_recording())
            s_join_req = true;
        break;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "mtu %d", ev->mtu.value);
        break;
    default:
        break;
    }
    return 0;
}

static void advertise(void)
{
    struct ble_hs_adv_fields f = {0};
    f.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    const char *name = ble_svc_gap_device_name();
    f.name = (uint8_t *)name;
    f.name_len = strlen(name);
    f.name_is_complete = 1;
    f.uuids128 = (ble_uuid128_t *)&svc_uuid;
    f.num_uuids128 = 1;
    f.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&f);
    if (rc) { ESP_LOGE(TAG, "adv fields %d", rc); return; }

    struct ble_gap_adv_params p = {0};
    p.conn_mode = BLE_GAP_CONN_MODE_UND;
    p.disc_mode = BLE_GAP_DISC_MODE_GEN;
    p.itvl_min = BLE_GAP_ADV_ITVL_MS(200);   // slow advertising saves battery
    p.itvl_max = BLE_GAP_ADV_ITVL_MS(300);
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &p, gap_event, NULL);
    if (rc && rc != BLE_HS_EALREADY) ESP_LOGE(TAG, "adv start %d", rc);
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own_addr_type);
    advertise();
    ESP_LOGI(TAG, "advertising as \"%s\"", ble_svc_gap_device_name());
}

static void on_reset(int reason) { ESP_LOGW(TAG, "reset %d", reason); }

static void host_task(void *arg)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void ble_start(void)
{
    s_cmds = xQueueCreate(4, sizeof(cmd_t));
    static StaticMessageBuffer_t live_struct;
    uint8_t *live_mem = heap_caps_malloc(LIVE_QUEUE + 1, MALLOC_CAP_SPIRAM);
    if (live_mem) s_live_q = xMessageBufferCreateStatic(LIVE_QUEUE, live_mem, &live_struct);
    ESP_LOGI(TAG, "internal free %u, largest %u", (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
    if (nimble_port_init() != ESP_OK) { ESP_LOGE(TAG, "nimble init failed"); return; }
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_gatts_count_cfg(s_svcs);
    ble_gatts_add_svcs(s_svcs);
    ble_svc_gap_device_name_set("Pendant");
    // Bluetooth host first, so it gets its internal RAM before our own tasks
    nimble_port_freertos_init(host_task);
    if (xTaskCreate(worker_task, "ble_work", 6144, NULL, 4, NULL) != pdPASS)
        ESP_LOGE(TAG, "ble_work task create failed");
    // Live sender does no flash I/O, so its stack can live in PSRAM
    if (xTaskCreatePinnedToCoreWithCaps(live_task, "ble_live", 4096, NULL, 4, NULL, tskNO_AFFINITY,
                                        MALLOC_CAP_SPIRAM) != pdPASS)
        ESP_LOGE(TAG, "ble_live task create failed");
    ESP_LOGI(TAG, "internal free after start %u, largest %u", (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
}
