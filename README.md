# Fan/Cooler Voltage Controller — ESP32-C3 Super Mini (Bluetooth-only)

## 🆕 Versi 2.0 — 100% Bluetooth, WiFi & MQTT sudah dihapus total
Mulai versi ini, ESP32 **hanya** bisa dikontrol lewat **Bluetooth Low Energy
(BLE)** langsung dari HP. Tidak ada lagi:
- WiFi / Access Point config portal (`ESP32-Config`)
- Broker MQTT (`broker.emqx.io`)
- Endpoint HTTP (`/setwifi`, `/scanwifi`, `/api/set`, dst.)

Konsekuensinya: **tidak butuh router, internet, ataupun setup WiFi sama
sekali.** Cukup nyalakan ESP32, buka app, scan Bluetooth, pilih perangkat —
selesai. Jarak kontrol jadi terbatas jangkauan Bluetooth (biasanya beberapa
meter di dalam ruangan), tapi jauh lebih simpel dan tidak bergantung pada
jaringan WiFi rumah maupun broker publik pihak ketiga.

## Struktur folder
```
fan_cooler_app/
├── .github/workflows/build-firmware.yml  # Compile firmware.ino -> .bin otomatis (GitHub Actions)
├── codemagic.yaml       # Konfigurasi build otomatis (generate android/ + build APK)
├── pubspec.yaml
├── lib/
│   └── main.dart        # App Flutter (kontrol 100% via Bluetooth BLE)
└── firmware/
    └── firmware.ino     # Source firmware ESP32-C3 Super Mini (BLE-only)
```

## 🔥 Flash firmware TANPA laptop (langsung dari HP)
Karena app flasher di HP (misal **ESP32_Flasher** atau **ESPFlash**, ada di
Play Store) cuma bisa nulis file `.bin` yang SUDAH dikompilasi — bukan
source `.ino` — kita compile-nya di GitHub Actions dulu (gratis, otomatis).

**Langkah dari HP:**
1. Setelah kamu upload folder ini ke repo GitHub (termasuk folder
   `.github/` dan `firmware/`), buka tab **Actions** di repo tsb (lewat app
   GitHub atau browser HP). Workflow **"Build ESP32-C3 Firmware"** akan
   otomatis jalan setiap kali file di `firmware/` berubah — atau kamu bisa
   trigger manual: tab Actions → pilih workflow itu → **Run workflow**.
2. Tunggu sampai selesai (centang hijau), lalu buka hasil run itu → scroll
   ke bagian **Artifacts** → download **`firmware-untuk-hp`** (isinya 1
   file: `merged-firmware.bin`).
3. Install app **ESP32_Flasher** atau **ESPFlash** dari Play Store di HP.
4. Sambungkan ESP32-C3 ke HP pakai kabel **USB-C to USB-C** kamu (aktifkan
   OTG di pengaturan HP kalau diminta).
5. Di app flasher: pilih device **ESP32-C3**, pilih file
   `merged-firmware.bin` yang tadi didownload, set **offset ke `0x0`**
   (karena file ini sudah digabung jadi satu, cuma butuh 1 alamat), lalu
   tekan tombol **Flash**.
6. Kalau app minta masuk mode bootloader manual: tahan tombol **BOOT** di
   ESP32-C3 Super Mini sambil colok/pencet **RESET** sebentar, baru lepas
   BOOT-nya.
7. Selesai flash → lepas-pasang lagi kabelnya (atau pencet RESET) supaya
   firmware baru mulai jalan.

## Hardware yang dipakai
- **ESP32-C3 Super Mini** (pin kiri: 5V, G, 3.3, 4, 3, 2, 1, 0 — pin kanan: 5, 6, 7, 8, 9, 10, 20, 21)
- **Board decoy PD3.1/QC3.0** (2-channel A/B, pilih voltase pakai solder pad 1/2/3/4)

## 🔌 Wiring

### Board decoy → ESP32-C3 (pilih voltase 5V/9V/12V/15V)
Pakai output **A** di board decoy (yang deket IC). Solder kabel dari pad **1**, **2**, dan **3** ke ESP32 (JANGAN solder pad 4 — tidak dipakai):

| Board decoy | ESP32-C3 pin | Fungsi |
|---|---|---|
| Pad **1** | **GPIO 6** | pilih 9V saat pin ditarik LOW |
| Pad **2** | **GPIO 7** | pilih 12V saat pin ditarik LOW |
| Pad **3** | **GPIO 5** | pilih 15V saat pin ditarik LOW |
| GND (board) | **G** (ESP32) | **WAJIB** — ground harus disatukan |
| Output **A (+)** | ke beban (kipas/kontroler kamu) | output tegangan hasil |
| Output **A (–)** | ke beban, sama-samakan GND | |

Kalau ketiga GPIO 5, 6 & 7 tidak aktif (default) → board tetap di 5V (tidak perlu solder apapun untuk mode 5V).

⚠️ **Pemetaan pad 3 = 15V di atas adalah pola UMUM board decoy pad-tunggal (1=9V, 2=12V, 3=15V, 4=20V), TAPI tiap batch/model board bisa beda.** Sebelum menyolder pad 3 permanen ke GPIO 5, WAJIB verifikasi dulu pakai langkah di bagian "⚠️ Sebelum sambung ke ESP32" di bawah — ukur tegangan output aktual saat pad itu di-short ke GND. Kalau ternyata bukan 15V, sesuaikan urutan pad di firmware (`PIN_SEL_9V`/`PIN_SEL_12V`/`PIN_SEL_15V`) supaya cocok dengan pad fisik yang benar.

## 📥 Kalau tetap mau upload manual pakai Arduino IDE (opsional, butuh laptop)
Buka Library Manager (`Tools > Manage Libraries`), install:
- `NimBLE-Arduino` (h2zero) — versi terbaru
- `Adafruit NeoPixel` (Adafruit)
- `ArduinoJson` (Benoit Blanchon) — versi 6.x

Board package: pastikan sudah install **esp32 by Espressif Systems** di Board Manager, lalu pilih board **"ESP32C3 Dev Module"**.

Catatan: dependency `WiFi`, `WebServer`, dan `PubSubClient` **tidak dipakai
lagi** di versi firmware ini, jadi tidak perlu diinstall.

## 📱 Build App Flutter — TANPA laptop/komputer (pakai Codemagic)
Zip ini sengaja **tidak** menyertakan folder native (`android/`, `ios/`).
Sudah disiapkan `codemagic.yaml` di root folder ini yang bikin **mesin build
Codemagic sendiri** yang generate folder itu otomatis (mesin Codemagic sudah
ada Flutter SDK terpasang, kamu nggak perlu install apa-apa).

Langkah dari HP kamu:
1. Buat repo GitHub baru (via app GitHub atau browser HP).
2. Upload isi folder ini (`pubspec.yaml`, `lib/`, `codemagic.yaml`) ke **root**
   repo — bisa lewat GitHub app di HP ("Add file" → "Upload files"), atau
   lewat GitHub web version di Chrome HP kamu. `firmware/` & `README.md`
   boleh ikut diupload, tidak akan dipakai saat build tapi tidak masalah.
3. Buka Codemagic, connect ke repo itu (kalau belum pernah connect).
4. Codemagic otomatis mendeteksi `codemagic.yaml` dan munculin workflow
   **"Fan Cooler Android Build"** — klik **Start new build**.
5. Build ini akan: generate `android/` otomatis → `flutter pub get` →
   `flutter build apk --release`. Hasil APK bisa didownload dari halaman
   build Codemagic (bagian **Artifacts**) — bisa langsung didownload &
   diinstall di HP kamu.

Kalau nanti kamu (atau siapapun) punya akses laptop dan mau setup lebih rapi
(bukan generate ulang tiap build), tinggal jalankan sekali di laptop tsb:
```bash
flutter create --platforms=android --org com.coolerapp --project-name app_controller .
flutter pub get
```
lalu commit folder `android/` yang ke-generate itu ke repo, dan hapus step
"Generate scaffold" di `codemagic.yaml` karena sudah tidak perlu lagi.

## Cara kerja app
- 4 tombol preset: **5V / 9V / 12V / 15V** — ini satu-satunya cara pilih voltase (slider dihapus karena hardware cuma support 4 nilai tetap, bukan kontinu).
- Kontrol **hanya via Bluetooth BLE** langsung ke ESP32 — tidak ada lagi dropdown mode WiFi/Bluetooth, tidak ada lagi tombol Setup WiFi.
- Tekan **"Tambah Cooler"** (di layar utama atau drawer) untuk scan & pasangkan unit ESP32 baru lewat Bluetooth.

## 🆕 Fitur tambahan (menu di Drawer → "Data & Otomasi" / "Tampilan")
- **Riwayat Pemakaian** — grafik batang durasi nyala per hari (7 hari terakhir) + statistik ringkas (total jam nyala, voltase paling sering dipakai). Data dicatat dari status ASLI yang diterima dari device lewat Bluetooth (bukan simulasi), disimpan lokal di HP (maks. 45 hari), tidak dikirim ke server manapun.
- **Jadwal Otomatis** — atur aturan seperti "jam 22:00 turun ke 5V" atau "jam 6 pagi naik ke 12V" per hari dalam seminggu. ⚠️ Perintah baru benar-benar terkirim ke hardware kalau app sedang terbuka (foreground/background biasa) DAN Bluetooth masih tersambung — bukan lewat cloud. Notifikasi lokal tetap muncul tiap jadwal terpicu.
- **Export / Import Konfigurasi** — backup daftar cooler, warna tema, dan jadwal otomatis ke satu file `.json` (disimpan di folder dokumen internal app). Berguna saat ganti HP atau install ulang: tinggal Import file backup-nya lagi.
- **Notifikasi Cooler Offline** — kalau status disconnect lebih dari 5 menit, muncul notifikasi lokal sekali (tidak berulang) sampai online lagi.
- **Tema Terang/Gelap** — toggle "Mode Gelap" di drawer bagian Tampilan. Layar utama, drawer, Riwayat Pemakaian, dan Jadwal Otomatis sudah mendukung penuh; splash screen & beberapa dialog kecil (About, Tambah Cooler) sengaja tetap bernuansa gelap sesuai desain aslinya.

Dependency Flutter yang dipakai sekarang: `flutter_blue_plus` (Bluetooth BLE), `permission_handler` (izin Bluetooth/Lokasi/Notifikasi), `shared_preferences` (daftar cooler & pengaturan), `fl_chart` (grafik), `flutter_local_notifications` (notifikasi jadwal & offline), `path_provider` + `file_picker` (export/import file `.json`). Dependency `http` dan `mqtt_client` **sudah dihapus** karena tidak dipakai lagi. Semuanya sudah diatur di `pubspec.yaml`, tinggal build ulang lewat Codemagic seperti biasa.

## ⚠️ Sebelum sambung ke ESP32 (WAJIB dicek)
1. **Cek resistansi dulu** (board decoy disambung ke charger USB-C, BELUM disambung ke ESP32): ukur resistansi pad 1, 2, & 3 terhadap GND board. Kalau terbaca ada resistansi (bukan short 0Ω ke GND, dan bukan konek ke jalur output +), aman untuk disambung ke GPIO ESP32.
2. **Cek tegangan aktual tiap pad** (masih sebelum konek ke ESP32): sambungkan board decoy ke charger USB-C beneran, lalu satu per satu short-kan pad 1, 2, 3 ke GND pakai kabel jumper sesaat sambil ukur tegangan output **A** pakai multimeter. Catat pad mana yang menghasilkan 9V, 12V, dan 15V — cocokkan dengan urutan `PIN_SEL_9V` (GPIO6) / `PIN_SEL_12V` (GPIO7) / `PIN_SEL_15V` (GPIO5) di `firmware.ino`. Kalau urutannya beda dari asumsi default, ubah nomor GPIO di firmware supaya sesuai pad fisik yang benar sebelum disolder permanen.
3. Pastikan beban (kipas/kontroler) kamu memang aman menerima 15V — cek spesifikasi/label alatnya dulu sebelum mencoba preset 15V, supaya tidak merusak komponen yang cuma didesain untuk maksimal 12V.

## 📝 Ringkasan perubahan versi 2.0 (rombak Bluetooth-only)
- **Firmware**: WiFi, WebServer (HTTP config portal), Preferences (kredensial WiFi), dan PubSubClient (MQTT) dihapus total. Satu-satunya jalur kontrol & status sekarang BLE (library `NimBLEDevice`).
- **App Flutter**: dropdown mode "WiFi/Bluetooth" dihapus, dialog "Setup WiFi ESP32" dihapus, opsi "Tambah Cooler → Manual (WiFi)" dihapus. Semua kontrol (voltase, mode LED, bersihkan cache modul) sekarang selalu lewat Bluetooth BLE.
- **Dependency**: `http` dan `mqtt_client` dihapus dari `pubspec.yaml`.
