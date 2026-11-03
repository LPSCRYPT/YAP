#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void ble_start(void);       // advertise as "Pendant" for the phone app
bool ble_connected(void);

// Live sync: while recording, the note's .opus bytes are pushed to the phone as they are made,
// so the phone has the whole note the moment recording stops. Never blocks the caller.
void ble_live_start(const char *wav_name);
void ble_live_data(const void *data, size_t len);   // bytes exactly as written to the .opus file
void ble_live_end(uint32_t total_bytes);            // total size of the .opus file
// Phone came (back) in range while recording. The writer checks before each write and joins
// at the current offset (after flushing the file so the phone can fetch what it missed).
bool ble_live_join_pending(void);
void ble_live_join(const char *wav_name, uint32_t offset);
