#include <Arduino_H7_Video.h>
#include <lvgl.h>
#include "Arduino_GigaDisplayTouch.h"

Arduino_H7_Video Display;
Arduino_GigaDisplayTouch TouchDetector;

int rotationMode = 0; // 0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°
lv_obj_t *rotate_btn;
lv_obj_t *label;

static void rotate_screen_cb(lv_event_t *e) {
    rotationMode = (rotationMode + 1) % 4;
    Serial.print("[ROTATE] Setting rotationMode to: ");
    Serial.println(rotationMode);
    if (rotationMode == 0) {
        Serial.println("[ROTATE] LV_DISPLAY_ROTATION_0");
        lv_disp_set_rotation(NULL, LV_DISPLAY_ROTATION_0);
    } else if (rotationMode == 1) {
        Serial.println("[ROTATE] LV_DISPLAY_ROTATION_90");
        lv_disp_set_rotation(NULL, LV_DISPLAY_ROTATION_90);
    } else if (rotationMode == 2) {
        Serial.println("[ROTATE] LV_DISPLAY_ROTATION_180");
        lv_disp_set_rotation(NULL, LV_DISPLAY_ROTATION_180);
    } else if (rotationMode == 3) {
        Serial.println("[ROTATE] LV_DISPLAY_ROTATION_270");
        lv_disp_set_rotation(NULL, LV_DISPLAY_ROTATION_270);
    }
    lv_refr_now(NULL);
    // Rebuild UI after rotation
    lv_obj_clean(lv_scr_act());
    label = lv_label_create(lv_scr_act());
    lv_label_set_text(label, (rotationMode == 0) ? "0°" : (rotationMode == 1) ? "90°" : (rotationMode == 2) ? "180°" : "270°");
    lv_obj_align(label, LV_ALIGN_CENTER, 0, -40);
    rotate_btn = lv_btn_create(lv_scr_act());
    lv_obj_set_size(rotate_btn, 180, 70);
    lv_obj_align(rotate_btn, LV_ALIGN_CENTER, 0, 60);
    lv_obj_add_event_cb(rotate_btn, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *btn_label = lv_label_create(rotate_btn);
    lv_label_set_text(btn_label, "ROTATE");
    lv_obj_center(btn_label);
}

void setup() {
    Serial.begin(115200);
    delay(2000);
    Serial.println("=== SIMPLE ROTATE TEST STARTING ===");
    Display.begin();
    TouchDetector.begin();
    lv_obj_clean(lv_scr_act());
    label = lv_label_create(lv_scr_act());
    lv_label_set_text(label, "0°");
    lv_obj_align(label, LV_ALIGN_CENTER, 0, -40);
    rotate_btn = lv_btn_create(lv_scr_act());
    lv_obj_set_size(rotate_btn, 180, 70);
    lv_obj_align(rotate_btn, LV_ALIGN_CENTER, 0, 60);
    lv_obj_add_event_cb(rotate_btn, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *btn_label = lv_label_create(rotate_btn);
    lv_label_set_text(btn_label, "ROTATE");
    lv_obj_center(btn_label);
    Serial.println("UI ready. Press ROTATE to cycle orientations.");
}

void loop() {
    lv_timer_handler();
    delay(1);
}
