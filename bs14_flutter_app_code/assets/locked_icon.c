#include "lvgl.h"
#include <stdint.h>

// Placeholder image data array. Replace with actual image data.
const uint8_t locked_icon_map[1024] = { 0 };

const lv_img_dsc_t locked_icon = {
    {LV_COLOR_FORMAT_RGB565, LV_IMAGE_HEADER_MAGIC, 368, 365}, // header: cf, magic, w, h
    ...data_size...,
    ...data...,
};
