//lvgl 8.x for ESP32
// ESP32 native BLE library (not ArduinoBLE)
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <lvgl.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include <SPI.h>

// Display and touch setup for Waveshare ESP32-S3 4 inch
TFT_eSPI tft = TFT_eSPI();
#define XPT2046_IRQ 36
#define XPT2046_MOSI 32
#define XPT2046_MISO 39
#define XPT2046_CLK 25
#define XPT2046_CS 33
SPIClass touchSPI = SPIClass(VSPI);
XPT2046_Touchscreen ts(XPT2046_CS, XPT2046_IRQ);

// Display buffer for LVGL
static const uint32_t screenWidth = 480;
static const uint32_t screenHeight = 320;
static lv_disp_draw_buf_t draw_buf;
static lv_color_t buf[screenWidth * 10];

// Bluetooth - Use custom UUIDs matching Flutter app expectations
BLEServer* pServer = NULL;
BLECharacteristic* commandChar = NULL;
BLECharacteristic* statusChar = NULL;
BLECharacteristic* lockChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define COMMAND_CHAR_UUID   "87654321-4321-4321-4321-cba987654321"
#define STATUS_CHAR_UUID    "11011111-2222-3333-4444-555555555555"
#define LOCK_CHAR_UUID      "22222222-3333-4444-5555-666666666666"

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
lv_obj_t *open_btn_overlay;  // Overlay for disabled state symbol on open button
lv_obj_t *lock_icon_btn = NULL;   // Lock icon button
lv_obj_t *lock_icon_label = NULL; // Lock icon label
lv_obj_t *lock_container = NULL;  // Container for lock button

// LED pins (ESP32-S3 built-in LED or external RGB)
const int redled = 48;    // Adjust these pins based on your ESP32-S3 board
const int greenled = 47;
const int blueled = 21;

// Breaker control pins - adjust for ESP32-S3 GPIO
const int sense = 4;
const int pin39 = 5;
const int pin41 = 6;
const int openInput = 7;
const int closeInput = 15;

// State variables
bool breakerstate = true;
bool locked = false;
bool switchToggled = true;
unsigned long lock_press_start = 0;

bool bluetoothConnected = false;
unsigned long lastStatusSent = 0;

// Rotation state
int currentRotation = 0;

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
static void create_ui();

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      bluetoothConnected = true;
      Serial.println("BLE Client Connected");
      update_button_styles();
      update_lock_icon();
      set_leds();
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      bluetoothConnected = false;
      Serial.println("BLE Client Disconnected");
      update_button_styles();
      update_lock_icon();
      set_leds();
      delay(500); // give the bluetooth stack the chance to get things ready
      pServer->startAdvertising(); // restart advertising
    }
};

// BLE Characteristic Callbacks
class MyCommandCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue(); // ESP32 BLE returns String, not std::string
      if (value.length() >= 3) {
        bool newBreakerState = value[0] == 1;
        bool newSwitchState  = value[1] == 1;
        bool newLockState    = value[2] == 1;

        bool stateChanged = false;

        if (locked != newLockState) {
          locked = newLockState;
          uint8_t val = locked ? 1 : 0;
          lockChar->setValue(&val, 1);
          lockChar->notify();
          update_lock_icon();
          update_button_styles();
          stateChanged = true;
        }

        if (switchToggled != newSwitchState) {
          switchToggled = newSwitchState;
          if (switch_69) {
            if (switchToggled) lv_obj_add_state(switch_69, LV_STATE_CHECKED);
            else lv_obj_clear_state(switch_69, LV_STATE_CHECKED);
          }
          stateChanged = true;
        }

        if (!locked && newBreakerState != breakerstate) {
          set_breaker_state(newBreakerState);
          stateChanged = true;
        }

        if (stateChanged) {
          send_status_to_flutter();
          set_leds();
        }
      }
    }
};

class MyLockCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue(); // ESP32 BLE returns String, not std::string
      if (value.length() >= 1) {
        uint8_t newVal = value[0];
        if (locked != (newVal == 1)) {
          locked = (newVal == 1);
          update_lock_icon();
          update_button_styles();
          send_status_to_flutter();
        }
      }
    }
};

// LVGL display driver
void my_disp_flush(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *color_p) {
  uint32_t w = (area->x2 - area->x1 + 1);
  uint32_t h = (area->y2 - area->y1 + 1);

  tft.startWrite();
  tft.setAddrWindow(area->x1, area->y1, w, h);
  tft.pushColors((uint16_t*)&color_p->full, w * h, true);
  tft.endWrite();

  lv_disp_flush_ready(disp);
}

// LVGL touch driver
void my_touchpad_read(lv_indev_drv_t *indev_driver, lv_indev_data_t *data) {
  if(ts.touched()) {
    TS_Point p = ts.getPoint();
    
    // Map touch coordinates to screen coordinates
    data->point.x = map(p.x, 200, 3700, 0, screenWidth);
    data->point.y = map(p.y, 240, 3800, 0, screenHeight);
    data->state = LV_INDEV_STATE_PR;
  } else {
    data->state = LV_INDEV_STATE_REL;
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("=== ESP32-S3 BS14 STARTING ===");

  // Initialize display
  tft.init();
  tft.setRotation(1); // Landscape mode
  tft.fillScreen(TFT_BLACK);

  // Initialize touch
  touchSPI.begin(XPT2046_CLK, XPT2046_MISO, XPT2046_MOSI, XPT2046_CS);
  ts.begin(touchSPI);
  ts.setRotation(1);

  // Initialize LVGL
  lv_init();

  // Initialize the display buffer
  lv_disp_draw_buf_init(&draw_buf, buf, NULL, screenWidth * 10);

  // Initialize the display driver
  static lv_disp_drv_t disp_drv;
  lv_disp_drv_init(&disp_drv);
  disp_drv.hor_res = screenWidth;
  disp_drv.ver_res = screenHeight;
  disp_drv.flush_cb = my_disp_flush;
  disp_drv.draw_buf = &draw_buf;
  lv_disp_drv_register(&disp_drv);

  // Initialize the input device driver
  static lv_indev_drv_t indev_drv;
  lv_indev_drv_init(&indev_drv);
  indev_drv.type = LV_INDEV_TYPE_POINTER;
  indev_drv.read_cb = my_touchpad_read;
  lv_indev_drv_register(&indev_drv);

  // Initialize BLE
  BLEDevice::init("BS14-ESP32");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  commandChar = pService->createCharacteristic(
                      COMMAND_CHAR_UUID,
                      BLECharacteristic::PROPERTY_WRITE
                    );
  commandChar->setCallbacks(new MyCommandCallbacks());

  statusChar = pService->createCharacteristic(
                      STATUS_CHAR_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  statusChar->addDescriptor(new BLE2902());

  lockChar = pService->createCharacteristic(
                      LOCK_CHAR_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  lockChar->addDescriptor(new BLE2902());
  lockChar->setCallbacks(new MyLockCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();

  // Initialize GPIO pins
  pinMode(redled, OUTPUT);
  pinMode(greenled, OUTPUT);
  pinMode(blueled, OUTPUT);
  pinMode(sense, OUTPUT);
  pinMode(pin39, OUTPUT);
  pinMode(pin41, OUTPUT);
  pinMode(openInput, INPUT_PULLUP);
  pinMode(closeInput, INPUT_PULLUP);

  digitalWrite(redled, HIGH);
  digitalWrite(greenled, HIGH);
  digitalWrite(blueled, HIGH);

  digitalWrite(pin39, LOW);
  digitalWrite(pin41, LOW);

  breakerstate = true;
  digitalWrite(sense, LOW);

  set_leds();

  // Set initial rotation
  currentRotation = 0;
  lv_disp_t *disp = lv_disp_get_default();
  lv_disp_set_rotation(disp, LV_DISP_ROT_NONE);

  create_ui();
  update_lock_icon();

  Serial.println("ESP32-S3 BS14 Ready");
}

void loop() {
  lv_tick_inc(5); // Tell LVGL how much time has passed
  lv_timer_handler();
  
  // Handle BLE reconnection
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // give the bluetooth stack the chance to get things ready
    pServer->startAdvertising(); // restart advertising
    Serial.println("Start advertising");
    oldDeviceConnected = deviceConnected;
  }
  
  // Handle BLE connection
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Hardware inputs when not locked and not connected via BLE
  if (!bluetoothConnected) {
    bool openInputActive  = !digitalRead(openInput);  // Inverted for pullup
    bool closeInputActive = !digitalRead(closeInput); // Inverted for pullup

    if (!locked) {
      if (openInputActive && !breakerstate) {
        set_breaker_state(true);
      } else if (closeInputActive && !openInputActive && switchToggled && breakerstate) {
        set_breaker_state(false);
      }
    }
  }

  delay(5);
}

// ---------------- helper functions ----------------

static void send_status_to_flutter() {
  if (bluetoothConnected && deviceConnected && statusChar) {
    uint8_t status[3] = {
      breakerstate ? 1 : 0,
      switchToggled ? 1 : 0,
      locked ? 1 : 0
    };
    statusChar->setValue(status, 3);
    statusChar->notify();
  }
}

static void set_leds() {
  if (breakerstate) {
    digitalWrite(greenled, LOW);
    digitalWrite(redled, HIGH);
    digitalWrite(blueled, HIGH);
  } else {
    digitalWrite(redled, LOW);
    digitalWrite(greenled, HIGH);
    digitalWrite(blueled, HIGH);
  }
}

static void set_breaker_state(bool open) {
  if (locked) return;
  bool previousState = breakerstate;
  breakerstate = open;
  if (previousState != breakerstate) {
    if (breakerstate) {
      digitalWrite(pin39, LOW);
      delay(5);
      digitalWrite(pin41, LOW);
      digitalWrite(sense, LOW);
    } else {
      digitalWrite(pin41, HIGH);
      digitalWrite(pin39, HIGH);
      digitalWrite(sense, HIGH);
    }
  }
  update_button_styles();
  set_leds();
}

static void switch_toggled_cb(lv_event_t *e) {
  switchToggled = lv_obj_has_state(switch_69, LV_STATE_CHECKED);
  if (!switchToggled && !breakerstate) {
    set_breaker_state(true);
  } else {
    update_button_styles();
  }
  if (bluetoothConnected) send_status_to_flutter();
}

static void open_btn_cb(lv_event_t *e) {
  if (locked) return;
  set_breaker_state(true);
  if (bluetoothConnected) send_status_to_flutter();
}

static void close_btn_cb(lv_event_t *e) {
  if (locked) return;
  if (switchToggled && breakerstate) {
    set_breaker_state(false);
    if (bluetoothConnected) send_status_to_flutter();
  }
}

static void rotate_screen_cb(lv_event_t *e) {
  static unsigned long lastRotationTime = 0;
  unsigned long currentTime = millis();
  if (currentTime - lastRotationTime < 500) return;
  lastRotationTime = currentTime;

  currentRotation = (currentRotation + 90) % 360;
  lv_disp_t *disp = lv_disp_get_default();

  switch (currentRotation) {
    case 0:   
      lv_disp_set_rotation(disp, LV_DISP_ROT_NONE); 
      tft.setRotation(1);
      ts.setRotation(1);
      break;
    case 90:  
      lv_disp_set_rotation(disp, LV_DISP_ROT_90);   
      tft.setRotation(2);
      ts.setRotation(2);
      break;
    case 180: 
      lv_disp_set_rotation(disp, LV_DISP_ROT_180);  
      tft.setRotation(3);
      ts.setRotation(3);
      break;
    case 270: 
      lv_disp_set_rotation(disp, LV_DISP_ROT_270);  
      tft.setRotation(0);
      ts.setRotation(0);
      break;
  }
  lv_refr_now(disp);
}

static void lock_icon_event_cb(lv_event_t *e) {
  uint32_t code = lv_event_get_code(e);
  static bool lock_feedback_given = false;
  
  if (code == LV_EVENT_PRESSED) {
    lock_press_start = millis();
    lock_feedback_given = false;
    Serial.println("Lock button press started - hold for 600ms");
    
    // Immediate visual feedback - slightly darken the button
    if (locked) {
      lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0xE68900), 0); // Darker orange
    } else {
      lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0x1565C0), 0); // Darker blue
    }
    
  } else if (code == LV_EVENT_PRESSING) {
    if (lock_press_start) {
      unsigned long elapsed = millis() - lock_press_start;
      
      // Provide feedback at halfway point (300ms)
      if (!lock_feedback_given && elapsed > 300) {
        lock_feedback_given = true;
        Serial.println("Lock button halfway - continue holding...");
        // Brief visual pulse by changing color momentarily
        if (locked) {
          lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0xFFB74D), 0); // Lighter orange pulse
        } else {
          lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0x42A5F5), 0); // Lighter blue pulse
        }
        lv_timer_handler(); // Force immediate update
        delay(50); // Brief pulse
        // Return to pressed state color
        if (locked) {
          lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0xE68900), 0);
        } else {
          lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0x1565C0), 0);
        }
      }
      
      // Trigger lock toggle at 600ms (reduced from 800ms for better responsiveness)
      if (elapsed > 600) {
        lock_press_start = 0;
        locked = !locked;
        Serial.print("Lock button activated - locked: ");
        Serial.println(locked);

        // sync with BLE
        uint8_t val = locked ? 1 : 0;
        if (lockChar) {
          lockChar->setValue(&val, 1);
          lockChar->notify();
        }

        update_lock_icon();
        update_button_styles();
        if (bluetoothConnected) send_status_to_flutter();
        
        // Brief confirmation feedback
        delay(100);
      }
    }
    
  } else if (code == LV_EVENT_RELEASED) {
    if (lock_press_start) {
      unsigned long elapsed = millis() - lock_press_start;
      Serial.print("Lock button released early after ");
      Serial.print(elapsed);
      Serial.println("ms - lock not toggled");
    }
    lock_press_start = 0;
    lock_feedback_given = false;
    
    // Restore normal button appearance
    update_lock_icon();
  }
}

static void update_lock_icon() {
  if (!lock_icon_label || !lock_icon_btn) return;
  if (locked) {
    lv_label_set_text(lock_icon_label, "LOCKED");
    lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0xFF9800), 0);
  } else {
    lv_label_set_text(lock_icon_label, "UNLOCKED");
    lv_obj_set_style_bg_color(lock_icon_btn, lv_color_hex(0x1976D2), 0);
  }
}

static void update_button_styles() {
  if (!btn_open || !btn_close || !ui_container || !switch_container || !tight_container || !switch_69) return;
  
  // Update background color based on breaker state
  if (breakerstate) {
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0x00AA00), 0); // Green for open
  } else {
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0xAA0000), 0); // Red for closed
  }
  
  // Always clear disabled state and overlays first
  lv_obj_clear_state(btn_open, LV_STATE_DISABLED);
  lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
  lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN);
  lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);

  if (locked) {
    // Locked: both open and close buttons should be disabled (grayed out)
    lv_obj_add_state(btn_open, LV_STATE_DISABLED);
    lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x333300), 0);
    lv_obj_add_state(btn_close, LV_STATE_DISABLED);
    lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x330000), 0);
    // Disable switch if locked
    lv_obj_add_state(switch_69, LV_STATE_DISABLED);
  } else {
    // Not locked: ensure switch is enabled
    lv_obj_clear_state(switch_69, LV_STATE_DISABLED);
    // Update close button state based on switchToggled and breakerstate
    if (breakerstate) {
      // Breaker is OPEN
      lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x00AA00), 0);
      if (!switchToggled) {
        // Switch DOWN - disable close button (safety rule)
        lv_obj_set_style_bg_color(btn_close, lv_color_hex(0x220000), 0);
        lv_obj_add_state(btn_close, LV_STATE_DISABLED);
        lv_obj_clear_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN); // Show prohibition overlay
      } else {
        // Switch UP - ensure close button is enabled
        lv_obj_set_style_bg_color(btn_close, lv_color_hex(0xFF6666), 0); // Lighter red
        lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
        lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);
      }
    } else {
      // Breaker is CLOSED
      lv_obj_set_style_bg_color(btn_open, lv_color_hex(0x005500), 0);
      lv_obj_set_style_bg_color(btn_close, lv_color_hex(0xAA0000), 0);
      // Always enable close button when breaker is closed
      lv_obj_clear_state(btn_close, LV_STATE_DISABLED);
      lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);
    }
  }
}

// Create UI function - called once at startup
static void create_ui() {
  // Main container
  ui_container = lv_obj_create(lv_scr_act());
  lv_obj_set_size(ui_container, LV_PCT(100), LV_PCT(100));
  // Set initial background color based on breaker state
  if (breakerstate) {
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0x00AA00), 0); // Green for open
  } else {
    lv_obj_set_style_bg_color(ui_container, lv_color_hex(0xAA0000), 0); // Red for closed
  }
  lv_obj_clear_flag(ui_container, LV_OBJ_FLAG_SCROLLABLE);

  // Switch container - adjusted for 4 inch display
  switch_container = lv_obj_create(ui_container);
  lv_obj_set_size(switch_container, 200, 250);
  lv_obj_align(switch_container, LV_ALIGN_TOP_MID, 0, 60);
  lv_obj_set_style_bg_color(switch_container, lv_color_hex(0xFFFF00), 0);
  lv_obj_set_style_border_width(switch_container, 3, 0);
  lv_obj_set_style_border_color(switch_container, lv_color_hex(0x000000), 0);
  lv_obj_set_flex_flow(switch_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(switch_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(switch_container, 8, 0);

  // UP label
  lv_obj_t *label_up = lv_label_create(switch_container);
  lv_label_set_text(label_up, "UP");
  lv_obj_set_style_text_color(label_up, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_up, &lv_font_montserrat_32, 0);

  // Middle container for switch and 69 label (horizontal layout)
  lv_obj_t *middle_container = lv_obj_create(switch_container);
  lv_obj_set_size(middle_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(middle_container, LV_FLEX_FLOW_ROW);
  lv_obj_set_flex_align(middle_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(middle_container, 0, 0);
  lv_obj_set_style_pad_column(middle_container, 10, 0);
  lv_obj_set_style_border_width(middle_container, 0, 0);
  lv_obj_set_style_bg_opa(middle_container, LV_OPA_TRANSP, 0);

  // 69 label to the left of switch
  lv_obj_t *label_69 = lv_label_create(middle_container);
  lv_label_set_text(label_69, "69");
  lv_obj_set_style_text_color(label_69, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_69, &lv_font_montserrat_32, 0);

  // 69 switch
  switch_69 = lv_switch_create(middle_container);
  lv_obj_add_event_cb(switch_69, switch_toggled_cb, LV_EVENT_VALUE_CHANGED, NULL);
  if (switchToggled) lv_obj_add_state(switch_69, LV_STATE_CHECKED);
  // Disable switch if locked
  if (locked) lv_obj_add_state(switch_69, LV_STATE_DISABLED);

  // DOWN label
  lv_obj_t *label_down = lv_label_create(switch_container);
  lv_label_set_text(label_down, "DOWN");
  lv_obj_set_style_text_color(label_down, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_down, &lv_font_montserrat_32, 0);

  // Button container for open/close - adjusted for 4 inch display
  tight_container = lv_obj_create(ui_container);
  lv_obj_set_size(tight_container, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_flex_flow(tight_container, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_flex_align(tight_container, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
  lv_obj_set_style_pad_all(tight_container, 8, 0);
  lv_obj_set_style_pad_row(tight_container, 10, 0);
  lv_obj_set_style_border_width(tight_container, 0, 0);
  lv_obj_set_style_bg_opa(tight_container, LV_OPA_TRANSP, 0);
  lv_obj_align(tight_container, LV_ALIGN_BOTTOM_MID, 0, 5);

  // Open button - smaller for 4 inch display
  btn_open = lv_btn_create(tight_container);
  lv_obj_set_size(btn_open, 200, 60);
  lv_obj_set_style_border_width(btn_open, 2, 0);
  lv_obj_set_style_border_color(btn_open, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_open, open_btn_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_open = lv_label_create(btn_open);
  lv_label_set_text(label_open, "OPEN");
  lv_obj_set_style_text_color(label_open, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_open, &lv_font_montserrat_32, 0);
  lv_obj_center(label_open);

  // Close button
  btn_close = lv_btn_create(tight_container);
  lv_obj_set_size(btn_close, 200, 60);
  lv_obj_set_style_border_width(btn_close, 2, 0);
  lv_obj_set_style_border_color(btn_close, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_close, close_btn_cb, LV_EVENT_CLICKED, NULL);

  lv_obj_t *label_close = lv_label_create(btn_close);
  lv_label_set_text(label_close, "CLOSE");
  lv_obj_set_style_text_color(label_close, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_close, &lv_font_montserrat_32, 0);
  lv_obj_center(label_close);

  // Create overlay for disabled state (circle slash symbol)
  close_btn_overlay = lv_obj_create(btn_close);
  lv_obj_set_size(close_btn_overlay, 200, 60);
  lv_obj_align(close_btn_overlay, LV_ALIGN_CENTER, 0, 0);
  lv_obj_set_style_bg_color(close_btn_overlay, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(close_btn_overlay, LV_OPA_40, 0);
  lv_obj_set_style_radius(close_btn_overlay, 0, 0);
  lv_obj_add_flag(close_btn_overlay, LV_OBJ_FLAG_HIDDEN);
  
  // Create circle (O)
  lv_obj_t *circle_label = lv_label_create(close_btn_overlay);
  lv_label_set_text(circle_label, "O");
  lv_obj_set_style_text_color(circle_label, lv_color_hex(0xFF0000), 0);
  lv_obj_set_style_text_font(circle_label, &lv_font_montserrat_32, 0);
  lv_obj_center(circle_label);

  lv_obj_t *slash_label = lv_label_create(close_btn_overlay);
  lv_label_set_text(slash_label, "/");
  lv_obj_set_style_text_color(slash_label, lv_color_hex(0xFF0000), 0);
  lv_obj_set_style_text_font(slash_label, &lv_font_montserrat_32, 0);
  lv_obj_center(slash_label);

  // Create overlay for disabled state (lock symbol) for open button
  open_btn_overlay = lv_obj_create(btn_open);
  lv_obj_set_size(open_btn_overlay, 200, 60);
  lv_obj_align(open_btn_overlay, LV_ALIGN_CENTER, 0, 0);
  lv_obj_set_style_bg_color(open_btn_overlay, lv_color_hex(0x000000), 0);
  lv_obj_set_style_bg_opa(open_btn_overlay, LV_OPA_40, 0);
  lv_obj_set_style_radius(open_btn_overlay, 0, 0);
  lv_obj_add_flag(open_btn_overlay, LV_OBJ_FLAG_HIDDEN);
  
  lv_obj_t *lock_label_open = lv_label_create(open_btn_overlay);
  lv_label_set_text(lock_label_open, LV_SYMBOL_LOCK);
  lv_obj_set_style_text_color(lock_label_open, lv_color_hex(0xAA0000), 0);
  lv_obj_set_style_text_font(lock_label_open, &lv_font_montserrat_32, 0);
  lv_obj_center(lock_label_open);

  // Lock icon button - improved for better touch response
  lock_icon_btn = lv_btn_create(tight_container);
  lv_obj_set_size(lock_icon_btn, 180, 55); // Larger for better touch on 4" display
  lv_obj_set_style_radius(lock_icon_btn, 3, 0); // Slight rounding for visual distinction
  lv_obj_set_style_border_width(lock_icon_btn, 2, 0);
  lv_obj_set_style_border_color(lock_icon_btn, lv_color_hex(0x000000), 0);
  
  // Add touch area padding to make it easier to press
  lv_obj_set_style_pad_all(lock_icon_btn, 6, 0);
  
  // Only listen for specific events, not ALL events to avoid intercepting other button touches
  lv_obj_add_event_cb(lock_icon_btn, lock_icon_event_cb, LV_EVENT_PRESSED, NULL);
  lv_obj_add_event_cb(lock_icon_btn, lock_icon_event_cb, LV_EVENT_PRESSING, NULL);
  lv_obj_add_event_cb(lock_icon_btn, lock_icon_event_cb, LV_EVENT_RELEASED, NULL);
  
  lock_icon_label = lv_label_create(lock_icon_btn);
  lv_obj_set_style_text_font(lock_icon_label, &lv_font_montserrat_22, 0); // Adjusted font size
  lv_obj_set_style_text_color(lock_icon_label, lv_color_hex(0x000000), 0);
  lv_obj_center(lock_icon_label);

  // Rotate button - smaller for 4 inch display
  lv_obj_t *btn_rotate = lv_btn_create(ui_container);
  lv_obj_set_size(btn_rotate, 120, 50);
  lv_obj_align(btn_rotate, LV_ALIGN_TOP_RIGHT, 0, 0);
  lv_obj_set_style_border_width(btn_rotate, 3, 0);
  lv_obj_set_style_border_color(btn_rotate, lv_color_hex(0x000000), 0);
  lv_obj_add_event_cb(btn_rotate, rotate_screen_cb, LV_EVENT_CLICKED, NULL);
  lv_obj_t *label_rotate = lv_label_create(btn_rotate);
  lv_label_set_text(label_rotate, "ROTATE");
  lv_obj_set_style_text_color(label_rotate, lv_color_hex(0x000000), 0);
  lv_obj_set_style_text_font(label_rotate, &lv_font_montserrat_24, 0);
  lv_obj_center(label_rotate);

  // Initialize button styles
  update_button_styles();
}