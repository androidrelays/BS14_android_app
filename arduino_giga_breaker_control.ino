#include <ArduinoBLE.h>
#include <Arduino_H7_Video.h>
#include <lvgl.h>
#include <stdint.h>
#include <font/lv_font.h>
#include "locked.h"
#include "Arduino_GigaDisplayTouch.h"


// Bluetooth - Use custom UUIDs matching Flutter app expectations
BLEService breakerService("12345678-1234-1234-1234-123456789abc");
BLECharacteristic commandChar("87654321-4321-4321-4321-cba987654321", BLEWrite, 20);
BLECharacteristic statusChar("11011111-2222-3333-4444-555555555555", BLERead | BLENotify, 20);
// Lock BLE characteristic (read/write, 1 byte: 0=unlocked, 1=locked)
BLECharacteristic lockChar("22222222-3333-4444-5555-666666666666", BLERead | BLEWrite | BLENotify, 1);

// Hardware interfaces
Arduino_H7_Video Display;
Arduino_GigaDisplayTouch TouchDetector;

// UI objects
lv_obj_t *switch_69;
lv_obj_t *ui_container;
lv_obj_t *tight_container;
lv_obj_t *switch_container;
lv_obj_t *btn_open;
// Define LV_SYMBOL_LOCK for overlay lock symbol
#ifndef LV_SYMBOL_LOCK
#define LV_SYMBOL_LOCK "\xef\x80\xa3"
#endif
lv_obj_t *btn_close;
lv_obj_t *close_btn_overlay; // Overlay for disabled state symbol
lv_obj_t *open_btn_overlay; // Overlay for disabled state symbol on open button
lv_obj_t *lock_icon_btn = NULL; // Lock icon button
lv_obj_t *lock_icon_label = NULL; // Lock icon label (L/U)
lv_obj_t *lock_container = NULL; // Container for lock button

// LED pins (active-low RGB)
const int redled = 86;
const int greenled = 87;
const int blueled = 88;

// Breaker control pins
const int sense = 37;    // D37 for breaker status output
const int pin39 = 39;    // D39 output control
const int pin41 = 41;    // D41 output control
const int openInput = 45;  // D45 input for open command
const int closeInput = 43; // D43 input for close command

// State variables
bool switchToggled = true;
bool portraitMode  = false;
bool breakerstate  = true; // true = Open (green), false = Closed (red)
bool bluetoothConnected = false;
unsigned long lastStatusSent = 0;
bool locked = false; // Lock state
unsigned long lock_press_start = 0; // For long-press detection

// Function declarations
static void set_leds();
static void set_breaker_state(bool open);
static void open_btn_cb(lv_event_t *e);
static void close_btn_cb(lv_event_t *e);
static void switch_toggled_cb(lv_event_t *e);
static void update_button_styles();
static void rotate_screen_cb(lv_event_t *e);
static void send_status_to_flutter();
static void lock_icon_event_cb(lv_event_t *e);
static void update_lock_icon();

void setup() {
  Serial.begin(115200);
  delay(2000); // Give time for Serial Monitor to connect
  Serial.println("=== ARDUINO GIGA STARTING ===");
  Serial.println("Initializing display...");
  
  Display.begin();
  TouchDetector.begin();
  Serial.println("Display initialized!");
  
  // Bluetooth
  Serial.println("Starting Bluetooth initialization...");
  if (!BLE.begin()) {
    Serial.println("Starting BLE failed!");
    while (1);
  }
  Serial.println("BLE started successfully!");
  
  // Set device name and make it discoverable
  BLE.setLocalName("BS14");
  BLE.setDeviceName("BS14");
  
  // Configure advertising with both characteristics
  BLE.setAdvertisedService(breakerService);
  breakerService.addCharacteristic(commandChar);
  breakerService.addCharacteristic(statusChar);
  breakerService.addCharacteristic(lockChar);
  BLE.addService(breakerService);
  
  // Set advertising parameters for maximum discoverability
  BLE.setAdvertisingInterval(100); // Faster advertising - 62.5ms intervals
  BLE.setConnectable(true);
  
  // Start advertising with discoverability
  BLE.advertise();
  Serial.println("==============================");
  Serial.println("BLE DEVICE READY");
  Serial.println("==============================");
  Serial.println("Device name: BS14");
  Serial.print("Service UUID: ");
  Serial.println("12345678-1234-1234-1234-123456789abc");
  Serial.println("Device should now be discoverable");
  Serial.println("Check your phone's Bluetooth settings!");
  Serial.println("==============================");

  pinMode(redled,     OUTPUT);
  pinMode(greenled,   OUTPUT);
  pinMode(blueled,    OUTPUT);
  pinMode(sense,      OUTPUT);    // D37 as output for breaker status
  pinMode(pin39,      OUTPUT);    // D39 as output control
  pinMode(pin41,      OUTPUT);    // D41 as output control
  pinMode(openInput,  INPUT);  // D45 as input for open command
  pinMode(closeInput, INPUT); // D43 as input for close command

  // Turn all LEDs off (HIGH = off for active-low)
  digitalWrite(redled,   HIGH);
  digitalWrite(greenled, HIGH);
  digitalWrite(blueled,  HIGH);

  // Initialize breaker control outputs
  digitalWrite(pin39, LOW);  // Initialize pin39 to LOW
  digitalWrite(pin41, LOW);  // Initialize pin41 to LOW

  // Initialize breaker state and sense pin
  breakerstate = true;
  digitalWrite(sense, LOW); // Initialize sense pin to LOW (open state)
  set_leds();
  rotate_screen_cb(NULL); // Build UI
  update_lock_icon();
}

void loop() {
  // Check input pins for breaker control (active high)
  bool openInputActive = digitalRead(openInput);   // Pin 45 - active when high
  bool closeInputActive = digitalRead(closeInput); // Pin 43 - active when high
  
  // Handle input pin control with pin 45 dominating, but ignore if locked
  if (!locked) {
    if (openInputActive) {
      // Pin 45 dominates - always open when active
      if (!breakerstate) {  // Only change if not already open
        set_breaker_state(true);
        Serial.println("Breaker OPENED via input pin 45");
      }
    } else if (closeInputActive && !openInputActive) {
      // Pin 43 active and pin 45 not active - close if switch allows
      if (switchToggled && breakerstate) {  // Only close if switch UP and currently open
        set_breaker_state(false);
        Serial.println("Breaker CLOSED via input pin 43");
      } else if (!switchToggled) {
        Serial.println("Close command from pin 43 REJECTED - switch is DOWN");
      }
    }
  }

  BLEDevice central = BLE.central();

  static bool lastBreakerState = true;
  static bool lastSwitchState = true;
  static bool lastLockedState = false;

  if (central) {
    bluetoothConnected = true;
    send_status_to_flutter(); // Send initial status

    while (central.connected()) {
      bool stateChanged = false;
      if (commandChar.written()) {
        if (commandChar.valueLength() >= 2) {
          uint8_t* data = (uint8_t*)commandChar.value();
          bool newBreakerState = data[0] == 1;
          bool newSwitchState = data[1] == 1;
          if (switchToggled != newSwitchState) {
            switchToggled = newSwitchState;
            if (switch_69) {
              if (switchToggled) {
                lv_obj_add_state(switch_69, LV_STATE_CHECKED);
              } else {
                lv_obj_clear_state(switch_69, LV_STATE_CHECKED);
              }
            }
            stateChanged = true;
          }
          if (!locked) {
            if (newBreakerState != breakerstate) {
              set_breaker_state(newBreakerState);
              stateChanged = true;
            }
          }
        } else {
          uint8_t cmd = commandChar.value()[0];
          if (!locked) {
            if ((cmd == 1 && !breakerstate) || (cmd == 0 && breakerstate && switchToggled)) {
              set_breaker_state(cmd == 1);
              stateChanged = true;
            }
          }
        }
      }
      if (lockChar.written()) {
        uint8_t lockValue = lockChar.value()[0];
        bool newLocked = (lockValue == 1);
        if (locked != newLocked) {
          locked = newLocked;
          update_lock_icon();
          update_button_styles();
          stateChanged = true;
        }
      }
      // Only send status if state changed
      if (stateChanged || breakerstate != lastBreakerState || switchToggled != lastSwitchState || locked != lastLockedState) {
        send_status_to_flutter();
        lastBreakerState = breakerstate;
        lastSwitchState = switchToggled;
        lastLockedState = locked;
      }
      set_leds();
      lv_timer_handler();
      delay(1);
    }
    bluetoothConnected = false;
    BLE.advertise(); // Restart advertising after disconnect
  }
  
  set_leds();
  lv_timer_handler();
  delay(1);
}

static void send_status_to_flutter() {
  if (bluetoothConnected && BLE.central() && BLE.central().connected()) {
    // Send status as bytes: [breaker_state, switch_state, lock_state]
    uint8_t status[3] = {
      breakerstate ? 1 : 0,
      switchToggled ? 1 : 0,
      locked ? 1 : 0
    };
    // Use statusChar for sending notifications to Flutter
    statusChar.writeValue(status, 3);
    // Also update lockChar for notification
    lockChar.writeValue(&status[2], 1);
    // Add a small delay to ensure proper notification delivery
    delay(10);
    Serial.print("📤 Sent status to Flutter - Breaker: ");
    Serial.print(breakerstate ? "OPEN" : "CLOSED");
    Serial.print(", Switch: ");
    Serial.print(switchToggled ? "UP" : "DOWN");
    Serial.print(", Lock: ");
    Serial.println(locked ? "LOCKED" : "UNLOCKED");
  } else {
    Serial.println("⚠️ Cannot send status - not connected to Flutter");
  }
}

static void set_leds() {
  if (breakerstate) {
    digitalWrite(greenled, LOW);
    digitalWrite(redled,   HIGH);
    digitalWrite(blueled,  HIGH);
  } else {
    digitalWrite(redled,   LOW);
    digitalWrite(greenled, HIGH);
    digitalWrite(blueled,  HIGH);
  }
}

static void set_breaker_state(bool open) {
  if (locked) {
    Serial.println("Breaker state change IGNORED - system is LOCKED");
    return;
  }
  bool previousState = breakerstate;
  breakerstate = open;
  // Execute output sequence if state actually changed
  if (previousState != breakerstate) {
    if (breakerstate) {
      // Breaker state changes from low to high (closed to open)
      delay(0);
      digitalWrite(pin39, LOW);
      delay(5);
      digitalWrite(pin41, LOW);
      digitalWrite(sense, LOW);   // LOW for open
    } else {
      // Breaker state changes from high to low (open to closed)
      delay(0);
      digitalWrite(pin41, HIGH);
      delay(0);
      digitalWrite(pin39, HIGH);
      digitalWrite(sense, HIGH);
    }
  }
  update_button_styles();
  set_leds();
  send_status_to_flutter(); // Send status update to Flutter
}

static void switch_toggled_cb(lv_event_t *e) {
  switchToggled = lv_obj_has_state(switch_69, LV_STATE_CHECKED);
  Serial.print("Switch toggled via touch to: ");
  Serial.println(switchToggled ? "UP" : "DOWN");
  // Safety rule: if switch goes DOWN, force breaker OPEN
  if (!switchToggled && !breakerstate) {
    set_breaker_state(true);  // Use set_breaker_state to update sense pin too
    Serial.println("Safety rule: Breaker forced OPEN due to switch DOWN");
  } else {
    // If switch toggled up, immediately update button styles so close button is enabled
    update_button_styles();
  }
  send_status_to_flutter(); // Send status update to Flutter
}

static void open_btn_cb(lv_event_t *e) {
  if (locked) {
    Serial.println("Open command IGNORED - system is LOCKED");
    return;
  }
  set_breaker_state(true);
  Serial.println("Breaker OPENED via touch");
}

static void close_btn_cb(lv_event_t *e) {
  if (locked) {
    Serial.println("Close command IGNORED - system is LOCKED");
    return;
  }
  // Close only allowed when switch UP and breaker OPEN
  if (switchToggled && breakerstate) {  // Only when UP and OPEN
    set_breaker_state(false);
    Serial.println("Breaker CLOSED via touch");
  } else {
    Serial.println("Close command REJECTED - safety rule or already closed");
  }
}

// ...existing code...
// ...existing code...

// Move all UI creation and styling into rotate_screen_cb
static void rotate_screen_cb(lv_event_t *e) {
  portraitMode = !portraitMode;
  lv_disp_set_rotation(NULL, portraitMode ? LV_DISPLAY_ROTATION_270 : LV_DISPLAY_ROTATION_0);

  if (ui_container) lv_obj_del(ui_container);
  // Reset all global UI pointers so new objects are created and old pointers are not reused
  btn_open = NULL;
  btn_close = NULL;
  open_btn_overlay = NULL;
  close_btn_overlay = NULL;
  lock_icon_btn = NULL;
  lock_icon_label = NULL;
  lock_container = NULL;
  switch_69 = NULL;
  switch_container = NULL;
  tight_container = NULL;
  ui_container = NULL;

  // Main container
  ui_container = lv_obj_create(lv_scr_act());
  lv_obj_set_size(ui_container, LV_PCT(100), LV_PCT(100));
  lv_obj_clear_flag(ui_container, LV_OBJ_FLAG_SCROLLABLE);

  switch_container = lv_obj_create(ui_container);
  lv_obj_set_size(switch_container, 280, 400);  // Increased from 200x300
  if (portraitMode) {
    //portrait
    lv_obj_align(switch_container, LV_ALIGN_LEFT_MID, 60, 0);
  } else {
    // landscape
    lv_obj_align(switch_container, LV_ALIGN_TOP_MID, 0, 100);
  }
  lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);
  lv_obj_set_style_border_width(switch_container, 5, 0);
  lv_obj_set_style_border_color(switch_container, lv_color_hex(0x000000), 0);
  lv_obj_set_flex_flow(switch_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(switch_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(switch_container, 10, 0);

  // UP label
  lv_obj_t *label_up = lv_label_create(switch_container);
  lv_label_set_text(label_up, "UP");
  lv_obj_set_style_text_color(label_up, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_up, &lv_font_montserrat_48, 0);

  // Middle container for switch and 69 label (horizontal layout)
  lv_obj_t *middle_container = lv_obj_create(switch_container);
  lv_obj_set_size(middle_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(middle_container, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(middle_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(middle_container, 0, 0);
  lv_obj_set_style_pad_column(middle_container, 15, 0);
  lv_obj_set_style_border_width(middle_container, 0, 0);
  lv_obj_set_style_bg_opa(middle_container, LV_OPA_TRANSP, 0);

  // 69 label to the left of switch
  lv_obj_t *label_69 = lv_label_create(middle_container);
  lv_label_set_text(label_69, "69");
  lv_obj_set_style_text_color(label_69, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_69, &lv_font_montserrat_48, 0);

  // 69 switch (rotated back to vertical orientation)
  switch_69 = lv_switch_create(middle_container);
  lv_obj_set_size(switch_69, 70, 140);  // Increased from 50x100
  lv_obj_add_event_cb(switch_69, switch_toggled_cb, LV_EVENT_VALUE_CHANGED, NULL);
  if (switchToggled) lv_obj_add_state(switch_69, LV_STATE_CHECKED);

  // DOWN label
  lv_obj_t *label_down = lv_label_create(switch_container);
  lv_label_set_text(label_down, "DOWN");
  lv_obj_set_style_text_color(label_down, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_down, &lv_font_montserrat_48, 0);

  // Button container for open/close
  tight_container = lv_obj_create(ui_container);
  lv_obj_set_size(tight_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(tight_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(tight_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(tight_container, 10, 0);
  lv_obj_set_style_pad_row(tight_container, 15, 0);
  lv_obj_set_style_border_width(tight_container, 0, 0);
  lv_obj_set_style_bg_opa(tight_container, LV_OPA_TRANSP, 0);

  // Lock button container (for independent positioning)
  lock_container = lv_obj_create(ui_container);
  lv_obj_set_size(lock_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_border_width(lock_container, 0, 0);
  lv_obj_set_style_bg_opa(lock_container, LV_OPA_TRANSP, 0);

 if (!portraitMode) {
    // Portrait
    lv_obj_align(tight_container, LV_ALIGN_BOTTOM_LEFT, 0, -10); 
    lv_obj_align(switch_container, LV_ALIGN_LEFT_MID, 90, -100); 
    lv_obj_align(lock_container, LV_ALIGN_BOTTOM_RIGHT, 0, -50);  
  } else {
    // Landscape
    lv_obj_align(tight_container, LV_ALIGN_BOTTOM_RIGHT, -100, -125);
    lv_obj_align(switch_container, LV_ALIGN_TOP_MID, -200, 30);
    lv_obj_align(lock_container, LV_ALIGN_BOTTOM_RIGHT, -170, 10); 
  }


  // Open button
  btn_open = lv_btn_create(tight_container);
  lv_obj_set_size(btn_open, 280, 100);  // Width matches switch container (280)
  lv_obj_set_style_border_width(btn_open, 3, 0);
  lv_obj_set_style_border_color(btn_open, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_open, open_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_open = lv_label_create(btn_open);
  lv_label_set_text(label_open, "OPEN");
  lv_obj_set_style_text_color(label_open, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_open, &lv_font_montserrat_48, 0);
  lv_obj_center(label_open);

  // Close button
  btn_close = lv_btn_create(tight_container);
  lv_obj_set_size(btn_close, 280, 100);
  lv_obj_set_style_border_width(btn_close, 3, 0);
  lv_obj_set_style_border_color(btn_close, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_close, close_btn_cb, LV_EVENT_CLICKED, NULL);

  lv_obj_t *label_close = lv_label_create(btn_close);
  lv_label_set_text(label_close, "CLOSE");
  lv_obj_set_style_text_color(label_close, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_close, &lv_font_montserrat_48, 0);
  lv_obj_center(label_close);

  // Create overlay for disabled state (circle slash symbol)
  close_btn_overlay = lv_obj_create(btn_close);
  lv_obj_set_size(close_btn_overlay, 280, 100);  // Updated to match new button size
  lv_obj_align(close_btn_overlay, LV_ALIGN_CENTER, 0, 0);
  lv_obj_set_style_bg_color(close_btn_overlay, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(close_btn_overlay, LV_OPA_40, 0); // 40% transparency
  lv_obj_set_style_radius(close_btn_overlay, 0, 0); // Squared edges to match button
  lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Initially hidden
  // Add prohibition symbol using overlapping characters
  // Create circle (O)
  lv_obj_t *circle_label = lv_label_create(close_btn_overlay);
  lv_label_set_text(circle_label, "O");
  lv_obj_set_style_text_color(circle_label, lv_color_hex(0xFF0000), 0);
  lv_obj_set_style_text_font(circle_label, &lv_font_montserrat_48, 0);
  lv_obj_center(circle_label);

  lv_obj_t *slash_label = lv_label_create(close_btn_overlay);
  lv_label_set_text(slash_label, "/");
  lv_obj_set_style_text_color(slash_label, lv_color_hex(0xFF0000), 0);
  lv_obj_set_style_text_font(slash_label, &lv_font_montserrat_48, 0);
  lv_obj_center(slash_label);

  // Create overlay for disabled state (lock symbol) for open button
  open_btn_overlay = lv_obj_create(btn_open);
  lv_obj_set_size(open_btn_overlay, 280, 100);
  lv_obj_align(open_btn_overlay, LV_ALIGN_CENTER, 0, 0);
  lv_obj_set_style_bg_color(open_btn_overlay, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(open_btn_overlay, LV_OPA_40, 0);
  lv_obj_set_style_radius(open_btn_overlay, 0, 0);
  lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN);
  // Add lock symbol using LVGL built-in symbol
  lv_obj_t *lock_label_open = lv_label_create(open_btn_overlay);
  lv_label_set_text(lock_label_open, LV_SYMBOL_LOCK);
  lv_obj_set_style_text_color(lock_label_open, lv_color_hex(0xAA0000), 0);
  lv_obj_set_style_text_font(lock_label_open, &lv_font_montserrat_48, 0);
  lv_obj_center(lock_label_open);

  // Lock icon button (long-press to toggle lock) - now in its own container
  lock_icon_btn = lv_btn_create(lock_container);
  lv_obj_set_size(lock_icon_btn, 120, 120);
  lv_obj_set_style_radius(lock_icon_btn, LV_RADIUS_CIRCLE, 0); // Make it a circle
  lv_obj_set_style_border_width(lock_icon_btn, 4, 0);
  lv_obj_set_style_border_color(lock_icon_btn, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(lock_icon_btn, lock_icon_event_cb, LV_EVENT_ALL, NULL);
  // Remove label, add image instead
  lv_obj_t *lock_img = lv_img_create(lock_icon_btn);
  lv_img_set_src(lock_img, &locked_icon);
  lv_obj_center(lock_img);
  update_lock_icon();

  // Rotate button (without container)
  lv_obj_t *btn_rotate = lv_btn_create(ui_container);
  lv_obj_set_size(btn_rotate, 180, 70);
  lv_obj_align(btn_rotate, LV_ALIGN_TOP_RIGHT, 0, 0);
  lv_obj_set_style_border_width(btn_rotate, 5, 0);
  lv_obj_set_style_border_color(btn_rotate, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_rotate, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_rotate = lv_label_create(btn_rotate);
  lv_label_set_text(label_rotate, "ROTATE");
  lv_obj_set_style_text_color(label_rotate, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_rotate, &lv_font_montserrat_38, 0);
  lv_obj_center(label_rotate);

  // Finalize UI
  update_button_styles();
  lv_refr_now(NULL);
}

static void update_button_styles() {
  if (!btn_open || !btn_close || !ui_container || !switch_container || !tight_container) return;
  // Defensive: overlays for open/close buttons must be created only once in rotate_screen_cb, never deleted or recreated in update_button_styles
  // Only update overlay content/state here, never create or delete overlays
  // Update background colors based on breaker state
  if (breakerstate) {
    // Breaker is OPEN - Green background
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0x00AA00), 0);      // Green background
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Always yellow
    lv_obj_set_style_bg_opa(switch_container, LV_OPA_COVER, 0);              // Fully opaque
    if (locked) {
      if (switch_69) lv_obj_add_state(switch_69, LV_STATE_DISABLED);
    } else {
      if (switch_69) lv_obj_clear_state(switch_69, LV_STATE_DISABLED);
    }
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x00AA00), 0);          // Green - active (same as background)
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x550000), 0);         // Dark red - inactive (matches Flutter)
  } else {
    // Breaker is CLOSED - Red background
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0xAA0000), 0);      // Red background
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Always yellow
    lv_obj_set_style_bg_opa(switch_container, LV_OPA_COVER, 0);              // Fully opaque
    if (locked) {
      if (switch_69) lv_obj_add_state(switch_69, LV_STATE_DISABLED);
    } else {
      if (switch_69) lv_obj_clear_state(switch_69, LV_STATE_DISABLED);
    }
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x005500), 0);          // Dark green - inactive (matches Flutter)
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0xAA0000), 0);         // Red - active (same as background)
  }
  // No overlay with 'L' for locked state over the switch or its container
  // Defensive: ensure overlays are not referenced or deleted if never created
  // (No static overlay objects for switch_69)
  // Defensive: ensure btn_open, btn_close, open_btn_overlay, close_btn_overlay are valid before use
  if (!btn_open || !btn_close || !open_btn_overlay || !close_btn_overlay) return;
  // Handle close button state based on switch position, but only if not locked
  if (!locked) {
    if (!switchToggled) {
      // Switch DOWN - disable close button (safety rule) and show prohibition overlay
      lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x330000), 0); // Very dark red
      lv_obj_add_state(btn_close, LV_STATE_DISABLED);
      lv_obj_clear_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Show prohibition overlay
      lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide open lock overlay
      // Set prohibition symbol on close_btn_overlay
      uint32_t child_cnt = lv_obj_get_child_cnt(close_btn_overlay);
      for (uint32_t i = 0; i < child_cnt; ++i) {
        lv_obj_t *child = lv_obj_get_child(close_btn_overlay, i);
        if (child) lv_label_set_text(child, i == 0 ? "O" : (i == 1 ? "/" : ""));
      }
    } else {
      lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
      lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide overlay when enabled
      lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide open lock overlay
    }
  }
  // Disable open/close buttons if locked, and show lock overlay on the appropriate button
  if (locked) {
    if (breakerstate) {
      // Locked in open: gray out close button with 'L' overlay
      lv_obj_add_state(btn_close, LV_STATE_DISABLED);
      lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x330000), 0);
      lv_obj_clear_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Show overlay
      lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide open overlay
      // Set 'L' on close_btn_overlay
      uint32_t child_cnt = lv_obj_get_child_cnt(close_btn_overlay);
      for (uint32_t i = 0; i < child_cnt; ++i) {
        lv_obj_t *child = lv_obj_get_child(close_btn_overlay, i);
        if (child) lv_label_set_text(child, i == 0 ? "L" : "");
      }
      // Enable open button
      lv_obj_clear_state(btn_open, LV_STATE_DISABLED);
    } else {
      // Locked in close: gray out open button with 'L' overlay
      lv_obj_add_state(btn_open, LV_STATE_DISABLED);
      lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x333300), 0);
      lv_obj_clear_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Show overlay
      lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide close overlay
      // Set 'L' on open_btn_overlay
      uint32_t child_cnt = lv_obj_get_child_cnt(open_btn_overlay);
      for (uint32_t i = 0; i < child_cnt; ++i) {
        lv_obj_t *child = lv_obj_get_child(open_btn_overlay, i);
        if (child) lv_label_set_text(child, i == 0 ? "L" : "");
      }
      // Enable close button
      lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
    }
  } else {
    // Not locked: ensure both overlays are hidden and both buttons are enabled (unless switch is down)
    lv_obj_clear_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_state(btn_open, LV_STATE_DISABLED);
    if (switchToggled) {
      lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
    }
  }
}
// Lock icon event callback (long-press to toggle lock)
static void lock_icon_event_cb(lv_event_t *e) {
  uint32_t code = lv_event_get_code(e);
  if (code == LV_EVENT_PRESSED) {
    lock_press_start = millis();
  } else if (code == LV_EVENT_PRESSING) {
    if (lock_press_start && (millis() - lock_press_start > 800)) { // 800ms long-press
      lock_press_start = 0;
      locked = !locked;
      update_lock_icon();
      update_button_styles();
      // Notify Flutter via BLE
      uint8_t lockValue = locked ? 1 : 0;
      lockChar.writeValue(&lockValue, 1);
      send_status_to_flutter();
      Serial.print("Lock toggled via UI: ");
      Serial.println(locked ? "LOCKED" : "UNLOCKED");
    }
  } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_CLICKED) {
    lock_press_start = 0;
  }
}

// Update lock icon appearance
static void update_lock_icon() {
  if (!lock_icon_btn) return;
  // Set background color only
  if (locked) {
    lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0xFF9800), 0); // Orange
  } else {
    lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0x1976D2), 0); // Blue
  }
}
