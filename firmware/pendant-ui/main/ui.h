#pragma once
void ui_create(void);   // runs inside the LVGL task
void ui_notes_changed(void);
#include <stdbool.h>
void ui_request_record(bool on);   // any task: start/stop recording as if the button was pressed   // any task: notes on storage changed, refresh the list
