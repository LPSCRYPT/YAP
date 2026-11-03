#pragma once
#include <stdbool.h>
#include "lvgl.h"

// Start LCD, touch and the LVGL task. `ui_create` runs once inside the LVGL task.
void display_start(void (*ui_create)(void));

// Use around any LVGL call made from another task.
void display_lock(void);
void display_unlock(void);

// While asleep, the first touch only wakes the screen and is not passed to the UI.
void display_set_asleep(bool asleep, void (*on_wake_touch)(void));
