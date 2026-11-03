#pragma once
#include <stdbool.h>
#include <stdint.h>

void audio_init(void);

bool audio_rec_start(void);     // false if storage is missing or full
void audio_rec_stop(void);
bool audio_recording(void);
uint32_t audio_rec_ms(void);    // elapsed recording time
int  audio_level(void);         // live mic level, 0..100
const char *audio_last_file(void);

bool audio_play(const char *name);  // file name inside NOTES_DIR
void audio_play_stop(void);
bool audio_playing(void);
const char *audio_playing_name(void);
