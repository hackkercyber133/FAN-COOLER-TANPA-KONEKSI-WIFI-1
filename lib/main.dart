import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'theme_controller.dart';
import 'history_service.dart';
import 'schedule_service.dart';
import 'notification_service.dart';
import 'backup_service.dart';
import 'history_page.dart';
import 'schedule_page.dart';

// =======================================================================
// ===== MODEL: satu "Cooler" yang sudah dipasangkan (paired) dengan HP =====
// Supaya banyak HP & banyak cooler tidak tumbukan, setiap cooler dikenali
// lewat deviceId unik (dari chip ESP32-nya sendiri), bukan lewat topic
// global. HP hanya bisa kontrol cooler yang sudah eksplisit ditambahkan.
// =======================================================================
class Cooler {
  String id; // deviceId unik dari firmware, mis. "A1B2C3"
  String nickname; // nama custom dari user, mis. "Cooler Kamar"
  String bleRemoteId; // MAC address BLE perangkat, dipakai untuk reconnect

  Cooler({required this.id, required this.nickname, required this.bleRemoteId});

  Map<String, dynamic> toJson() =>
      {"id": id, "nickname": nickname, "bleRemoteId": bleRemoteId};

  factory Cooler.fromJson(Map<String, dynamic> j) => Cooler(
        id: j["id"],
        nickname: j["nickname"],
        // Kompatibel dengan backup lama yang mungkin masih punya field "mode"
        bleRemoteId: j["bleRemoteId"] ?? "",
      );
}

const String kAppVersion = "2.0.0";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.load();
  await NotificationService.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Dengarkan perubahan mode tema (terang/gelap) supaya seluruh app
    // langsung rebuild begitu user toggle di drawer.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Mod And TroubleShoot',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: SplashScreen(),
        );
      },
    );
  }
}

// =======================================================================
// ===== SPLASH SCREEN — ANIMASI PEMBUKA BERGAYA GAMING (MLBB/FF STYLE) ===
// =======================================================================
class _SplashParticle {
  final double x; // posisi horizontal awal (0..1)
  final double speed; // faktor kecepatan naik
  final double size; // ukuran partikel
  final double phase; // offset siklus awal (0..1)
  final double drift; // amplitudo goyangan horizontal

  _SplashParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.phase,
    required this.drift,
  });
}

class SplashScreen extends StatefulWidget {
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Controller utama: menjalankan urutan animasi satu-kali selama 5.2 detik.
  late final AnimationController _mainCtrl;
  // Controller loop: partikel, cincin energi, dan efek "shine" berjalan terus-menerus.
  late final AnimationController _loopCtrl;
  late final List<_SplashParticle> _particles;

  @override
  void initState() {
    super.initState();

    final rnd = Random(7);
    _particles = List.generate(42, (i) {
      return _SplashParticle(
        x: rnd.nextDouble(),
        speed: 0.35 + rnd.nextDouble() * 0.9,
        size: 1.2 + rnd.nextDouble() * 2.6,
        phase: rnd.nextDouble(),
        drift: rnd.nextDouble() * 18 - 9,
      );
    });

    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 15000));
    _loopCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 5000))..repeat();

    _mainCtrl.forward();
    _mainCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 400), _goToApp);
      }
    });
  }

  void _goToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, anim, __) => ControllerPage(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.06, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color neon = Color(0xFF33F0FF);

    return Scaffold(
      backgroundColor: const Color(0xFF03040A),
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainCtrl, _loopCtrl]),
        builder: (context, _) {
          final t = _mainCtrl.value.clamp(0.0, 1.0);
          final loop = _loopCtrl.value;

          double stage(double begin, double end, {Curve curve = Curves.linear}) {
            return curve.transform(Interval(begin, end, curve: Curves.linear).transform(t)).clamp(0.0, 1.0);
          }

          final ringIntro = stage(0.0, 0.45, curve: Curves.easeOutExpo);
          final logoScale = stage(0.05, 0.55, curve: Curves.elasticOut);
          final logoFade = stage(0.0, 0.30);
          final titleT = stage(0.35, 0.70, curve: Curves.easeOutCubic);
          final subtitleT = stage(0.50, 0.80, curve: Curves.easeOutCubic);
          final barT = stage(0.05, 0.97, curve: Curves.easeInOutSine);
          final flashT = stage(0.94, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // latar gradasi radial gelap ala HUD game
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.1),
                    radius: 1.15,
                    colors: [Color(0xFF0C1B2A), Color(0xFF03040A)],
                  ),
                ),
              ),
              // partikel energi melayang naik
              CustomPaint(
                painter: _ParticlePainter(particles: _particles, loop: loop, color: neon),
                size: Size.infinite,
              ),
              // cincin gelombang energi di belakang logo
              Center(
                child: CustomPaint(
                  painter: _RingPainter(loopValue: loop, intro: ringIntro, color: neon),
                  size: const Size(320, 320),
                ),
              ),
              // bingkai hexagon berputar (efek "circuit")
              Center(
                child: Transform.rotate(
                  angle: loop * 2 * pi,
                  child: Opacity(
                    opacity: (0.28 * ringIntro).clamp(0.0, 0.28),
                    child: CustomPaint(
                      painter: _HexPainter(color: neon),
                      size: const Size(210, 210),
                    ),
                  ),
                ),
              ),
              // konten utama: logo, judul, subjudul, progress bar
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: logoFade,
                      child: Transform.scale(
                        scale: 0.4 + 0.6 * logoScale,
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [neon.withOpacity(0.9), Colors.blueAccent.withOpacity(0.6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: neon.withOpacity(0.5 + 0.25 * sin(loop * 2 * pi).abs()),
                                blurRadius: 42,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.ac_unit, color: Colors.white, size: 56),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: titleT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - titleT) * 18),
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            final sweep = (loop * 2.4) % 2.4 - 0.7;
                            return LinearGradient(
                              colors: const [Colors.white, Color(0xFFBFF7FF), Colors.white],
                              stops: [
                                (sweep - 0.25).clamp(0.0, 1.0),
                                sweep.clamp(0.0, 1.0),
                                (sweep + 0.25).clamp(0.0, 1.0),
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'COOLER CONTROLLER',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: subtitleT,
                      child: Text(
                        'GAME-GRADE VOLTAGE ENGINE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 4,
                          color: neon.withOpacity(0.8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Opacity(
                      opacity: barT > 0 ? 1 : 0,
                      child: Column(
                        children: [
                          Container(
                            width: 190,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: barT,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: LinearGradient(colors: [neon, Colors.blueAccent]),
                                    boxShadow: [BoxShadow(color: neon.withOpacity(0.7), blurRadius: 8)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'LOADING ${(barT * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // versi aplikasi di bagian bawah
              Positioned(
                bottom: 26,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: subtitleT,
                  child: Center(
                    child: Text(
                      'v$kAppVersion',
                      style: const TextStyle(color: Colors.white30, fontSize: 12, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
              // kilatan putih halus saat transisi keluar dari splash
              if (flashT > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: (flashT * 0.85).clamp(0.0, 0.85),
                    child: Container(color: Colors.white),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_SplashParticle> particles;
  final double loop;
  final Color color;
  _ParticlePainter({required this.particles, required this.loop, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final progress = (loop + p.phase) % 1.0;
      final y = size.height * (1 - progress);
      final x = p.x * size.width + sin((progress + p.phase) * 2 * pi) * p.drift;
      final opacity = sin(progress * pi).clamp(0.0, 1.0);
      paint.color = color.withOpacity(0.55 * opacity);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

class _RingPainter extends CustomPainter {
  final double loopValue;
  final double intro;
  final Color color;
  _RingPainter({required this.loopValue, required this.intro, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final progress = (loopValue + i / 3) % 1.0;
      final radius = maxRadius * progress * intro;
      final opacity = ((1 - progress) * 0.5 * intro).clamp(0.0, 0.5);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withOpacity(opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => true;
}

class _HexPainter extends CustomPainter {
  final Color color;
  _HexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (pi / 3) * i - pi / 2;
      final point = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) => false;
}

class ControllerPage extends StatefulWidget {
  @override
  _ControllerPageState createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  // ===== DAFTAR COOLER YANG SUDAH DIPASANGKAN (persist ke HP) =====
  // Ini kuncinya supaya tidak tumbukan: app hanya mau ngirim perintah ke
  // cooler yang eksplisit ada di daftar ini (dikenali dari deviceId unik).
  List<Cooler> pairedCoolers = [];
  Cooler? activeCooler;

  // ===== TEMA WARNA (custom) =====
  Color accentColor = Colors.cyanAccent;
  final List<Color> colorPalette = [
    Colors.cyanAccent,
    Colors.purpleAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.blueAccent,
    Colors.amberAccent,
    Colors.tealAccent,
    Colors.redAccent,
    Colors.lightGreenAccent,
  ];

  // ===== BLUETOOTH (satu-satunya jalur kontrol sekarang) =====
  BluetoothDevice? bleDevice;
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  bool bleConnected = false;

  // ===== DATA VOLTASE =====
  // Hardware (board decoy PD3.1/QC3.0) mendukung 4 level tegangan
  // tetap secara fisik: 5V / 9V / 12V / 15V. Tidak ada mode kontinu.
  double setVolt = 5.0; // voltase yang sedang aktif/terkirim
  String ledMode = "off"; // "off" | "static" | "running" | "disco" | "bounce"
  String lastLedEffect = "running"; // efek terakhir dipilih, dipakai saat tombol ON
  String uptime = "00:00:00";
  String status = "🔴 Offline";

  // ===== JADWAL OTOMATIS & DETEKSI OFFLINE =====
  List<ScheduleRule> _schedules = [];
  Timer? _scheduleTimer;
  Timer? _offlineCheckTimer;
  DateTime? _lastOnlineAt;
  bool _offlineNotified = false;
  final int offlineThresholdMinutes = 5;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    _offlineCheckTimer?.cancel();
    bleDevice?.disconnect();
    super.dispose();
  }

  Future<void> _initApp() async {
    // Minta izin Bluetooth & Lokasi dulu (wajib di Android 12+), kalau tidak
    // diminta di sini, scan BLE akan gagal diam-diam.
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();

    await _loadPairedCoolers();
    _schedules = await ScheduleService.loadAll();

    // Cek jadwal tiap 30 detik, cek status offline tiap 1 menit — cukup
    // ringan tapi tetap responsif untuk kasus "jam 22:00 turun ke 5V".
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkSchedules());
    _offlineCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkOfflineNotification());

    if (activeCooler != null) {
      _connectActiveCooler();
    }
  }

  // ===== JADWAL OTOMATIS: dicek berkala, kirim perintah kalau waktunya cocok =====
  void _checkSchedules() {
    if (activeCooler == null || _schedules.isEmpty) return;
    final now = DateTime.now();
    final todayKey = "${now.year}-${now.month}-${now.day}";
    bool changed = false;
    for (final r in _schedules) {
      if (!r.enabled || r.coolerId != activeCooler!.id) continue;
      if (!r.days.contains(now.weekday)) continue;
      if (r.hour != now.hour || r.minute != now.minute) continue;
      if (r.lastFiredDateKey == todayKey) continue; // sudah jalan hari ini
      r.lastFiredDateKey = todayKey;
      changed = true;
      sendVoltage(r.voltage);
      NotificationService.show(
        id: r.id.hashCode,
        title: "Jadwal Otomatis",
        body: "${activeCooler!.nickname}: voltase otomatis diubah ke ${r.voltage.toStringAsFixed(0)}V",
      );
    }
    if (changed) ScheduleService.saveAll(_schedules);
  }

  // ===== NOTIFIKASI COOLER OFFLINE =====
  void _checkOfflineNotification() {
    if (activeCooler == null) return;
    final online = status == "🟢 Online";
    if (online) {
      _lastOnlineAt = DateTime.now();
      _offlineNotified = false;
      return;
    }
    _lastOnlineAt ??= DateTime.now();
    final offlineFor = DateTime.now().difference(_lastOnlineAt!);
    if (!_offlineNotified && offlineFor.inMinutes >= offlineThresholdMinutes) {
      _offlineNotified = true;
      NotificationService.show(
        id: 9001,
        title: "Cooler Offline",
        body: "${activeCooler!.nickname} tidak terhubung selama lebih dari $offlineThresholdMinutes menit.",
      );
    }
  }

  // ===== PENYIMPANAN DAFTAR COOLER (persist antar sesi app) =====
  Future<void> _loadPairedCoolers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('paired_coolers');
    final lastActiveId = prefs.getString('active_cooler_id');
    if (raw != null) {
      List<dynamic> list = jsonDecode(raw);
      setState(() {
        pairedCoolers = list.map((e) => Cooler.fromJson(e)).toList();
        if (pairedCoolers.isNotEmpty) {
          activeCooler = pairedCoolers.firstWhere(
            (c) => c.id == lastActiveId,
            orElse: () => pairedCoolers.first,
          );
        }
      });
    }
  }

  Future<void> _savePairedCoolers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'paired_coolers', jsonEncode(pairedCoolers.map((c) => c.toJson()).toList()));
    if (activeCooler != null) {
      await prefs.setString('active_cooler_id', activeCooler!.id);
    }
  }

  // ===== SAMBUNGKAN KE COOLER YANG SEDANG AKTIF (selalu via Bluetooth) =====
  void _connectActiveCooler() {
    if (activeCooler == null) return;
    _connectBleById(activeCooler!.bleRemoteId);
  }

  Future<void> _connectBleById(String remoteId) async {
    if (remoteId.isEmpty) return;
    try {
      final device = BluetoothDevice.fromId(remoteId);
      await connectBLE(device);
    } catch (e) {
      _showSnack("⚠️ Gagal konek ulang ke ${activeCooler?.nickname}, coba scan ulang");
    }
  }

  // ===== SWITCH COOLER AKTIF (dipanggil dari drawer) =====
  void switchActiveCooler(Cooler cooler) {
    // Putuskan koneksi cooler sebelumnya dulu supaya tidak nyangkut
    if (bleDevice != null) {
      bleDevice!.disconnect();
    }
    setState(() {
      activeCooler = cooler;
      status = "🔴 Offline";
      bleConnected = false;
    });
    _lastOnlineAt = null;
    _offlineNotified = false;
    _savePairedCoolers();
    _connectActiveCooler();
  }

  void removeCooler(Cooler cooler) {
    setState(() {
      pairedCoolers.removeWhere((c) => c.id == cooler.id);
      if (activeCooler?.id == cooler.id) {
        activeCooler = pairedCoolers.isNotEmpty ? pairedCoolers.first : null;
        status = "🔴 Offline";
      }
    });
    _savePairedCoolers();
    if (activeCooler != null) _connectActiveCooler();
  }

  void addCooler(Cooler cooler) {
    setState(() {
      pairedCoolers.removeWhere((c) => c.id == cooler.id); // hindari duplikat
      pairedCoolers.add(cooler);
      activeCooler = cooler;
      status = "🔴 Offline";
    });
    _savePairedCoolers();
    _connectActiveCooler();
  }

  // ===== BLUETOOTH =====
  void scanBLE() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));
    FlutterBluePlus.onScanResults.listen((results) {
      setState(() {
        // Nama unik per-unit ("ESP32-Cooler-XXXXXX") -> tiap fisik cooler
        // muncul sebagai entri terpisah di daftar, tidak bakal ketuker.
        scanResults =
            results.where((r) => r.device.platformName.contains("ESP32-Cooler-")).toList();
      });
    });
    await Future.delayed(Duration(seconds: 6));
    setState(() {
      isScanning = false;
    });
  }

  // Ambil ID unik cooler dari nama BLE-nya, mis. "ESP32-Cooler-A1B2C3" -> "A1B2C3"
  String extractDeviceId(String bleName) {
    final parts = bleName.split("ESP32-Cooler-");
    return parts.length > 1 ? parts[1].trim() : bleName;
  }

  Future<void> connectBLE(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        bleDevice = device;
        bleConnected = true;
        status = "🟢 Online";
      });
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((value) {
              String payload = utf8.decode(value);
              try {
                var data = jsonDecode(payload);
                if (data['deviceId'] != null && data['deviceId'] != activeCooler?.id) return;
                setState(() {
                  setVolt = (data['setVoltage'] ?? setVolt).toDouble();
                  ledMode = data['ledMode'] ?? ledMode;
                  uptime = data['uptime'] ?? "00:00:00";
                  if (ledMode != "off") lastLedEffect = ledMode;
                });
                if (activeCooler != null) {
                  HistoryService.recordStatus(coolerId: activeCooler!.id, online: true, voltage: setVolt);
                }
              } catch (e) {}
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        bleConnected = false;
        status = "🔴 Offline";
      });
      if (activeCooler != null) {
        HistoryService.recordStatus(coolerId: activeCooler!.id, online: false, voltage: setVolt);
      }
    }
  }

  void sendCommandBLE(double volt) async {
    if (!bleConnected || bleDevice == null) {
      setState(() => status = "🔴 Offline");
      _showSnack("⚠️ Belum terhubung ke perangkat Bluetooth");
      return;
    }
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode({"voltage": volt})));
            setState(() {
              setVolt = volt;
            });
            return;
          }
        }
      }
    } catch (e) {
      _showSnack("❌ Gagal mengirim perintah ke perangkat");
    }
  }

  void sendLedCommandBLE(String mode) async {
    if (!bleConnected || bleDevice == null) {
      setState(() => status = "🔴 Offline");
      _showSnack("⚠️ Belum terhubung ke perangkat Bluetooth");
      return;
    }
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode({"ledMode": mode})));
            setState(() {
              ledMode = mode;
            });
            return;
          }
        }
      }
    } catch (e) {
      _showSnack("❌ Gagal mengirim perintah ke perangkat");
    }
  }

  void sendLed(String mode) {
    if (activeCooler == null) {
      _showSnack("⚠️ Pilih atau tambah cooler dulu");
      return;
    }
    if (mode != "off") lastLedEffect = mode; // ingat efek terakhir buat tombol ON
    sendLedCommandBLE(mode);
  }

  void sendVoltage(double volt) {
    if (activeCooler == null) {
      _showSnack("⚠️ Pilih atau tambah cooler dulu");
      return;
    }
    volt = double.parse(volt.toStringAsFixed(1));
    sendCommandBLE(volt);
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ===== EXPORT / IMPORT KONFIGURASI =====
  void _showBackupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF12181f),
        title: Text("Export / Import Konfigurasi", style: TextStyle(color: Colors.white)),
        content: Text(
          "Export: simpan daftar cooler, tema, dan jadwal otomatis ke file .json di penyimpanan app.\n\n"
          "Import: baca file .json backup dan gantikan konfigurasi yang sedang dipakai sekarang.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Batal")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doImportConfig();
            },
            child: Text("Import", style: TextStyle(color: Colors.orangeAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            onPressed: () async {
              Navigator.pop(ctx);
              await _doExportConfig();
            },
            child: Text("Export", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _doExportConfig() async {
    try {
      final schedules = await ScheduleService.loadAll();
      final payload = BackupService.buildPayload(
        coolers: pairedCoolers.map((c) => c.toJson()).toList(),
        accentColorValue: accentColor.value,
        themeMode: ThemeController.isDark ? "dark" : "light",
        schedules: schedules.map((s) => s.toJson()).toList(),
      );
      final path = await BackupService.exportToFile(payload);
      _showSnack("✅ Backup tersimpan di: $path");
    } catch (e) {
      _showSnack("❌ Gagal export konfigurasi: $e");
    }
  }

  Future<void> _doImportConfig() async {
    final payload = await BackupService.importFromFile();
    if (payload == null) {
      _showSnack("⚠️ Import dibatalkan atau file tidak valid");
      return;
    }
    try {
      final coolersJson = (payload["coolers"] as List?) ?? [];
      final importedCoolers = coolersJson.map((e) => Cooler.fromJson(e)).toList();
      final importedAccent = payload["accentColor"] as int?;
      final importedTheme = payload["themeMode"] as String?;
      final schedulesJson = (payload["schedules"] as List?) ?? [];
      final importedSchedules = schedulesJson.map((e) => ScheduleRule.fromJson(e)).toList();

      // Putuskan koneksi lama sebelum daftar cooler diganti total.
      if (bleDevice != null) {
        bleDevice!.disconnect();
      }

      setState(() {
        pairedCoolers = importedCoolers;
        if (importedAccent != null) accentColor = Color(importedAccent);
        activeCooler = pairedCoolers.isNotEmpty ? pairedCoolers.first : null;
        status = "🔴 Offline";
      });
      await _savePairedCoolers();
      await ScheduleService.saveAll(importedSchedules);
      _schedules = importedSchedules;
      if (importedTheme != null) {
        await ThemeController.setDark(importedTheme != "light");
      }
      if (activeCooler != null) _connectActiveCooler();
      _showSnack("✅ Konfigurasi berhasil diimport (${importedCoolers.length} cooler)");
    } catch (e) {
      _showSnack("❌ File backup tidak valid: $e");
    }
  }

  // ===== CACHE =====
  void clearAppCache() {
    setState(() {
      scanResults.clear();
    });
    Navigator.of(context, rootNavigator: true).pop();
    _showSnack("🧹 Cache aplikasi berhasil dibersihkan");
  }

  void clearEsp32Cache() {
    if (bleConnected) {
      sendBLERaw({"action": "clear_cache"});
      _showSnack("🧹 Perintah bersihkan cache modul ESP32 terkirim");
    } else {
      _showSnack("⚠️ Tidak terhubung ke ESP32, cache tidak bisa dibersihkan");
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> sendBLERaw(Map<String, dynamic> payload) async {
    if (!bleConnected || bleDevice == null) return;
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode(payload)));
            return;
          }
        }
      }
    } catch (e) {}
  }

  // ===== DIALOG: ABOUT / CHANGELOG =====
  void showAboutChangelogDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF11161f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: accentColor),
            SizedBox(width: 8),
            Text("About", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: DefaultTextStyle(
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Cooler Controller App",
                    style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Version: $kAppVersion"),
                Divider(color: Colors.white24, height: 20),
                Text("Developer", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Nama: Apri Ansyah"),
                Text("Telegram Dev: t.me/bujanginm"),
                Text("Group Telegram:"),
                Text("https://t.me/forumdiskusitele/371474"),
                Divider(color: Colors.white24, height: 20),
                Text("Tujuan Aplikasi", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text(
                    "Aplikasi ini dibuat hanya untuk tujuan edukasi/pembelajaran, mengenai cara kerja fan cooler apabila dikontrol menggunakan aplikasi."),
                Divider(color: Colors.white24, height: 20),
                Text("Cara Penggunaan (Dari Awal sampai Selesai)",
                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text("A. Persiapan Awal",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 2),
                Text(
                    "1. Pastikan modul ESP32-C3 sudah terpasang & menyala (lampu indikator hidup).\n"
                    "2. Buka aplikasi ini, lalu izinkan permission Bluetooth & Lokasi saat diminta (wajib supaya fitur scan Bluetooth berfungsi).\n"
                    "3. Aplikasi ini SEPENUHNYA memakai Bluetooth Low Energy (BLE) — tidak butuh WiFi, router, ataupun internet sama sekali."),
                SizedBox(height: 8),
                Text("B. Menambahkan Cooler ke Aplikasi",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 2),
                Text(
                    "4. Buka menu ☰ → \"Tambah Cooler Baru\".\n"
                    "5. Isi nama cooler (bebas, mis. \"Cooler Kamar\").\n"
                    "6. Tunggu daftar perangkat Bluetooth muncul, lalu ketuk perangkat yang sesuai (nama diawali \"ESP32-Cooler-\").\n"
                    "7. Cooler yang baru ditambahkan otomatis jadi cooler aktif & langsung tersambung Bluetooth (bisa dicek/diganti lewat menu ☰ → \"Cooler Saya\")."),
                SizedBox(height: 8),
                Text("C. Mengatur Voltase Kipas",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 2),
                Text(
                    "8. Pastikan status di atas menunjukkan \"🟢 Online\" (cooler sudah terhubung Bluetooth).\n"
                    "9. Di halaman utama, pilih salah satu preset tegangan: 5V / 9V / 12V / 15V.\n"
                    "10. Tekan tombol \"Pilih\" pada preset yang diinginkan — tombol akan berubah jadi \"Terpilih\" dan kipas akan menyesuaikan tegangan.\n"
                    "11. Selesai — kipas kini berjalan sesuai voltase yang dipilih."),
                SizedBox(height: 8),
                Text("D. Fitur Tambahan (opsional)",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                SizedBox(height: 2),
                Text(
                    "• Ganti warna tema aplikasi lewat menu ☰ → \"Tampilan\".\n"
                    "• \"Bersihkan Cache Aplikasi\" untuk menghapus data scan Bluetooth sementara.\n"
                    "• \"Bersihkan Cache Modul ESP32\" untuk kirim perintah reset cache ke ESP32.\n"
                    "• Bisa menambahkan & berpindah antar beberapa cooler lewat menu ☰ → \"Cooler Saya\"."),
                Divider(color: Colors.white24, height: 20),
                Text("Status", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Aplikasi ini FREE dan TIDAK untuk diperjualbelikan."),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Tutup", style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  // ===== DIALOG: KONFIRMASI CACHE =====
  void _confirmClear(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF11161f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: Colors.white)),
        content: Text(message, style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Batal", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            child: Text("Ya, Bersihkan"),
          ),
        ],
      ),
    );
  }

  // ===== DRAWER (MENU GARIS 3) =====
  // ===== DIALOG: TAMBAH COOLER BARU =====
  // Satu-satunya cara sekarang: scan Bluetooth, lalu pilih unit fisik yang
  // mau dipasangkan. Tidak ada lagi opsi manual via WiFi/ID perangkat.
  void showAddCoolerDialog() {
    final nicknameController = TextEditingController();
    scanBLE();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Color(0xFF11161f),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("Tambah Cooler Baru", style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nicknameController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Nama cooler (mis. Cooler Kamar)",
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                    ),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.bluetooth, color: accentColor, size: 18),
                        SizedBox(width: 6),
                        Text("Cooler Bluetooth di sekitar",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                      ],
                    ),
                    SizedBox(height: 10),
                    if (isScanning)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)),
                          SizedBox(width: 10),
                          Text("Mencari cooler di sekitar...", style: TextStyle(color: Colors.white54)),
                        ]),
                      ),
                    if (!isScanning && scanResults.isEmpty)
                      Text("Tidak ada cooler ditemukan. Pastikan Bluetooth aktif & cooler menyala.",
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ...scanResults.map((r) {
                      final id = extractDeviceId(r.device.platformName);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.bluetooth, color: accentColor),
                        title: Text(r.device.platformName, style: TextStyle(color: Colors.white)),
                        subtitle: Text("ID: $id", style: TextStyle(color: Colors.white38, fontSize: 11)),
                        onTap: () async {
                          String nickname =
                              nicknameController.text.trim().isEmpty ? r.device.platformName : nicknameController.text.trim();
                          Navigator.pop(ctx);
                          final cooler = Cooler(
                              id: id, nickname: nickname, bleRemoteId: r.device.remoteId.str);
                          addCooler(cooler);
                          await connectBLE(r.device);
                        },
                      );
                    }).toList(),
                    TextButton.icon(
                      onPressed: () => setDialogState(() => scanBLE()),
                      icon: Icon(Icons.refresh, color: accentColor, size: 18),
                      label: Text("Scan ulang", style: TextStyle(color: accentColor)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Batal", style: TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawer() {
    final isDark = ThemeController.isDark;
    return Drawer(
      backgroundColor: AppColors.surface(isDark),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 28, 20, 20),
              decoration: BoxDecoration(color: Colors.black26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ac_unit, color: accentColor, size: 34),
                  SizedBox(height: 10),
                  Text("Cooler Controller",
                      style: TextStyle(color: AppColors.text(isDark), fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text(
                      activeCooler != null
                          ? "${activeCooler!.nickname} • $status"
                          : status,
                      style: TextStyle(
                          fontSize: 12,
                          color: status == "🟢 Online" ? Colors.greenAccent : Colors.redAccent)),
                ],
              ),
            ),
            _drawerSectionTitle("Cooler Saya"),
            if (pairedCoolers.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Belum ada cooler yang ditambahkan. Tambah dulu supaya HP ini tahu cooler mana yang mau dikontrol.",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 12),
                ),
              ),
            ...pairedCoolers.map((cooler) {
              bool selected = activeCooler?.id == cooler.id;
              return ListTile(
                leading: Icon(Icons.bluetooth,
                    color: selected ? accentColor : AppColors.textFaint(isDark)),
                title: Text(cooler.nickname,
                    style: TextStyle(
                        color: AppColors.text(isDark),
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text("ID: ${cooler.id} • Bluetooth",
                    style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) Icon(Icons.check_circle, color: accentColor, size: 20),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: AppColors.textFaint(isDark), size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        removeCooler(cooler);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (!selected) switchActiveCooler(cooler);
                },
              );
            }).toList(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor),
                  ),
                  icon: Icon(Icons.add),
                  label: Text("Tambah Cooler Baru"),
                  onPressed: () {
                    Navigator.pop(context);
                    showAddCoolerDialog();
                  },
                ),
              ),
            ),
            Divider(color: AppColors.divider(isDark)),
            _drawerSectionTitle("Data & Otomasi"),
            ListTile(
              leading: Icon(Icons.bar_chart, color: AppColors.textFaint(isDark)),
              title: Text("Riwayat Pemakaian", style: TextStyle(color: AppColors.text(isDark))),
              subtitle: Text("Grafik voltase & durasi nyala per hari",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                if (activeCooler == null) {
                  _showSnack("⚠️ Pilih atau tambah cooler dulu");
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryPage(
                      coolerId: activeCooler!.id,
                      coolerName: activeCooler!.nickname,
                      accentColor: accentColor,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.schedule, color: AppColors.textFaint(isDark)),
              title: Text("Jadwal Otomatis", style: TextStyle(color: AppColors.text(isDark))),
              subtitle: Text("Atur perubahan voltase otomatis per jam",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
              onTap: () async {
                Navigator.pop(context);
                if (activeCooler == null) {
                  _showSnack("⚠️ Pilih atau tambah cooler dulu");
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SchedulePage(
                      coolerId: activeCooler!.id,
                      accentColor: accentColor,
                      availableVoltages: const [5.0, 9.0, 12.0, 15.0],
                    ),
                  ),
                );
                // Muat ulang cache jadwal yang dipakai timer background.
                _schedules = await ScheduleService.loadAll();
              },
            ),
            ListTile(
              leading: Icon(Icons.import_export, color: AppColors.textFaint(isDark)),
              title: Text("Export / Import Konfigurasi", style: TextStyle(color: AppColors.text(isDark))),
              subtitle: Text("Backup daftar cooler & tema ke file .json",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _showBackupDialog();
              },
            ),
            Divider(color: AppColors.divider(isDark)),
            _drawerSectionTitle("Tampilan"),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: AppColors.textFaint(isDark), size: 18),
                  SizedBox(width: 8),
                  Text("Mode Gelap", style: TextStyle(color: AppColors.text(isDark), fontSize: 13)),
                  Spacer(),
                  Switch(
                    value: isDark,
                    activeColor: accentColor,
                    onChanged: (v) async {
                      await ThemeController.setDark(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: colorPalette.map((c) {
                  bool selected = accentColor.value == c.value;
                  return GestureDetector(
                    onTap: () => setState(() => accentColor = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? AppColors.text(isDark) : Colors.transparent, width: 3),
                      ),
                      child: selected ? Icon(Icons.check, size: 16, color: Colors.black) : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 16),
            Divider(color: AppColors.divider(isDark)),
            _drawerSectionTitle("Perawatan"),
            ListTile(
              leading: Icon(Icons.cleaning_services, color: AppColors.textFaint(isDark)),
              title: Text("Bersihkan Cache Aplikasi", style: TextStyle(color: AppColors.text(isDark))),
              subtitle: Text("Hapus data sementara di aplikasi",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
              onTap: () => _confirmClear(
                  "Bersihkan Cache Aplikasi",
                  "Data pencarian Bluetooth sementara akan dihapus. Lanjutkan?",
                  clearAppCache),
            ),
            ListTile(
              leading: Icon(Icons.memory, color: AppColors.textFaint(isDark)),
              title: Text("Bersihkan Cache Modul ESP32", style: TextStyle(color: AppColors.text(isDark))),
              subtitle: Text("Kirim perintah reset cache ke modul ESP32",
                  style: TextStyle(color: AppColors.textFaint(isDark), fontSize: 11)),
              onTap: () => _confirmClear(
                  "Bersihkan Cache Modul ESP32",
                  "Perintah pembersihan cache akan dikirim ke modul ESP32 melalui Bluetooth. Lanjutkan?",
                  clearEsp32Cache),
            ),
            Divider(color: AppColors.divider(isDark)),
            _drawerSectionTitle("Lainnya"),
            ListTile(
              leading: Icon(Icons.info_outline, color: AppColors.textFaint(isDark)),
              title: Text("Tentang", style: TextStyle(color: AppColors.text(isDark))),
              onTap: () {
                Navigator.pop(context);
                showAboutChangelogDialog(context);
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: AppColors.textFaint(ThemeController.isDark),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold)),
    );
  }

  // ===== UI UTAMA =====
  @override
  Widget build(BuildContext context) {
    bool online = status == "🟢 Online";
    final isDark = ThemeController.isDark;
    return Scaffold(
      backgroundColor: AppColors.bg(isDark),
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.surface(isDark),
        foregroundColor: AppColors.text(isDark),
        elevation: 0,
        titleSpacing: 4,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ac_unit, color: accentColor, size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                activeCooler != null ? activeCooler!.nickname.toUpperCase() : "PILIH COOLER",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text(isDark)),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: online ? Colors.green.shade800 : Colors.red.shade800),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online ? Colors.greenAccent : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(online ? "Online" : "Offline",
                        style: TextStyle(
                            fontSize: 12, color: online ? Colors.greenAccent : Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double maxWidth = constraints.maxWidth > 520 ? 480 : constraints.maxWidth;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _modeBanner(),
                      SizedBox(height: 16),
                      _timerCard(),
                      SizedBox(height: 16),
                      _voltageDisplayCard(),
                      SizedBox(height: 20),
                      _sectionLabel("Kontrol Voltase (5V - 15V)"),
                      SizedBox(height: 10),
                      _presetList(),
                      SizedBox(height: 10),
                      _ledToggleCard(),
                      SizedBox(height: 10),
                      _hardwareInfoCard(),
                      SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _actionBtn('Refresh', Icons.refresh, () {
                              if (activeCooler == null) {
                                _showSnack("⚠️ Pilih atau tambah cooler dulu");
                                return;
                              }
                              _connectActiveCooler();
                            }),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _actionBtn('Tambah Cooler', Icons.bluetooth_searching, showAddCoolerDialog),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }

  Widget _modeBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth, color: accentColor, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text("Mode koneksi: Bluetooth",
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Icon(Icons.menu, color: Colors.white38, size: 16),
        ],
      ),
    );
  }

  Widget _timerCard() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer, color: accentColor),
          SizedBox(width: 10),
          Text(uptime, style: TextStyle(fontSize: 26, fontFamily: 'monospace', color: Colors.white)),
        ],
      ),
    );
  }

  Widget _ledToggleCard() {
    Widget modeButton(String mode, String label, IconData icon) {
      bool selected = ledMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => sendLed(mode),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            padding: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? accentColor : Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? Colors.black : Colors.white54, size: 18),
                SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        color: selected ? Colors.black : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text("Lampu RGB", style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Row(
            children: [
              modeButton("off", "Mati", Icons.power_settings_new),
              Expanded(
                child: GestureDetector(
                  onTap: () => sendLed(lastLedEffect),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    padding: EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: ledMode != "off" ? accentColor : Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.lightbulb, color: ledMode != "off" ? Colors.black : Colors.white54, size: 18),
                        SizedBox(height: 4),
                        Text("Nyala",
                            style: TextStyle(
                                color: ledMode != "off" ? Colors.black : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(left: 4, top: 12, bottom: 8),
            child: Text("Efek", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Row(
            children: [
              modeButton("static", "Diam", Icons.circle),
              modeButton("running", "Berjalan", Icons.arrow_forward),
              modeButton("disco", "Disko", Icons.celebration),
              modeButton("bounce", "Bolak-Balik", Icons.swap_horiz),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voltageDisplayCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text('${setVolt.toStringAsFixed(1)}V',
              style: TextStyle(fontSize: 46, fontWeight: FontWeight.bold, color: accentColor)),
          SizedBox(height: 6),
          Text('VOLTASE AKTIF', style: TextStyle(fontSize: 12, color: Colors.grey, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _presetList() {
    final presets = [
      {"v": 5.0, "c": Colors.orangeAccent},
      {"v": 9.0, "c": Colors.blueAccent},
      {"v": 12.0, "c": Colors.redAccent},
      {"v": 15.0, "c": Colors.purpleAccent},
    ];
    return Column(
      children: presets.map((p) {
        double v = p["v"] as double;
        Color c = p["c"] as Color;
        bool selected = setVolt == v;
        return Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c : Colors.transparent, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, color: c),
              SizedBox(width: 12),
              Expanded(
                child: Text('${v.toStringAsFixed(0)} Volt',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              if (selected)
                Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.check_circle, color: c, size: 20),
                ),
              ElevatedButton(
                onPressed: () => sendVoltage(v),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selected ? c : c.withOpacity(0.15),
                  foregroundColor: selected ? Colors.black : c,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(selected ? "Terpilih" : "Pilih"),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _hardwareInfoCard() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.white38, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Modul step-up yang dipakai hanya mendukung 4 level tegangan tetap (5V/9V/12V/15V), jadi pemilihan voltase dilakukan lewat 4 tombol di atas.",
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black38,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
