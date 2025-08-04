#include <ArduinoBLE.h>
#include <Arduino_H7_Video.h>
#include <lvgl.h>
#include <font/lv_font.h>
#include "Arduino_GigaDisplayTouch.h"

// Bluetooth - Use custom UUIDs matching Flutter app expectations
BLEService breakerService("12345678-1234-1234-1234-123456789abc");
BLECharacteristic commandChar("87654321-4321-4321-4321-cba987654321", BLEWrite, 20);
BLECharacteristic statusChar("11111111-2222-3333-4444-555555555555", BLERead | BLENotify, 20);

// Hardware interfaces
Arduino_H7_Video Display;
Arduino_GigaDisplayTouch TouchDetector;

// UI objects
lv_obj_t *switch_69;
lv_obj_t *ui_container;
lv_obj_t *tight_container;
lv_obj_t *switch_container;
lv_obj_t *btn_open;
lv_obj_t *btn_close;

// LED pins (active-low RGB)
const int redled = 86;
const int greenled = 87;
const int blueled = 88;

// State variables
bool switchToggled = true;
bool portraitMode  = false;
bool breakerstate  = true; // true = Open (green), false = Closed (red)
bool bluetoothConnected = false;

// Function declarations
static void set_leds();
static void set_breaker_state(bool open);
static void open_btn_cb(lv_event_t *e);
static void close_btn_cb(lv_event_t *e);
static void switch_toggled_cb(lv_event_t *e);
static void update_button_styles();
static void rotate_screen_cb(lv_event_t *e);
static void send_status_to_flutter();

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
  BLE.setLocalName("GIGA_Breaker_69");
  BLE.setDeviceName("GIGA_Breaker_69");
  
  // Configure advertising with both characteristics
  BLE.setAdvertisedService(breakerService);
  breakerService.addCharacteristic(commandChar);
  breakerService.addCharacteristic(statusChar);
  BLE.addService(breakerService);
  
  // Set advertising parameters for maximum discoverability
  BLE.setAdvertisingInterval(100); // Faster advertising - 62.5ms intervals
  BLE.setConnectable(true);
  
  // Start advertising with discoverability
  BLE.advertise();
  Serial.println("==============================");
  Serial.println("BLE DEVICE READY");
  Serial.println("==============================");
  Serial.println("Device name: GIGA_Breaker_69");
  Serial.print("Service UUID: ");
  Serial.println("12345678-1234-1234-1234-123456789abc");
  Serial.print("Command UUID: ");
  Serial.println("87654321-4321-4321-4321-cba987654321");
  Serial.print("Status UUID: ");
  Serial.println("11111111-2222-3333-4444-555555555555");
  Serial.println("Device should now be discoverable");
  Serial.println("Check your phone's Bluetooth settings!");
  Serial.println("==============================");

  pinMode(redled,   OUTPUT);
  pinMode(greenled, OUTPUT);
  pinMode(blueled,  OUTPUT);

  // Turn all LEDs off (HIGH = off for active-low)
  digitalWrite(redled,   HIGH);
  digitalWrite(greenled, HIGH);
  digitalWrite(blueled,  HIGH);

  breakerstate = true;
  set_leds();
  rotate_screen_cb(NULL); // Build UI
}

void loop() {
  BLEDevice central = BLE.central();
  
  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());
    bluetoothConnected = true;
    
    while (central.connected()) {
      if (commandChar.written()) {
        // Check if we received the expected 2-byte command from Flutter
        if (commandChar.valueLength() >= 2) {
          uint8_t* data = (uint8_t*)commandChar.value();
          bool newBreakerState = data[0] == 1;    // Breaker state (1=open, 0=closed)
          bool newSwitchState = data[1] == 1;     // Switch state (1=up, 0=down)
          
          Serial.print("Received command - Breaker: ");
          Serial.print(newBreakerState ? "OPEN" : "CLOSED");
          Serial.print(", Switch: ");
          Serial.println(newSwitchState ? "UP" : "DOWN");
          
          // Update switch state (always allowed)
          switchToggled = newSwitchState;
          
          // Apply breaker state with safety logic
          if (newBreakerState) {
            // Always allow opening
            set_breaker_state(true);
            Serial.println("Breaker OPENED via Bluetooth");
          } else {
            // Only allow closing if switch is UP
            if (switchToggled) {
              set_breaker_state(false);
              Serial.println("Breaker CLOSED via Bluetooth");
            } else {
              Serial.println("Close command REJECTED - switch is DOWN");
              // Send rejection status
              send_status_to_flutter();
            }
          }
        } else {
          // Handle single byte command for backward compatibility
          uint8_t cmd = commandChar.value()[0];
          Serial.print("Received single byte command: ");
          Serial.println(cmd);
          
          if (cmd == 1) {
            // Open command - always allowed
            set_breaker_state(true);
            Serial.println("Breaker OPENED via Bluetooth");
          } else if (cmd == 0) {
            // Close command - only allowed if switch is UP
            if (switchToggled) {
              set_breaker_state(false);
              Serial.println("Breaker CLOSED via Bluetooth");
            } else {
              Serial.println("Close command REJECTED - switch is DOWN");
              // Send rejection status
              send_status_to_flutter();
            }
          }
        }
      }
      
      set_leds();
      lv_timer_handler();
      delay(5);
    }
    
    Serial.println("Disconnected from central");
    bluetoothConnected = false;
  }
  
  set_leds();
  lv_timer_handler();
  delay(5);
}

static void send_status_to_flutter() {
  if (bluetoothConnected) {
    // Send status as bytes: [breaker_state, switch_state]
    uint8_t status[2] = {
      breakerstate ? 1 : 0,
      switchToggled ? 1 : 0
    };
    statusChar.setValue(status, 2);
    statusChar.notify();
    Serial.print("Status sent to Flutter: Breaker=");
    Serial.print(breakerstate ? "OPEN" : "CLOSED");
    Serial.print(", Switch=");
    Serial.println(switchToggled ? "UP" : "DOWN");
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
  breakerstate = open;
  update_button_styles();
  set_leds();
  send_status_to_flutter(); // Send status update to Flutter
}

static void switch_toggled_cb(lv_event_t *e) {
  switchToggled = lv_obj_has_state(switch_69, LV_STATE_CHECKED);
  
  // Safety rule: if switch goes DOWN, force breaker OPEN
  if (!switchToggled && !breakerstate) {
    breakerstate = true;  // Force open when switch DOWN
    update_button_styles();
    set_leds();
    send_status_to_flutter();
    Serial.println("Safety rule: Breaker forced OPEN due to switch DOWN");
  }
  
  update_button_styles();
  send_status_to_flutter();
}

static void open_btn_cb(lv_event_t *e) {
  // Always allow opening
  set_breaker_state(true);
  Serial.println("Breaker OPENED via touch");
}

static void close_btn_cb(lv_event_t *e) {
  // Close only allowed when switch UP and breaker OPEN
  if (switchToggled && breakerstate) {  // Only when UP and OPEN
    set_breaker_state(false);
    Serial.println("Breaker CLOSED via touch");
  } else {
    Serial.println("Close command REJECTED - safety rule or already closed");
  }
}

static void rotate_screen_cb(lv_event_t *e) {
  portraitMode = !portraitMode;
  lv_disp_set_rotation(NULL, portraitMode ? LV_DISPLAY_ROTATION_270 : LV_DISPLAY_ROTATION_0);

  if (ui_container) lv_obj_del(ui_container);

  // Main container
  ui_container = lv_obj_create(lv_scr_act());
  lv_obj_set_size(ui_container, LV_PCT(100), LV_PCT(100));
  lv_obj_clear_flag(ui_container, LV_OBJ_FLAG_SCROLLABLE);

  // Inner tight container
  tight_container = lv_obj_create(ui_container);
  lv_obj_set_size(tight_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(tight_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(tight_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(tight_container, 20, 0);
  lv_obj_set_style_border_width(tight_container, 0, 0);
  lv_obj_set_style_border_opa(tight_container, LV_OPA_TRANSP, 0);
  lv_obj_center(tight_container);

  // Permissive switch container
  switch_container = lv_obj_create(tight_container);
  lv_obj_clear_flag(switch_container, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_scrollbar_mode(switch_container, LV_SCROLLBAR_MODE_OFF);
  lv_obj_set_size(switch_container, 200, 300);
  lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);
  lv_obj_set_style_bg_opa(switch_container, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(switch_container, 5, 0);
  lv_obj_set_style_border_color(switch_container, lv_color_hex(0x000000), 0);
  lv_obj_set_flex_flow(switch_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(switch_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(switch_container, 10, 0);

  // UP label
  lv_obj_t *label_up = lv_label_create(switch_container);
  lv_label_set_text(label_up, "UP");
  lv_obj_set_style_text_color(label_up, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_up, &lv_font_montserrat_44, 0);

  // Row for 69 switch
  lv_obj_t *row = lv_obj_create(switch_container);
  lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_style_bg_opa(row, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(row, 0, 0);
  lv_obj_set_style_border_opa(row, LV_OPA_TRANSP, 0);
  lv_obj_set_size(row, 180, 140);
  lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_column(row, 0, 0);
  lv_obj_set_style_margin_right(row, 40, 0);

  // '69' label
  lv_obj_t *label_69 = lv_label_create(row);
  lv_label_set_text(label_69, "69");
  lv_obj_set_style_text_color(label_69, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_69, &lv_font_montserrat_44, 0);
  lv_obj_set_style_pad_all(label_69, 5, 0);
  lv_obj_set_style_pad_right(label_69, 35, 0);

  // Switch itself
  switch_69 = lv_switch_create(row);
  lv_obj_set_style_bg_color(switch_69, lv_color_hex(0x808080), LV_PART_MAIN);
  lv_obj_set_style_bg_opa(switch_69, LV_OPA_COVER, LV_PART_MAIN);
  lv_obj_set_size(switch_69, 60, 120);
  lv_obj_add_event_cb(switch_69, switch_toggled_cb, LV_EVENT_VALUE_CHANGED, NULL);
  if (switchToggled) lv_obj_add_state(switch_69, LV_STATE_CHECKED);

  // DOWN label
  lv_obj_t *label_down = lv_label_create(switch_container);
  lv_label_set_text(label_down, "DOWN");
  lv_obj_set_style_text_color(label_down, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_down, &lv_font_montserrat_44, 0);

  // Button row container
  lv_obj_t *button_row = lv_obj_create(tight_container);
  lv_obj_set_size(button_row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(button_row, LV_FLEX_FLOW_ROW);
  lv_obj_set_style_bg_color(button_row, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(button_row, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(button_row, 5, 0);
  lv_obj_set_style_border_color(button_row, lv_color_hex(0x000000), 0);
  lv_obj_set_style_border_opa(button_row, LV_OPA_COVER, 0);

  // Open button
  btn_open = lv_btn_create(button_row);
  lv_obj_set_size(btn_open, 180, 90);
  lv_obj_add_event_cb(btn_open, open_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_open = lv_label_create(btn_open);
  lv_label_set_text(label_open, "Open");
  lv_obj_set_style_text_color(label_open, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_open, &lv_font_montserrat_44, 0);
  lv_obj_center(label_open);

  // Close button
  btn_close = lv_btn_create(button_row);
  lv_obj_set_size(btn_close, 180, 90);
  lv_obj_add_event_cb(btn_close, close_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_close = lv_label_create(btn_close);
  lv_label_set_text(label_close, "Close");
  lv_obj_set_style_text_color(label_close, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_close, &lv_font_montserrat_44, 0);
  lv_obj_center(label_close);

  // Rotate button container
  lv_obj_t *rotate_container = lv_obj_create(ui_container);
  lv_obj_set_size(rotate_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_align(rotate_container, LV_ALIGN_TOP_RIGHT, 0, 0);
  lv_obj_set_flex_flow(rotate_container, LV_FLEX_FLOW_ROW);
  lv_obj_set_style_pad_all(rotate_container, 0, 0);
  lv_obj_set_style_bg_color(rotate_container, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(rotate_container, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(rotate_container, 5, 0);
  lv_obj_set_style_border_color(rotate_container, lv_color_hex(0x000000), 0);
  lv_obj_set_style_border_opa(rotate_container, LV_OPA_COVER, 0);

  lv_obj_t *btn_rotate = lv_btn_create(rotate_container);
  lv_obj_set_size(btn_rotate, 135, 75);
  lv_obj_add_event_cb(btn_rotate, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_rotate = lv_label_create(btn_rotate);
  lv_label_set_text(label_rotate, "Rotate");
  lv_obj_set_style_text_color(label_rotate, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_rotate, &lv_font_montserrat_38, 0);
  lv_obj_center(label_rotate);

  // Finalize UI
  update_button_styles();
  lv_refr_now(NULL);
}

static void update_button_styles() {
  if (!btn_open || !btn_close || !ui_container || !switch_container || !tight_container) return;
  
  // Update background colors based on breaker state
  if (breakerstate) {
    // Breaker is OPEN - Green background
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0x00AA00), 0);      // Green background
    lv_obj_set_style_bg_color(tight_container, lv_color_hex(0x00AA00), 0);   // Match main container
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Keep yellow switch container
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x00AA00), 0);          // Green - active
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x555555), 0);         // Gray - inactive
  } else {
    // Breaker is CLOSED - Red background
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0xAA0000), 0);      // Red background
    lv_obj_set_style_bg_color(tight_container, lv_color_hex(0xAA0000), 0);   // Match main container
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Keep yellow switch container
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x555555), 0);          // Gray - inactive
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0xAA0000), 0);         // Red - active
  }
  
  // Handle close button state based on switch position
  if (!switchToggled) {
    // Switch DOWN - disable close button (safety rule)
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x330000), 0); // Very dark red
    lv_obj_add_state(btn_close, LV_STATE_DISABLED);
  } else {
    lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
  }
}
