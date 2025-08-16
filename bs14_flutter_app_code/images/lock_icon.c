
/* Simple 16x16 monochrome padlock icon for LVGL */
#include "lvgl.h"
#include <stdint.h>

#ifndef LV_ATTRIBUTE_MEM_ALIGN
#define LV_ATTRIBUTE_MEM_ALIGN
#endif

#ifndef LV_ATTRIBUTE_IMAGE_LOCK_ICON
#define LV_ATTRIBUTE_IMAGE_LOCK_ICON
#endif

/* 16x16, 1bpp, padlock shape: 0=transparent, 1=black */
const LV_ATTRIBUTE_MEM_ALIGN LV_ATTRIBUTE_LARGE_CONST LV_ATTRIBUTE_IMAGE_LOCK_ICON uint8_t lock_icon_map[] = {
  0b0000011111100000,
  0b0001111111111000,
  0b0011111111111100,
  0b0111110000111110,
  0b0111100000011110,
  0b1111000000001111,
  0b1111000000001111,
  0b1111001111001111,
  0b1111001111001111,
  0b1111001111001111,
  0b1111001111001111,
  0b0111101111011110,
  0b0111111111111110,
  0b0011111111111100,
  0b0001111111111000,
  0b0000011111100000
};

const lv_img_dsc_t lock_icon = {
  .header.cf = LV_COLOR_FORMAT_A1, // 1bpp (monochrome)
  .header.always_zero = 0,
  .header.w = 16,
  .header.h = 16,
  .data_size = sizeof(lock_icon_map),
  .data = lock_icon_map,
};
