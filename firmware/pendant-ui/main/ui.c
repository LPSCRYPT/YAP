// Pendant UI: Home (clock / recording), Notes, Settings.
// Pure black background and few moving pixels keep redraws tiny, so it stays smooth.
#include "ui.h"
#include "audio.h"
#include "board.h"
#include "display.h"
#include "hw.h"
#include "storage.h"
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"

LV_FONT_DECLARE(font_clock);
LV_FONT_DECLARE(font_ui16);
LV_FONT_DECLARE(font_ui20);
LV_FONT_DECLARE(font_ui30);

#define C_BG    lv_color_hex(0x000000)
#define C_CARD  lv_color_hex(0x151517)
#define C_TEXT  lv_color_hex(0xF5F5F7)
#define C_SUB   lv_color_hex(0x8E8E93)
#define C_DIM   lv_color_hex(0x3A3A3C)
#define C_BLUE  lv_color_hex(0x0A84FF)
#define C_RED   lv_color_hex(0xFF453A)

#define DIM_AFTER_MS    15000
#define SLEEP_AFTER_MS  30000
#define POWER_HOLD_MS   3000
#define REC_COVER_AFTER_MS 2000   // while recording: screen goes black except the blue dot
#define REC_DOT_BL      100       // backlight % while only the dot shows

static lv_obj_t *tv, *tile_home, *tile_notes, *tile_set;
static lv_obj_t *page_dots[3];

// Home
static lv_obj_t *idle_box, *lbl_date, *lbl_clock, *lbl_home_info;
static lv_obj_t *rec_box, *lbl_rec_title, *lbl_timer, *rec_arc, *bars[5];
// Overlay
static lv_obj_t *rec_dot, *rec_cover, *toast;
// Notes
static lv_obj_t *notes_list, *notes_empty;
static note_info_t notes[MAX_NOTES];
static int notes_n;
static lv_obj_t *playing_lbl;   // duration label of the note now playing
static int playing_idx = -1;
// Settings
static lv_obj_t *lbl_bat, *lbl_storage, *slider_bright;

static int brightness = 70;
static enum { SCR_ON, SCR_DIM, SCR_OFF } scr_state = SCR_ON;
static bool was_recording;
static volatile bool notes_dirty;

void ui_notes_changed(void) { notes_dirty = true; }

/* ---------- helpers ---------- */
static lv_obj_t *box(lv_obj_t *parent)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    return o;
}

static lv_obj_t *label(lv_obj_t *parent, const lv_font_t *f, lv_color_t c, const char *txt)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, f, 0);
    lv_obj_set_style_text_color(l, c, 0);
    lv_label_set_text(l, txt);
    return l;
}

// Only touch the label when the text really changes (avoids needless redraws)
static void set_text_if(lv_obj_t *l, const char *txt)
{
    if (strcmp(lv_label_get_text(l), txt) != 0) lv_label_set_text(l, txt);
}

static void toast_show(const char *msg)
{
    lv_label_set_text(toast, msg);
    lv_obj_remove_flag(toast, LV_OBJ_FLAG_HIDDEN);
    lv_obj_set_style_opa(toast, LV_OPA_COVER, 0);
    lv_obj_fade_out(toast, 300, 1800);
}

static void save_brightness(void)
{
    nvs_handle_t h;
    if (nvs_open("ui", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_u8(h, "bright", (uint8_t)brightness);
        nvs_commit(h);
        nvs_close(h);
    }
}

static void load_brightness(void)
{
    nvs_handle_t h;
    uint8_t v;
    if (nvs_open("ui", NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_u8(h, "bright", &v) == ESP_OK && v >= 5 && v <= 100) brightness = v;
        nvs_close(h);
    }
}

/* ---------- screen sleep ---------- */
static void wake(void)
{
    lv_display_trigger_activity(NULL);
    if (rec_cover && !lv_obj_has_flag(rec_cover, LV_OBJ_FLAG_HIDDEN)) {
        lv_obj_add_flag(rec_cover, LV_OBJ_FLAG_HIDDEN);
        scr_state = SCR_DIM;   // forces the backlight back up below
    }
    if (scr_state != SCR_ON) {
        scr_state = SCR_ON;
        display_set_asleep(false, NULL);
        hw_backlight_set(brightness);
    }
}

static void wake_from_touch(void) { wake(); }  // called from inside the LVGL task

static void sleep_timer_cb(lv_timer_t *t)
{
    uint32_t idle = lv_display_get_inactive_time(NULL);
    // Recording: after a moment, black out everything but the blue dot.
    // A touch or button press shows the full recording screen again.
    if (audio_recording()) {
        bool cover = idle > REC_COVER_AFTER_MS;
        if (cover && lv_obj_has_flag(rec_cover, LV_OBJ_FLAG_HIDDEN)) {
            lv_obj_remove_flag(rec_cover, LV_OBJ_FLAG_HIDDEN);
            scr_state = SCR_DIM;
            hw_backlight_set(REC_DOT_BL);
        }
        return;
    }
    if (scr_state == SCR_ON && idle > DIM_AFTER_MS) {
        scr_state = SCR_DIM;
        hw_backlight_set(brightness / 4 > 5 ? brightness / 4 : 5);
    } else if (scr_state == SCR_DIM && idle > SLEEP_AFTER_MS) {
        // While recording, never go fully dark: the blue dot must stay visible
        if (audio_recording()) return;
        scr_state = SCR_OFF;
        hw_backlight_set(0);
        display_set_asleep(true, wake_from_touch);
    }
}

/* ---------- recording ---------- */
static void notes_refresh(void);

static void show_recording(bool on)
{
    if (on) {
        lv_obj_add_flag(idle_box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(rec_box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(rec_arc, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(rec_dot, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(lbl_timer, "00:00");
        lv_arc_set_angles(rec_arc, 0, 0);
    } else {
        lv_obj_add_flag(rec_box, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(rec_arc, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(rec_dot, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(idle_box, LV_OBJ_FLAG_HIDDEN);
        wake();   // lift the black cover
    }
}

static void toggle_recording(void)
{
    if (audio_recording()) {
        audio_rec_stop();
        show_recording(false);   // instant feedback; file closes in the background
    } else {
        if (!audio_rec_start()) {
            toast_show(storage_ready() ? "Storage full" : "No storage");
            return;
        }
        lv_tileview_set_tile_by_index(tv, 0, 0, LV_ANIM_ON);
        show_recording(true);
        was_recording = true;
    }
}

static void rec_timer_cb(lv_timer_t *t)
{
    bool rec = audio_recording();
    if (was_recording && !rec) {   // finished saving (or stopped because storage is full)
        was_recording = false;
        show_recording(false);
        int idx = 0;
        sscanf(audio_last_file(), "N%4d", &idx);
        char msg[40];
        snprintf(msg, sizeof(msg), "Saved  \xC2\xB7  Note %d", idx);
        toast_show(msg);
        notes_refresh();
        return;
    }
    if (!rec || lv_obj_has_flag(rec_box, LV_OBJ_FLAG_HIDDEN)) return;
    if (!lv_obj_has_flag(rec_cover, LV_OBJ_FLAG_HIDDEN)) return;   // screen is blacked out

    uint32_t ms = audio_rec_ms(), s = ms / 1000;
    char buf[16];
    if (s < 6000) snprintf(buf, sizeof(buf), "%02lu:%02lu", (unsigned long)(s / 60), (unsigned long)(s % 60));
    else snprintf(buf, sizeof(buf), "%lu:%02lu", (unsigned long)(s / 3600), (unsigned long)(s / 60 % 60));
    set_text_if(lbl_timer, buf);

    // Bezel arc fills once per minute
    lv_arc_set_angles(rec_arc, 0, (ms % 60000) * 360 / 60000);

    // Level bars: middle bars react most
    static const int weight[5] = {55, 80, 100, 80, 55};
    int lvl = audio_level();
    for (int i = 0; i < 5; i++) {
        int h = 6 + lvl * weight[i] * 34 / 10000;
        if (lv_obj_get_height(bars[i]) != h) lv_obj_set_height(bars[i], h);
    }
}

/* ---------- buttons (polled; no locking needed) ---------- */
static volatile int s_rec_request = -1;   // set from the BLE task, handled in the LVGL task

void ui_request_record(bool on) { s_rec_request = on ? 1 : 0; }

static void button_timer_cb(lv_timer_t *t)
{
    int req = s_rec_request;
    if (req >= 0) {
        s_rec_request = -1;
        if ((req == 1) != audio_recording()) {
            wake();
            toggle_recording();
        }
    }

    static bool pwr_armed, prev_pwr, prev_boot, started_by_press;
    static int64_t pwr_down_at;
    bool pwr = hw_btn_pwr_down(), boot = hw_btn_boot_down();
    int64_t now = esp_timer_get_time() / 1000;

    if (!pwr) pwr_armed = true;   // ignore the press that powered the board on

    if (pwr_armed && pwr && !prev_pwr) {
        pwr_down_at = now;
        wake();
        toggle_recording();       // act on press, not release: feels instant
        started_by_press = audio_recording();
    }
    if (pwr_armed && pwr && pwr_down_at && now - pwr_down_at > POWER_HOLD_MS) {
        pwr_down_at = 0;
        bool discard = started_by_press && audio_recording();
        if (audio_recording()) audio_rec_stop();
        show_recording(false);
        toast_show("Powering off");
        lv_refr_now(NULL);
        vTaskDelay(pdMS_TO_TICKS(600));   // let the file close
        if (discard) {                    // this hold was meant as power off, not a note
            storage_remove_note(audio_last_file());
            was_recording = false;
            notes_refresh();
        }
        hw_power_off();
        // Still alive: running on USB power
        hw_backlight_set(brightness);
        toast_show("On USB power");
    }
    if (!pwr) { pwr_down_at = 0; started_by_press = false; }

    if (boot && !prev_boot) {
        wake();
        toggle_recording();
    }
    prev_pwr = pwr;
    prev_boot = boot;
}

/* ---------- clock / status ---------- */
static void clock_timer_cb(lv_timer_t *t)
{
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char buf[32];
    strftime(buf, sizeof(buf), "%H:%M", &tm);
    set_text_if(lbl_clock, buf);
    strftime(buf, sizeof(buf), "%a, %d %b", &tm);
    set_text_if(lbl_date, buf);
}

static void status_update(void)
{
    char buf[64];
    int pct = hw_battery_percent(), mv = hw_battery_mv();
    if (pct < 0) snprintf(buf, sizeof(buf), "USB power");
    else snprintf(buf, sizeof(buf), "%d%%  \xC2\xB7  %d.%02d V", pct, mv / 1000, (mv % 1000) / 10);
    set_text_if(lbl_bat, buf);

    if (!storage_ready()) snprintf(buf, sizeof(buf), "No storage");
    else {
        uint64_t f = storage_free_bytes();
        if (f > 1024ULL * 1024 * 1024)
            snprintf(buf, sizeof(buf), "%s  \xC2\xB7  %.1f GB free", storage_on_sd() ? "SD card" : "Internal",
                     f / 1073741824.0);
        else
            snprintf(buf, sizeof(buf), "%s  \xC2\xB7  %llu MB free", storage_on_sd() ? "SD card" : "Internal",
                     f / 1048576);
    }
    set_text_if(lbl_storage, buf);

    if (pct < 0) snprintf(buf, sizeof(buf), "%d notes", notes_n);
    else snprintf(buf, sizeof(buf), "%d%%  \xC2\xB7  %d notes", pct, notes_n);
    set_text_if(lbl_home_info, buf);
}

static void status_timer_cb(lv_timer_t *t) { status_update(); }

/* ---------- page dots ---------- */
static void tile_changed_cb(lv_event_t *e)
{
    lv_obj_t *act = lv_tileview_get_tile_active(tv);
    int idx = act == tile_home ? 0 : act == tile_notes ? 1 : 2;
    for (int i = 0; i < 3; i++) {
        lv_obj_set_style_bg_color(page_dots[i], i == idx ? C_TEXT : C_DIM, 0);
        lv_obj_set_width(page_dots[i], i == idx ? 18 : 6);
    }
    if (idx == 2) status_update();
}

/* ---------- Home ---------- */
static void build_home(void)
{
    // Idle: date + clock + info
    idle_box = box(tile_home);
    lv_obj_set_size(idle_box, LV_PCT(100), LV_PCT(100));
    lbl_date = label(idle_box, &font_ui20, C_SUB, "");
    lv_obj_align(lbl_date, LV_ALIGN_CENTER, 0, -86);
    lbl_clock = label(idle_box, &font_clock, C_TEXT, "00:00");
    lv_obj_align(lbl_clock, LV_ALIGN_CENTER, 0, -6);
    lbl_home_info = label(idle_box, &font_ui16, C_SUB, "");
    lv_obj_align(lbl_home_info, LV_ALIGN_CENTER, 0, 78);
    lv_obj_t *hint = label(idle_box, &font_ui16, C_DIM, "Press button to record");
    lv_obj_align(hint, LV_ALIGN_BOTTOM_MID, 0, -70);

    // Recording: thin bezel arc, timer, level bars
    rec_arc = lv_arc_create(tile_home);
    lv_obj_set_size(rec_arc, LCD_W - 10, LCD_H - 10);
    lv_obj_center(rec_arc);
    lv_arc_set_rotation(rec_arc, 270);
    lv_arc_set_bg_angles(rec_arc, 0, 360);
    lv_arc_set_angles(rec_arc, 0, 0);
    lv_obj_remove_style(rec_arc, NULL, LV_PART_KNOB);
    lv_obj_remove_flag(rec_arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_arc_width(rec_arc, 4, LV_PART_MAIN);
    lv_obj_set_style_arc_color(rec_arc, lv_color_hex(0x1C1C1E), LV_PART_MAIN);
    lv_obj_set_style_arc_width(rec_arc, 4, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(rec_arc, C_BLUE, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(rec_arc, true, LV_PART_INDICATOR);
    lv_obj_add_flag(rec_arc, LV_OBJ_FLAG_HIDDEN);

    rec_box = box(tile_home);
    lv_obj_set_size(rec_box, LV_PCT(100), LV_PCT(100));
    lbl_rec_title = label(rec_box, &font_ui20, C_BLUE, "Recording");
    lv_obj_align(lbl_rec_title, LV_ALIGN_CENTER, 0, -86);
    lbl_timer = label(rec_box, &font_clock, C_TEXT, "00:00");
    lv_obj_align(lbl_timer, LV_ALIGN_CENTER, 0, -6);

    lv_obj_t *bar_row = box(rec_box);
    lv_obj_set_size(bar_row, 5 * 7 + 4 * 7, 44);
    lv_obj_align(bar_row, LV_ALIGN_CENTER, 0, 86);
    for (int i = 0; i < 5; i++) {
        bars[i] = box(bar_row);
        lv_obj_set_size(bars[i], 7, 6);
        lv_obj_set_style_bg_opa(bars[i], LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(bars[i], C_BLUE, 0);
        lv_obj_set_style_radius(bars[i], 4, 0);
        lv_obj_align(bars[i], LV_ALIGN_LEFT_MID, i * 14, 0);
    }
    lv_obj_t *stop = label(rec_box, &font_ui16, C_DIM, "Press to stop");
    lv_obj_align(stop, LV_ALIGN_BOTTOM_MID, 0, -70);
    lv_obj_add_flag(rec_box, LV_OBJ_FLAG_HIDDEN);
}

/* ---------- Notes ---------- */
static void note_click_cb(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    lv_obj_t *dur = lv_obj_get_child(lv_event_get_current_target(e), 2);
    if (audio_recording()) return;

    bool same = audio_playing() && playing_idx == i;
    if (playing_lbl) {   // reset previous row
        char d[16];
        snprintf(d, sizeof(d), "%lu:%02lu", (unsigned long)(notes[playing_idx].seconds / 60),
                 (unsigned long)(notes[playing_idx].seconds % 60));
        lv_label_set_text(playing_lbl, d);
        lv_obj_set_style_text_color(playing_lbl, C_SUB, 0);
        playing_lbl = NULL;
        playing_idx = -1;
    }
    if (same) {
        audio_play_stop();
        return;
    }
    if (audio_play(notes[i].name)) {
        playing_lbl = dur;
        playing_idx = i;
        lv_label_set_text(dur, LV_SYMBOL_PAUSE);
        lv_obj_set_style_text_color(dur, C_BLUE, 0);
    }
}

static void play_watch_cb(lv_timer_t *t)
{
    if (notes_dirty && !audio_playing()) { notes_dirty = false; notes_refresh(); }
    if (playing_lbl && !audio_playing()) {
        char d[16];
        snprintf(d, sizeof(d), "%lu:%02lu", (unsigned long)(notes[playing_idx].seconds / 60),
                 (unsigned long)(notes[playing_idx].seconds % 60));
        lv_label_set_text(playing_lbl, d);
        lv_obj_set_style_text_color(playing_lbl, C_SUB, 0);
        playing_lbl = NULL;
        playing_idx = -1;
    }
}

static void notes_refresh(void)
{
    if (audio_playing()) audio_play_stop();
    playing_lbl = NULL;
    playing_idx = -1;
    lv_obj_clean(notes_list);
    notes_n = storage_list(notes, MAX_NOTES);
    if (notes_n == 0) lv_obj_remove_flag(notes_empty, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(notes_empty, LV_OBJ_FLAG_HIDDEN);

    for (int i = 0; i < notes_n; i++) {
        lv_obj_t *row = box(notes_list);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_flag(row, LV_OBJ_FLAG_SCROLL_ON_FOCUS);
        lv_obj_set_size(row, LV_PCT(100), 66);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(row, C_CARD, 0);
        lv_obj_set_style_bg_color(row, lv_color_hex(0x26262A), LV_STATE_PRESSED);
        lv_obj_set_style_radius(row, 20, 0);
        lv_obj_add_event_cb(row, note_click_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);

        int idx = 0;
        sscanf(notes[i].name, "N%4d", &idx);
        char t[32];
        snprintf(t, sizeof(t), "Note %d", idx);
        lv_obj_t *title = label(row, &font_ui20, C_TEXT, t);
        lv_obj_align(title, LV_ALIGN_TOP_LEFT, 20, 11);

        struct tm tm;
        localtime_r(&notes[i].when, &tm);
        strftime(t, sizeof(t), "%d %b  \xC2\xB7  %H:%M", &tm);
        lv_obj_t *sub = label(row, &font_ui16, C_SUB, t);
        lv_obj_align(sub, LV_ALIGN_BOTTOM_LEFT, 20, -10);

        snprintf(t, sizeof(t), "%lu:%02lu", (unsigned long)(notes[i].seconds / 60),
                 (unsigned long)(notes[i].seconds % 60));
        lv_obj_t *dur = label(row, &font_ui16, C_SUB, t);
        lv_obj_align(dur, LV_ALIGN_RIGHT_MID, -20, 0);
    }
    if (lbl_home_info) status_update();
}

static void build_notes(void)
{
    lv_obj_t *title = label(tile_notes, &font_ui30, C_TEXT, "Notes");
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 50);

    notes_list = box(tile_notes);
    lv_obj_add_flag(notes_list, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(notes_list, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(notes_list, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_size(notes_list, 290, LCD_H - 100 - 60);
    lv_obj_align(notes_list, LV_ALIGN_TOP_MID, 0, 100);
    lv_obj_set_flex_flow(notes_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(notes_list, 8, 0);
    lv_obj_set_style_pad_bottom(notes_list, 40, 0);

    notes_empty = box(tile_notes);
    lv_obj_set_size(notes_empty, LV_PCT(100), 80);
    lv_obj_center(notes_empty);
    lv_obj_t *a = label(notes_empty, &font_ui20, C_SUB, "No notes yet");
    lv_obj_align(a, LV_ALIGN_TOP_MID, 0, 8);
    lv_obj_t *b = label(notes_empty, &font_ui16, C_DIM, "Press the button to record");
    lv_obj_align(b, LV_ALIGN_TOP_MID, 0, 40);
}

/* ---------- Settings ---------- */
static void bright_cb(lv_event_t *e)
{
    brightness = lv_slider_get_value(slider_bright);
    hw_backlight_set(brightness);
    if (lv_event_get_code(e) == LV_EVENT_RELEASED) save_brightness();
}

static void power_cb(lv_event_t *e)
{
    if (audio_recording()) audio_rec_stop();
    toast_show("Powering off");
    lv_refr_now(NULL);
    vTaskDelay(pdMS_TO_TICKS(600));
    hw_power_off();
    hw_backlight_set(brightness);
    toast_show("On USB power");
}

static lv_obj_t *setting_row(lv_obj_t *parent, const char *name, int h)
{
    lv_obj_t *row = box(parent);
    lv_obj_set_size(row, LV_PCT(100), h);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(row, C_CARD, 0);
    lv_obj_set_style_radius(row, 20, 0);
    lv_obj_t *n = label(row, &font_ui16, C_SUB, name);
    lv_obj_align(n, LV_ALIGN_TOP_LEFT, 20, 10);
    return row;
}

static void build_settings(void)
{
    lv_obj_t *title = label(tile_set, &font_ui30, C_TEXT, "Settings");
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 50);

    lv_obj_t *col = box(tile_set);
    lv_obj_add_flag(col, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_scroll_dir(col, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(col, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_size(col, 290, LCD_H - 100 - 60);
    lv_obj_align(col, LV_ALIGN_TOP_MID, 0, 100);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, 8, 0);
    lv_obj_set_style_pad_bottom(col, 60, 0);

    lv_obj_t *r = setting_row(col, "Battery", 66);
    lbl_bat = label(r, &font_ui20, C_TEXT, "");
    lv_obj_align(lbl_bat, LV_ALIGN_BOTTOM_LEFT, 20, -10);

    r = setting_row(col, "Brightness", 74);
    slider_bright = lv_slider_create(r);
    lv_obj_remove_style_all(slider_bright);
    lv_obj_set_size(slider_bright, 240, 8);
    lv_obj_align(slider_bright, LV_ALIGN_BOTTOM_MID, 0, -18);
    lv_obj_set_ext_click_area(slider_bright, 20);
    lv_slider_set_range(slider_bright, 5, 100);
    lv_slider_set_value(slider_bright, brightness, LV_ANIM_OFF);
    lv_obj_set_style_bg_opa(slider_bright, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_bg_color(slider_bright, C_DIM, LV_PART_MAIN);
    lv_obj_set_style_radius(slider_bright, 4, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(slider_bright, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(slider_bright, C_TEXT, LV_PART_INDICATOR);
    lv_obj_set_style_radius(slider_bright, 4, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(slider_bright, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_bg_color(slider_bright, C_TEXT, LV_PART_KNOB);
    lv_obj_set_style_radius(slider_bright, LV_RADIUS_CIRCLE, LV_PART_KNOB);
    lv_obj_set_style_pad_all(slider_bright, 6, LV_PART_KNOB);
    lv_obj_add_event_cb(slider_bright, bright_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_add_event_cb(slider_bright, bright_cb, LV_EVENT_RELEASED, NULL);

    r = setting_row(col, "Storage", 66);
    lbl_storage = label(r, &font_ui20, C_TEXT, "");
    lv_obj_align(lbl_storage, LV_ALIGN_BOTTOM_LEFT, 20, -10);

    r = setting_row(col, "Privacy", 66);
    lv_obj_t *p = label(r, &font_ui20, C_TEXT, "Stored on device only");
    lv_obj_align(p, LV_ALIGN_BOTTOM_LEFT, 20, -10);

    r = setting_row(col, "Firmware", 66);
    lv_obj_t *v = label(r, &font_ui20, C_TEXT, "v" FW_VERSION);
    lv_obj_align(v, LV_ALIGN_BOTTOM_LEFT, 20, -10);

    lv_obj_t *pw = box(col);
    lv_obj_add_flag(pw, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(pw, LV_PCT(100), 56);
    lv_obj_set_style_bg_opa(pw, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(pw, C_CARD, 0);
    lv_obj_set_style_bg_color(pw, lv_color_hex(0x26262A), LV_STATE_PRESSED);
    lv_obj_set_style_radius(pw, 20, 0);
    lv_obj_t *pl = label(pw, &font_ui20, C_RED, "Power off");
    lv_obj_center(pl);
    lv_obj_add_event_cb(pw, power_cb, LV_EVENT_CLICKED, NULL);
}

/* ---------- Root ---------- */
static void dot_opa_cb(void *obj, int32_t v) { lv_obj_set_style_opa(obj, (lv_opa_t)v, 0); }
static void cover_tap_cb(lv_event_t *e) { wake(); }

void ui_create(void)
{
    load_brightness();

    lv_obj_t *scr = lv_screen_active();
    lv_obj_remove_style_all(scr);
    lv_obj_set_style_bg_color(scr, C_BG, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(scr, C_TEXT, 0);

    tv = lv_tileview_create(scr);
    lv_obj_set_style_bg_opa(tv, LV_OPA_TRANSP, 0);
    lv_obj_set_scrollbar_mode(tv, LV_SCROLLBAR_MODE_OFF);
    tile_home = lv_tileview_add_tile(tv, 0, 0, LV_DIR_RIGHT);
    tile_notes = lv_tileview_add_tile(tv, 1, 0, LV_DIR_LEFT | LV_DIR_RIGHT);
    tile_set = lv_tileview_add_tile(tv, 2, 0, LV_DIR_LEFT);
    lv_obj_add_event_cb(tv, tile_changed_cb, LV_EVENT_VALUE_CHANGED, NULL);

    build_home();
    build_notes();
    build_settings();

    // Page dots (top layer, so they don't scroll)
    lv_obj_t *dots = box(lv_layer_top());
    lv_obj_set_size(dots, 60, 6);
    lv_obj_align(dots, LV_ALIGN_BOTTOM_MID, 0, -24);
    lv_obj_set_flex_flow(dots, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(dots, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(dots, 6, 0);
    for (int i = 0; i < 3; i++) {
        page_dots[i] = box(dots);
        lv_obj_set_size(page_dots[i], i == 0 ? 18 : 6, 6);
        lv_obj_set_style_radius(page_dots[i], 3, 0);
        lv_obj_set_style_bg_opa(page_dots[i], LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(page_dots[i], i == 0 ? C_TEXT : C_DIM, 0);
    }

    // Black cover shown while recording (under the dot). Clickable so a tap
    // only wakes the screen and doesn't hit the UI underneath.
    rec_cover = box(lv_layer_top());
    lv_obj_set_size(rec_cover, LCD_W, LCD_H);
    lv_obj_set_style_bg_opa(rec_cover, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(rec_cover, C_BG, 0);
    lv_obj_add_flag(rec_cover, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(rec_cover, cover_tap_cb, LV_EVENT_PRESSED, NULL);

    // Blue recording dot, always on top, gently breathing
    rec_dot = box(lv_layer_top());
    lv_obj_set_size(rec_dot, 24, 24);
    lv_obj_set_style_radius(rec_dot, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_opa(rec_dot, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(rec_dot, C_BLUE, 0);
    lv_obj_align(rec_dot, LV_ALIGN_TOP_MID, 0, 18);
    lv_obj_add_flag(rec_dot, LV_OBJ_FLAG_HIDDEN);
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, rec_dot);
    lv_anim_set_values(&a, LV_OPA_COVER, LV_OPA_70);
    lv_anim_set_duration(&a, 1000);
    lv_anim_set_playback_duration(&a, 1000);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_set_exec_cb(&a, dot_opa_cb);
    lv_anim_start(&a);

    // Toast
    toast = label(lv_layer_top(), &font_ui16, C_TEXT, "");
    lv_obj_set_style_bg_opa(toast, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(toast, lv_color_hex(0x232326), 0);
    lv_obj_set_style_radius(toast, 16, 0);
    lv_obj_set_style_pad_hor(toast, 16, 0);
    lv_obj_set_style_pad_ver(toast, 8, 0);
    lv_obj_align(toast, LV_ALIGN_BOTTOM_MID, 0, -46);
    lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN);

    clock_timer_cb(NULL);
    notes_refresh();
    status_update();

    lv_timer_create(clock_timer_cb, 1000, NULL);
    lv_timer_create(rec_timer_cb, 66, NULL);
    lv_timer_create(button_timer_cb, 15, NULL);
    lv_timer_create(sleep_timer_cb, 500, NULL);
    lv_timer_create(status_timer_cb, 10000, NULL);
    lv_timer_create(play_watch_cb, 200, NULL);

    hw_backlight_set(brightness);
}
