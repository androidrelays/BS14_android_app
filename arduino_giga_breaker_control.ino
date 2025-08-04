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
lv_obj_t *close_btn_overlay; // Overlay for disabled state symbol

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
  BLE.setLocalName("BS14");
  BLE.setDeviceName("BS14");
  
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
}

void loop() {
  // Check input pins for breaker control (active high)
  bool openInputActive = digitalRead(openInput);   // Pin 45 - active when high
  bool closeInputActive = digitalRead(closeInput); // Pin 43 - active when high
  
  // Handle input pin control with pin 45 dominating
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

  BLEDevice central = BLE.central();
  
  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());
    bluetoothConnected = true;
    
    // Send initial status when connected
    send_status_to_flutter();
    
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
          if (switchToggled != newSwitchState) {
            switchToggled = newSwitchState;
            // Update the UI switch to match
            if (switch_69) {
              if (switchToggled) {
                lv_obj_add_state(switch_69, LV_STATE_CHECKED);
              } else {
                lv_obj_clear_state(switch_69, LV_STATE_CHECKED);
              }
            }
            Serial.print("Switch updated to: ");
            Serial.println(switchToggled ? "UP" : "DOWN");
          }
          
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
      
      // Send periodic status updates every 5 seconds to ensure Flutter stays synchronized
      // Reduced frequency for better power efficiency
      unsigned long currentTime = millis();
      if (currentTime - lastStatusSent > 5000) {
        send_status_to_flutter();
        lastStatusSent = currentTime;
      }
      
      set_leds();
      lv_timer_handler();
      delay(1);
    }
    
    Serial.println("Disconnected from central");
    bluetoothConnected = false;
  }
  
  set_leds();
  lv_timer_handler();
  delay(1);
}

static void send_status_to_flutter() {
  if (bluetoothConnected && BLE.central() && BLE.central().connected()) {
    // Send status as bytes: [breaker_state, switch_state]
    uint8_t status[2] = {
      breakerstate ? 1 : 0,
      switchToggled ? 1 : 0
    };
    
    // Use statusChar for sending notifications to Flutter
    statusChar.writeValue(status, 2);
    
    // Add a small delay to ensure proper notification delivery
    delay(10);
    
    Serial.print("📤 Sent status to Flutter - Breaker: ");
    Serial.print(breakerstate ? "OPEN" : "CLOSED");
    Serial.print(", Switch: ");
    Serial.println(switchToggled ? "UP" : "DOWN");
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
  }
  
  update_button_styles();
  send_status_to_flutter(); // Send status update to Flutter
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

  // Switch container - positioned in upper area to leave room for buttons
  switch_container = lv_obj_create(ui_container);
  lv_obj_set_size(switch_container, 280, 400);  // Increased from 200x300
  if (portraitMode) {
    // Portrait: switch in left-center area
    lv_obj_align(switch_container, LV_ALIGN_LEFT_MID, 70, 60);
  } else {
    // Landscape: switch in upper half, moved left 20px
    lv_obj_align(switch_container, LV_ALIGN_TOP_MID, -20, 70);
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
  lv_obj_set_style_text_font(label_up, &lv_font_montserrat_48, 0);  // Increased from 44

  // 69 switch (rotated back to vertical orientation)
  switch_69 = lv_switch_create(switch_container);
  lv_obj_set_size(switch_69, 70, 140);  // Increased from 50x100
  lv_obj_add_event_cb(switch_69, switch_toggled_cb, LV_EVENT_VALUE_CHANGED, NULL);
  if (switchToggled) lv_obj_add_state(switch_69, LV_STATE_CHECKED);

  // 69 label below switch
  lv_obj_t *label_69 = lv_label_create(switch_container);
  lv_label_set_text(label_69, "69");
  lv_obj_set_style_text_color(label_69, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_69, &lv_font_montserrat_48, 0);  // Increased from 44

  // DOWN label
  lv_obj_t *label_down = lv_label_create(switch_container);
  lv_label_set_text(label_down, "DOWN");
  lv_obj_set_style_text_color(label_down, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_down, &lv_font_montserrat_48, 0);  // Increased from 44

  // Button container positioned based on orientation
  tight_container = lv_obj_create(ui_container);
  lv_obj_set_size(tight_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(tight_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(tight_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(tight_container, 10, 0);
  lv_obj_set_style_pad_row(tight_container, 15, 0);
  lv_obj_set_style_border_width(tight_container, 0, 0);
  lv_obj_set_style_bg_opa(tight_container, LV_OPA_TRANSP, 0);

  if (portraitMode) {
    // Portrait: buttons in right area, well to the right of switch, moved down
    lv_obj_align(tight_container, LV_ALIGN_RIGHT_MID, -30, 60);
  } else {
    // Landscape: buttons in bottom area, well below switch, moved left 20px
    lv_obj_align(tight_container, LV_ALIGN_BOTTOM_MID, -20, -30);
  }

  // Open button
  btn_open = lv_btn_create(tight_container);
  lv_obj_set_size(btn_open, 280, 100);  // Width matches switch container (280)
  lv_obj_set_style_border_width(btn_open, 3, 0);
  lv_obj_set_style_border_color(btn_open, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_open, open_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_open = lv_label_create(btn_open);
  lv_label_set_text(label_open, "Open");
  lv_obj_set_style_text_color(label_open, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_open, &lv_font_montserrat_48, 0);  // Increased from 44
  lv_obj_center(label_open);

  // Close button
  btn_close = lv_btn_create(tight_container);
  lv_obj_set_size(btn_close, 280, 100);  // Width matches switch container (280)
  lv_obj_set_style_border_width(btn_close, 3, 0);
  lv_obj_set_style_border_color(btn_close, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_close, close_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_close = lv_label_create(btn_close);
  lv_label_set_text(label_close, "Close");
  lv_obj_set_style_text_color(label_close, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_close, &lv_font_montserrat_48, 0);  // Increased from 44
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
  lv_obj_set_style_text_color(circle_label, lv_color_hex(0xFF0000), 0); // Red color
  lv_obj_set_style_text_font(circle_label, &lv_font_montserrat_48, 0); // Large font
  lv_obj_center(circle_label);
  
  // Create slash (/) positioned over the circle
  lv_obj_t *slash_label = lv_label_create(close_btn_overlay);
  lv_label_set_text(slash_label, "/");
  lv_obj_set_style_text_color(slash_label, lv_color_hex(0xFF0000), 0); // Red color
  lv_obj_set_style_text_font(slash_label, &lv_font_montserrat_48, 0); // Large font
  lv_obj_center(slash_label);

  // Rotate button (without container)
  lv_obj_t *btn_rotate = lv_btn_create(ui_container);
  lv_obj_set_size(btn_rotate, 160, 90);  // Increased from 145x75
  lv_obj_align(btn_rotate, LV_ALIGN_TOP_RIGHT, 0, 0);
  lv_obj_set_style_border_width(btn_rotate, 5, 0);
  lv_obj_set_style_border_color(btn_rotate, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_rotate, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_rotate = lv_label_create(btn_rotate);
  lv_label_set_text(label_rotate, "Rotate");
  lv_obj_set_style_text_color(label_rotate, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_rotate, &lv_font_montserrat_44, 0);  // Increased from 38
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
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Keep yellow switch container
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x00AA00), 0);          // Green - active (same as background)
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x550000), 0);         // Dark red - inactive (matches Flutter)
  } else {
    // Breaker is CLOSED - Red background
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0xAA0000), 0);      // Red background
    lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);  // Keep yellow switch container
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x005500), 0);          // Dark green - inactive (matches Flutter)
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0xAA0000), 0);         // Red - active (same as background)
  }
  
  // Use default LVGL switch colors - no custom styling needed
  
  // Handle close button state based on switch position
  if (!switchToggled) {
    // Switch DOWN - disable close button (safety rule) and show overlay
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x330000), 0); // Very dark red
    lv_obj_add_state(btn_close, LV_STATE_DISABLED);
    lv_obj_clear_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Show circle slash overlay
  } else {
    lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
    lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Hide overlay when enabled
  }
}
