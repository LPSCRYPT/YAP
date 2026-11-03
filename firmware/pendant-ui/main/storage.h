#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define NOTES_DIR  "/data/notes"
#define MAX_NOTES  60

typedef struct {
    char name[40];      // file name, e.g. N0007_20261031_140210.wav
    uint32_t seconds;   // duration
    time_t when;        // start time
} note_info_t;

void storage_init(void);              // SD card if present, otherwise internal flash
bool storage_ready(void);
bool storage_on_sd(void);
uint64_t storage_free_bytes(void);
uint64_t storage_total_bytes(void);
int  storage_list(note_info_t *out, int max);   // newest first
int  storage_next_index(void);

// Each note N....wav may have a compressed twin N....opus (same name, made while recording).
// The phone downloads the .opus (about 12x smaller); the .wav stays for playback on the pendant.
void storage_opus_path(const char *wav_name, char *out, size_t out_len);
bool storage_remove_note(const char *wav_name);   // deletes the .wav and its .opus
