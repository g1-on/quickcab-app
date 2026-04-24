import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

String get wsUrl {
  const envUrl = String.fromEnvironment('WS_URL');
  if (envUrl.isNotEmpty) return envUrl;

  const isLive = bool.fromEnvironment('LIVE', defaultValue: false);
  if (isLive || kReleaseMode) return 'wss://quickcab-matrix.onrender.com/ws';

  if (kIsWeb) {
    // If running on a hosted domain or specifically requested
    return 'wss://quickcab-matrix.onrender.com/ws';
  }
  
  if (Platform.isAndroid) return 'ws://10.0.2.2:8081/ws';
  return 'ws://localhost:8081/ws';
}

String get apiUrl {
  return wsUrl
      .replaceAll('wss://', 'https://')
      .replaceAll('ws://', 'http://')
      .replaceAll('/ws', '');
}

final WebSocketService ws = WebSocketService();

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  String get driverId => driverState.driverId;
  String get name => driverState.name;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Timer? _reconnectTimer;
  void connect() {
    if (_channel != null) return;
    _doConnect();
  }

  void _doConnect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            debugPrint("WS IN: $msg");
            _controller.add(msg);
          } catch (e) {
            debugPrint("WS Parse Error: $e");
          }
        },
        onError: (e) {
          debugPrint("WS Error: $e");
          _handleDisconnect();
        },
        onDone: () {
          debugPrint("WS Done");
          _handleDisconnect();
        },
      );

      syncDriverProfile();
    } catch (e) {
      debugPrint("WS Connection Exception: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      debugPrint("WS Attempting Reconnect...");
      _doConnect();
    });
  }

  void syncDriverProfile() {
    // Register the driver to show up in Admin Panel
    send({
      'type': 'register_driver',
      'driverId': driverId,
      'name': name,
      'email': driverState.email,
      'phone': '555-5000',
      'city': 'Delhi',
      'vehicleModel': driverState.vehicleModel,
      'vehicleNumber': driverState.vehicleNumber,
      'licenseNumber': 'DL-1234567',
    });
    // Mark as online in admin
    send({'type': 'driver_online', 'driverId': driverId});
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      debugPrint("WS OUT: $data");
      _channel!.sink.add(jsonEncode(data));
    }
  }
}

class DriverProfileState {
  static final DriverProfileState _instance = DriverProfileState._internal();
  factory DriverProfileState() => _instance;
  DriverProfileState._internal();

  String driverId =
      "D_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
  String name = "James Driver";
  String email = "james@quickcab.com";
  String vehicleModel = "Swift Dzire";
  String vehicleNumber = "DL 1C AB 1234";
  bool isLoggedIn = false;

  List<Map<String, dynamic>> trips = [
    {"amount": 450, "route": "Delhi - Noida", "date": "2024-04-21"},
    {"amount": 1200, "route": "Delhi - Agra", "date": "2024-04-20"},
  ];

  int get totalEarnings =>
      trips.fold(0, (sum, t) => sum + (t['amount'] as int));
  int get tripCount => trips.length;

  void addTrip(int amount, String route) {
    trips.insert(0, {
      "amount": amount,
      "route": route,
      "date": DateTime.now().toIso8601String().substring(0, 10),
    });
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('driverId');
    if (savedId != null) {
      driverId = savedId;
    } else {
      await prefs.setString('driverId', driverId);
    }
    
    name = prefs.getString('name') ?? name;
    email = prefs.getString('email') ?? email;
    vehicleModel = prefs.getString('vehicleModel') ?? vehicleModel;
    vehicleNumber = prefs.getString('vehicleNumber') ?? vehicleNumber;
    isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> login({required String email, required String password}) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final doc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(cred.user!.uid)
        .get();
    if (doc.exists) {
      await _saveSession(cred.user!.uid, doc.data()!);
    }
  }

  Future<void> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final data = {
      'name': name,
      'email': email,
      'role': 'driver',
      'vehicleModel': vehicleModel,
      'vehicleNumber': vehicleNumber,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(cred.user!.uid)
        .set(data);
    await _saveSession(cred.user!.uid, data);
  }

  Future<void> _saveSession(String uid, Map<String, dynamic> data) async {
    driverId = uid;
    name = data['name'];
    email = data['email'];
    vehicleModel = data['vehicleModel'] ?? vehicleModel;
    vehicleNumber = data['vehicleNumber'] ?? vehicleNumber;
    isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driverId', driverId);
    await prefs.setString('name', name);
    await prefs.setString('email', email);
    await prefs.setString('vehicleModel', vehicleModel);
    await prefs.setString('vehicleNumber', vehicleNumber);
    await prefs.setBool('isLoggedIn', true);
  }
}

final driverState = DriverProfileState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await driverState.init();
    await notificationService.init();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const QuickCabDriverApp());
}

class QuickCabDriverApp extends StatelessWidget {
  const QuickCabDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickCab Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Color(0xFFEEEEEE),
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
      home: driverState.isLoggedIn ? const DriverHome() : const LoginScreen(),
    );
  }
}

// ================= WIDGETS =================

class BlackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;

  const BlackButton({super.key, required this.onPressed, required this.text});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class LiveMapWidget extends StatelessWidget {
  final List<Marker> markers;
  final LatLng initialCenter;
  final double initialZoom;
  final MapController? controller;

  const LiveMapWidget({
    super.key,
    this.markers = const [],
    this.initialCenter = const LatLng(28.6139, 77.2100), // Delhi
    this.initialZoom = 13.0,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.quickcab_driver',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class MockMapBackground extends StatelessWidget {
  final bool showRipple;
  const MockMapBackground({super.key, this.showRipple = true});

  @override
  Widget build(BuildContext context) {
    return const LiveMapWidget();
  }
}

class LocationRipple extends StatefulWidget {
  const LocationRipple({super.key});

  @override
  State<LocationRipple> createState() => _LocationRippleState();
}

class _LocationRippleState extends State<LocationRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              Opacity(
                opacity: 1.0 - _controller.value,
                child: Container(
                  width: 100 * _controller.value,
                  height: 100 * _controller.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.04)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(100, 0), Offset(150, size.height), roadPaint);
    canvas.drawLine(Offset(0, 200), Offset(size.width, 250), roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

//// ================= LOGIN =================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passController = TextEditingController();

  void _handleLogin() async {
    if (emailController.text.isNotEmpty && passController.text.isNotEmpty) {
      try {
        await driverState.login(
          email: emailController.text,
          password: passController.text,
        );
        ws.connect();
        ws.syncDriverProfile();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverHome()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter email and password")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 100),
              const Text(
                "QuickCab Driver",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 64),
              QuickCabTextField(
                controller: emailController,
                hint: "Driver Email",
                icon: Icons.email_outlined,
                dark: true,
              ),
              const SizedBox(height: 16),
              QuickCabTextField(
                controller: passController,
                hint: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
                dark: true,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _handleLogin,
                child: const Text(
                  "Go Online",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "New to QuickCab? ",
                    style: TextStyle(color: Colors.white70),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverSignupScreen(),
                      ),
                    ),
                    child: const Text(
                      "Sign Up to Drive",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverSignupScreen extends StatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  State<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends State<DriverSignupScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final modelController = TextEditingController();
  final plateController = TextEditingController();
  final passController = TextEditingController();

  void _handleSignup() async {
    if (nameController.text.isNotEmpty &&
        emailController.text.isNotEmpty &&
        passController.text.isNotEmpty) {
      try {
        await driverState.signup(
          name: nameController.text,
          email: emailController.text,
          password: passController.text,
        );
        // Also save vehicle info locally for now (can be added to signup API later)
        driverState.vehicleModel = modelController.text;
        driverState.vehicleNumber = plateController.text;

        ws.connect();
        ws.syncDriverProfile();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DriverHome()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Complete your details")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Partner with us",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const Text(
              "Start earning in Delhi/NCR today",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            QuickCabTextField(
              controller: nameController,
              hint: "Full Name",
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            QuickCabTextField(
              controller: emailController,
              hint: "Email address",
              icon: Icons.email_outlined,
            ),
            const SizedBox(height: 16),
            QuickCabTextField(
              controller: passController,
              hint: "Create Password",
              icon: Icons.lock_outline,
              isPassword: true,
            ),
            const SizedBox(height: 16),
            const Text(
              "VEHICLE INFO",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            QuickCabTextField(
              controller: modelController,
              hint: "Vehicle Model (e.g. Swift)",
              icon: Icons.directions_car_outlined,
            ),
            const SizedBox(height: 16),
            QuickCabTextField(
              controller: plateController,
              hint: "License Plate #",
              icon: Icons.assignment_outlined,
            ),
            const SizedBox(height: 32),
            BlackButton(onPressed: _handleSignup, text: "Begin Driving"),
          ],
        ),
      ),
    );
  }
}

class QuickCabTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool dark;

  const QuickCabTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: TextStyle(color: dark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: dark ? Colors.white38 : Colors.grey),
        prefixIcon: Icon(icon, color: dark ? Colors.white70 : Colors.black),
        filled: true,
        fillColor: dark
            ? Colors.white.withOpacity(0.12)
            : const Color(0xFFF3F3F3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

//// ================= HOME =================

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late StreamSubscription _sub;
  Map<String, dynamic>? activeRequest;
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();

    // Ensure WebSocket is connected
    ws.connect();

    // Register as a driver to receive ride requests
    ws.send({
      'type': 'register_driver',
      'driverId': ws.driverId,
      'name': driverState.name,
      'vehicleModel': driverState.vehicleModel,
      'vehicleNumber': driverState.vehicleNumber,
    });
    
    // Explicitly go online
    ws.send({
      'type': 'driver_online',
      'driverId': ws.driverId,
    });

    _checkLocation();
    _determinePosition();
    _sub = ws.stream.listen((msg) {
      if (msg['type'] == 'ride_request') {
        if (mounted) {
          setState(() {
            activeRequest = msg;
          });
          try {
            notificationService.showNotification(
              title: "New Ride Request!",
              body: "Pickup: ${msg['pickup']} • Drop: ${msg['drop']}",
            );
          } catch (e) {
            debugPrint("Notification Error: $e");
          }
        }
      }
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    }
  }

  void _checkLocation() {
    if (kIsWeb) {
      _determinePosition();
      return;
    }
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        final status = await Permission.locationWhenInUse.status;
        if (!status.isGranted) {
          await showModalBottomSheet(
            context: context,
            isDismissible: false,
            enableDrag: false,
            builder: (context) => const LocationPermissionSheet(),
          );
          if (mounted) _determinePosition();
        } else {
          _determinePosition();
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _reviewRequest() {
    if (activeRequest == null) return;

    ws.send({
      'type': 'join_ride',
      'rideId': activeRequest!['rideId'],
      'role': 'driver',
      'driverId': ws.driverId,
    });

    final rideId = activeRequest!['rideId'];
    final pickup = activeRequest!['pickup'];
    final drop = activeRequest!['drop'];
    final userOffer = activeRequest!['userOffer'] ?? 0;
    final userName = activeRequest!['userName'];

    setState(() {
      activeRequest = null;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBargainScreen(
          rideId: rideId,
          pickup: pickup,
          drop: drop,
          userOffer: userOffer,
          userName: userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          LiveMapWidget(
            initialCenter: _currentLocation ?? const LatLng(28.6139, 77.2100),
            markers: _currentLocation != null ? [
              Marker(
                point: _currentLocation!,
                width: 40,
                height: 40,
                child: const LocationRipple(),
              )
            ] : [],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverProfileScreen()),
              ),
              child: const CircleAvatar(
                radius: 26,
                backgroundColor: Colors.black,
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          Positioned(
            top: 70,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "TODAY'S EARNINGS",
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "4.95",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "₹${driverState.totalEarnings}.00",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStat("${driverState.tripCount}", "TRIPS"),
                      _buildMiniStat("8.4 hrs", "ONLINE"),
                      _buildMiniStat("98%", "ACCEPTANCE"),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: activeRequest == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(height: 20),
                        CircularProgressIndicator(color: Colors.black),
                        SizedBox(height: 20),
                        Text(
                          "Looking for rides near you...",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        SizedBox(height: 40),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "New Ride Request",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              "₹${activeRequest!['userOffer']}",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF00C853),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Pickup: ${activeRequest!['pickup']}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Drop: ${activeRequest!['drop']}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        BlackButton(
                          onPressed: _reviewRequest,
                          text: "Negotiate Offer",
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class LocationPermissionSheet extends StatelessWidget {
  const LocationPermissionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_searching_rounded,
            size: 64,
            color: Colors.black,
          ),
          const SizedBox(height: 24),
          const Text(
            "Enable Tracking",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            "Drivers share their location to receive ride requests and provide accurate ETAs to riders.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await notificationService.requestPermissions();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              "Allow Permissions",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Not Now",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Driver Profile",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: Color(0xFFF3F3F3),
                child: Icon(Icons.person, size: 40, color: Colors.black),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driverState.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    driverState.email,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Text(
            "VEHICLE DETAILS",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          _buildProfileItem(
            context,
            Icons.directions_car_rounded,
            driverState.vehicleModel,
            driverState.vehicleNumber,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Vehicle details are verified")),
              );
            },
          ),
          _buildProfileItem(
            context,
            Icons.verified_user_rounded,
            "Documents",
            "License & Insurance Verified",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("All security documents are up-to-date"),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            "TRIP HISTORY",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          ...driverState.trips.map(
            (trip) => _buildProfileItem(
              context,
              Icons.history_rounded,
              "₹${trip['amount']}",
              "${trip['route']} • ${trip['date']}",
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            "ACCOUNT",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          _buildProfileItem(
            context,
            Icons.account_balance_wallet_rounded,
            "Total Earnings",
            "₹${driverState.totalEarnings}.00",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Redirecting to detailed reports..."),
                ),
              );
            },
          ),
          _buildProfileItem(
            context,
            Icons.logout_rounded,
            "Log Out",
            "Go offline & exit",
            color: Colors.red,
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem(
    BuildContext context,
    IconData icon,
    String title,
    String sub, {
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.black, size: 28),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

//// ================= BARGAIN =================

class DriverBargainScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String drop;
  final int userOffer;
  final String? userName;

  const DriverBargainScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.drop,
    required this.userOffer,
    this.userName,
  });

  @override
  State<DriverBargainScreen> createState() => _DriverBargainScreenState();
}

class _DriverBargainScreenState extends State<DriverBargainScreen> {
  List<Map<String, dynamic>> msgs = [];
  final controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription _sub;

  int _latestPrice = 0;

  @override
  void initState() {
    super.initState();
    _latestPrice = widget.userOffer;
    msgs.add({"text": "₹${widget.userOffer}", "me": false});

    ws.send({
      'type': 'join_ride',
      'rideId': widget.rideId,
      'role': 'driver',
      'driverId': ws.driverId,
    });

    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'joined') {
        final history = msg['history'] as List?;
        if (history != null && mounted) {
          setState(() {
            msgs.clear();
            for (var entry in history) {
              msgs.add({
                "text": entry['text'],
                "me": entry['from'] == 'driver',
              });
            }
          });
          _scrollToBottom();
        }
        return;
      }

      if (msg['type'] == 'user_offer') {
        int offer = msg['price'] ?? 0;
        if (offer > 0 && mounted) {
          setState(() {
            _latestPrice = offer;
            msgs.add({"text": "₹$offer", "me": false});
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'driver_offer') {
        if (mounted) {
          setState(() {
            // Only add if it's from me, or if we want to show other driver offers (usually just me)
            if (msg['driverId'] == ws.driverId) {
              msgs.add({
                "text": "Your new offer: ₹${msg['price']}",
                "me": true,
              });
            }
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'chat_message') {
        if (mounted) {
          if (msg['role'] == 'driver') return; // Already added locally
          setState(() {
            msgs.add({
              "text": msg['text'],
              "me": msg['role'] == 'driver',
              "from": msg['role'] == 'user'
                  ? (msg['userName'] ?? 'User')
                  : 'You',
            });
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'ride_booked' || msg['type'] == 'accept') {
        if (mounted) {
          final winnerDriverId = msg['driverId'];
          if (winnerDriverId != null && winnerDriverId != ws.driverId) {
            // Someone else got the ride
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Another driver got the ride.")),
            );
            Navigator.pop(context);
            return;
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverExecutionScreen(
                rideId: widget.rideId,
                price: msg['price'] ?? _latestPrice,
                pickup: widget.pickup,
                drop: widget.drop,
                userName: widget.userName,
              ),
            ),
          );
        }
      } else if (msg['type'] == 'negotiation_cancelled') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User cancelled negotiation.")),
          );
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void sendOffer() {
    String text = controller.text.trim();
    if (text.isEmpty) return;

    int? price = int.tryParse(text);
    if (price != null && price > 0) {
      ws.send({
        'type': 'driver_offer',
        'rideId': widget.rideId,
        'driverId': ws.driverId,
        'price': price,
        'driverName': driverState.name,
        'vehicleModel': driverState.vehicleModel,
        'vehicleNumber': driverState.vehicleNumber,
      });
      setState(() {
        _latestPrice = price;
      });
    } else {
      ws.send({
        'type': 'chat_message',
        'rideId': widget.rideId,
        'role': 'driver',
        'text': text,
        'driverId': ws.driverId,
        'driverName': driverState.name,
      });
      // Show locally immediately for better UX
      setState(() {
        msgs.add({
          "text": text,
          "me": true,
          "from": "You",
        });
      });
    }
    controller.clear();
    _scrollToBottom();
  }

  void _showPriceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final priceC = TextEditingController();
        return AlertDialog(
          title: const Text(
            "Make a Counter Offer",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: priceC,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Enter amount (e.g. 600)",
              prefixText: "₹ ",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final p = int.tryParse(priceC.text);
                if (p != null && p > 0) {
                  ws.send({
                    'type': 'driver_offer',
                    'rideId': widget.rideId,
                    'driverId': ws.driverId,
                    'price': p,
                    'driverName': driverState.name,
                    'vehicleModel': driverState.vehicleModel,
                    'vehicleNumber': driverState.vehicleNumber,
                  });
                  setState(() {
                    _latestPrice = p;
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text("Send Offer"),
            ),
          ],
        );
      },
    );
  }

  void acceptDeal() {
    ws.send({
      'type': 'accept',
      'rideId': widget.rideId,
      'role': 'driver',
      'price': _latestPrice,
      'driverName': driverState.name,
      'vehicleModel': driverState.vehicleModel,
      'vehicleNumber': driverState.vehicleNumber,
    });
  }

  void cancelNegotiation() {
    ws.send({
      'type': 'cancel_negotiation',
      'rideId': widget.rideId,
      'reason': 'Driver rejected the offer.',
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isUserTurn = msgs.isNotEmpty && !msgs.last["me"];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Bargain Chat",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: cancelNegotiation,
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${widget.pickup} → ${widget.drop}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: msgs.length,
              itemBuilder: (context, index) {
                var m = msgs[index];
                bool me = m["me"];
                return Column(
                  crossAxisAlignment: me
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: me ? Colors.black : const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: me ? Radius.zero : null,
                          bottomLeft: !me ? Radius.zero : null,
                        ),
                      ),
                      child: Text(
                        m["text"],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: me ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        me ? "You" : "Passenger",
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          if (isUserTurn)
            Padding(
              padding: const EdgeInsets.all(20),
              child: BlackButton(
                onPressed: acceptDeal,
                text: "Accept Deal for ₹$_latestPrice",
              ),
            ),

          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showPriceDialog,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.currency_rupee,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      hintText: "Reply to user...",
                      filled: true,
                      fillColor: const Color(0xFFF3F3F3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: sendOffer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//// ================= DRIVER EXECUTION =================

class DriverExecutionScreen extends StatefulWidget {
  final String rideId;
  final int price;
  final String pickup;
  final String drop;
  final String? userName;

  const DriverExecutionScreen({
    super.key,
    required this.rideId,
    required this.price,
    required this.pickup,
    required this.drop,
    this.userName,
  });

  @override
  State<DriverExecutionScreen> createState() => _DriverExecutionScreenState();
}

class _DriverExecutionScreenState extends State<DriverExecutionScreen> {
  late StreamSubscription _sub;
  bool rideStarted = false;
  double progress = 0.0;
  final otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ws.send({
      'type': 'join_ride',
      'rideId': widget.rideId,
      'role': 'driver',
      'driverId': ws.driverId,
    });
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'otp_verified' || msg['type'] == 'ride_started') {
        if (mounted) {
          setState(() {
            rideStarted = true;
          });
        }
      } else if (msg['type'] == 'otp_invalid') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid OTP! Try again.")),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _verifyOtp() {
    ws.send({
      'type': 'verify_start_otp',
      'rideId': widget.rideId,
      'otp': otpController.text.trim(),
    });
  }

  void _updateProgress(double value) {
    setState(() {
      progress = value;
    });
    // Push progress directly to User App
    ws.send({
      'type': 'driver_location',
      'rideId': widget.rideId,
      'progress': progress,
      'lat': 28.7041, // mock coordinate
      'lng': 77.1025, // mock coordinate
    });

    if (progress == 1.0) {
      ws.send({
        'type': 'ride_complete',
        'rideId': widget.rideId,
        'finalPrice': widget.price,
      });
      // We now wait for the driver to click "Finish & Record Trip" manually
    }
  }

  void _finishRide() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverRatingScreen(rideId: widget.rideId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const MockMapBackground(),

          Positioned(
            left: 50 + (250 * progress),
            top: 400 - (200 * progress),
            child: const Icon(
              Icons.local_taxi,
              size: 40,
              color: Colors.blue,
            ), // Driver car is blue
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: !rideStarted
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "Arrived at Pickup",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "${widget.pickup} → ${widget.drop}",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Ask user for OTP to verify.",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: otpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLength: 4,
                            decoration: InputDecoration(
                              hintText: "0000",
                              filled: true,
                              fillColor: const Color(0xFFF3F3F3),
                              counterText: "",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          BlackButton(
                            onPressed: _verifyOtp,
                            text: "Verify OTP & Start Ride",
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "LIVE TRACKING",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.userName != null
                                        ? "Driving ${widget.userName} to Drop-off"
                                        : "Driving to Drop-off",
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "${widget.pickup} → ${widget.drop}",
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "₹${widget.price}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "Slide to update routing progress (Demo):",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          Slider(
                            value: progress,
                            onChanged: _updateProgress,
                            activeColor: Colors.black,
                            inactiveColor: Colors.grey[300],
                          ),
                          const SizedBox(height: 10),
                          if (progress == 1.0) ...[
                            const Text(
                              "Ride Complete! Redirecting...",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                driverState.addTrip(
                                  widget.price,
                                  "${widget.pickup} - ${widget.drop}",
                                );
                                _finishRide();
                              },
                              child: const Text("Finish & Record Trip"),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverRatingScreen extends StatefulWidget {
  final String rideId;
  const DriverRatingScreen({super.key, required this.rideId});

  @override
  State<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends State<DriverRatingScreen> {
  int rating = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Rate Rider",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "How was your experience with the passenger?",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 56,
                      color: Colors.amber,
                    ),
                    onPressed: () => setState(() => rating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  ws.send({
                    'type': 'submit_rating',
                    'rideId': widget.rideId,
                    'role': 'driver',
                    'rating': rating,
                  });
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverHome()),
                    (route) => false,
                  );
                },
                child: const Text(
                  "Done",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
