#include <NimBLEDevice.h>   // NimBLE: jauh lebih hemat RAM daripada Bluedroid (BLEDevice.h)
#include <Adafruit_NeoPixel.h>
#include <ArduinoJson.h>

String deviceId;   // contoh: "A1B2C3"
String bleName;    // contoh: "ESP32-Cooler-A1B2C3"

String computeDeviceId() {
  uint64_t mac = ESP.getEfuseMac();
  char buf[7];
  // Ambil 3 byte terakhir dari MAC supaya pendek tapi tetap unik antar unit
  snprintf(buf, sizeof(buf), "%06X", (unsigned int)(mac & 0xFFFFFF));
  return String(buf);
}

#define PIN_SEL_9V  6
#define PIN_SEL_12V 7
#define PIN_SEL_15V 5
#define PIN_LED_DATA 4
#define NUM_LEDS 30   // <-- GANTI sesuai JUMLAH LED ASLI di strip kamu (hitung manual)
Adafruit_NeoPixel strip(NUM_LEDS, PIN_LED_DATA, NEO_GRB + NEO_KHZ800);
String ledMode = "off"; // "off" | "static" | "running" | "disco" | "bounce"
String lastLedEffect = "running"; // efek terakhir dipilih, dipakai saat tombol ON ditekan
unsigned long lastLedStep = 0;
uint16_t rainbowStep = 0;
int bouncePos = 0;
int bounceDir = 1;

float currentSetVoltage = 5.0;
unsigned long startMillis = 0;
unsigned long lastNotify = 0;

// ===== BLE (NimBLE) =====
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
NimBLEServer* pServer = NULL;
NimBLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
String bleCommand = "";

class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer) {
    deviceConnected = true;
  }
  void onDisconnect(NimBLEServer* pServer) {
    deviceConnected = false;
    // Lanjut advertise lagi supaya app bisa reconnect kapan saja
    pServer->getAdvertising()->start();
  }
};

class MyCharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() > 0) bleCommand = value;
  }
};

void applyVoltage(float volt) {
  // Snap ke nilai terdekat yang benar-benar disupport hardware: 5 / 9 / 12 / 15
  if (volt >= 13.5) volt = 15.0;
  else if (volt >= 10.5) volt = 12.0;
  else if (volt >= 7.0) volt = 9.0;
  else volt = 5.0;

  // Lepas semua pin dulu (floating = tidak menyolder pad apapun = default 5V)
  pinMode(PIN_SEL_9V, INPUT);
  pinMode(PIN_SEL_12V, INPUT);
  pinMode(PIN_SEL_15V, INPUT);

  if (volt == 9.0) {
    pinMode(PIN_SEL_9V, OUTPUT);
    digitalWrite(PIN_SEL_9V, LOW);
  } else if (volt == 12.0) {
    pinMode(PIN_SEL_12V, OUTPUT);
    digitalWrite(PIN_SEL_12V, LOW);
  } else if (volt == 15.0) {
    pinMode(PIN_SEL_15V, OUTPUT);
    digitalWrite(PIN_SEL_15V, LOW);
  }
  // volt == 5.0 -> ketiga pin dibiarkan floating (INPUT), tidak ada yang disolder

  currentSetVoltage = volt;
}

void applyLedMode(String mode) {
  if (mode != "off" && mode != "static" && mode != "running" &&
      mode != "disco" && mode != "bounce") return;

  ledMode = mode;
  if (mode != "off") lastLedEffect = mode; // ingat efek terakhir buat tombol ON

  if (mode == "off") {
    strip.clear();
    strip.show();
  } else if (mode == "static") {
    for (int i = 0; i < NUM_LEDS; i++) {
      int hue = (i * 256 / NUM_LEDS) & 255;
      strip.setPixelColor(i, wheelColor(hue));
    }
    strip.show();
  } else if (mode == "bounce") {
    bouncePos = 0;
    bounceDir = 1;
  }
  // "running" & "disco" -> animasinya diproses tiap frame di handleLedAnimation()
}

// ===== FUNGSI BANTU: WARNA PELANGI DARI 1 ANGKA (0-255) =====
uint32_t wheelColor(byte pos) {
  pos = 255 - pos;
  if (pos < 85) return strip.Color(255 - pos * 3, 0, pos * 3);
  if (pos < 170) { pos -= 85; return strip.Color(0, pos * 3, 255 - pos * 3); }
  pos -= 170;
  return strip.Color(pos * 3, 255 - pos * 3, 0);
}

// ===== ANIMASI LAMPU (dipanggil terus-menerus di loop()) =====
void handleLedAnimation() {
  if (ledMode == "running") {
    if (millis() - lastLedStep < 20) return; // kecepatan animasi (ms/frame)
    lastLedStep = millis();
    for (int i = 0; i < NUM_LEDS; i++) {
      int hue = ((i * 256 / NUM_LEDS) + rainbowStep) & 255;
      strip.setPixelColor(i, wheelColor(hue));
    }
    strip.show();
    rainbowStep += 3;
    if (rainbowStep >= 256) rainbowStep = 0;

  } else if (ledMode == "disco") {
    if (millis() - lastLedStep < 120) return; // kecepatan kedip disko
    lastLedStep = millis();
    for (int i = 0; i < NUM_LEDS; i++) {
      strip.setPixelColor(i, strip.Color(random(0, 256), random(0, 256), random(0, 256)));
    }
    strip.show();

  } else if (ledMode == "bounce") {
    if (millis() - lastLedStep < 30) return; // kecepatan gerak titik
    lastLedStep = millis();
    strip.clear();
    const int tailLen = 4; // panjang ekor cahaya
    for (int t = 0; t < tailLen; t++) {
      int pos = bouncePos - (bounceDir * t);
      if (pos >= 0 && pos < NUM_LEDS) {
        int fade = 255 - (t * (255 / tailLen));
        uint32_t c = wheelColor((bouncePos * 8) & 255);
        uint8_t r = (uint8_t)(((c >> 16) & 0xFF) * fade / 255);
        uint8_t g = (uint8_t)(((c >> 8) & 0xFF) * fade / 255);
        uint8_t b = (uint8_t)((c & 0xFF) * fade / 255);
        strip.setPixelColor(pos, strip.Color(r, g, b));
      }
    }
    strip.show();
    bouncePos += bounceDir;
    if (bouncePos >= NUM_LEDS - 1 || bouncePos <= 0) bounceDir = -bounceDir;
  }
  // "static" & "off" -> tidak perlu update tiap frame, sudah digambar sekali di applyLedMode()
}

void clearModuleCache() {
  applyVoltage(5.0);
  startMillis = millis();
  notifyStatus();
}

// ===== KIRIM STATUS TERBARU VIA BLE NOTIFY =====
void notifyStatus() {
  unsigned long runtime = millis() - startMillis;
  long s = runtime / 1000, m = s / 60, h = m / 60;
  String uptime = String(h) + ":" + String(m % 60) + ":" + String(s % 60);

  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["setVoltage"] = currentSetVoltage;
  doc["ledMode"] = ledMode;
  doc["uptime"] = uptime;
  String jsonStr;
  serializeJson(doc, jsonStr);

  if (deviceConnected) {
    pCharacteristic->setValue(jsonStr.c_str());
    pCharacteristic->notify();
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);
  randomSeed(esp_random());

  // ===== HITUNG ID UNIK PERANGKAT (WAJIB paling awal, dipakai di semua tempat) =====
  deviceId = computeDeviceId();
  bleName = "ESP32-Cooler-" + deviceId;
  Serial.println("=== ID Perangkat: " + deviceId + " ===");
  Serial.println("BLE name: " + bleName);

  // Voltage select pins: default floating (5V), belum ada yang disolder ke GND
  applyVoltage(5.0);

  // Lampu: mulai strip, batasi brightness biar arus aman, lalu matikan dulu
  strip.begin();
  strip.setBrightness(80); // 0-255; makin tinggi makin terang TAPI makin besar arusnya
  strip.show();
  applyLedMode("off");

  // ===== START BLE (NimBLE) — SATU-SATUNYA JALUR KONTROL =====
  NimBLEDevice::init(bleName.c_str());
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ |
    NIMBLE_PROPERTY::WRITE |
    NIMBLE_PROPERTY::NOTIFY
  );
  // Catatan: NimBLE otomatis handle descriptor notify (CCCD),
  // tidak perlu addDescriptor(new BLE2902()) manual seperti di Bluedroid.
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pService->start();
  pServer->getAdvertising()->start();
  Serial.println("BLE (NimBLE) siap! Menunggu koneksi dari app...");

  startMillis = millis();
}

void loop() {
  // ===== Proses Perintah BLE =====
  if (bleCommand.length() > 0) {
    StaticJsonDocument<128> doc;
    if (!deserializeJson(doc, bleCommand)) {
      if (doc.containsKey("voltage")) applyVoltage(doc["voltage"]);
      if (doc.containsKey("ledMode")) applyLedMode(String((const char*)doc["ledMode"]));
      if (doc.containsKey("action") && String((const char*)doc["action"]) == "clear_cache") {
        clearModuleCache();
      }
      notifyStatus(); // balas status langsung setelah perintah diproses
    }
    bleCommand = "";
  }

  // ===== Jalankan 1 frame animasi lampu (kalau mode running/disco/bounce) =====
  handleLedAnimation();

  // ===== Kirim status berkala via BLE notify =====
  if (millis() - lastNotify > 3000) {
    notifyStatus();
    lastNotify = millis();
  }

  delay(10);
}
