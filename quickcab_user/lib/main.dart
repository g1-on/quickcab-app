import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// Determines localhost equivalent or reads production environment url
String get wsUrl {
  const envUrl = String.fromEnvironment('WS_URL');
  if (envUrl.isNotEmpty) return envUrl;

  const isLive = bool.fromEnvironment('LIVE', defaultValue: false);
  if (isLive) return 'wss://quickcab-matrix.onrender.com/ws';

  if (kIsWeb) return 'ws://localhost:8081/ws';
  if (!kIsWeb && Platform.isAndroid) return 'ws://10.0.2.2:8081/ws';
  return 'ws://localhost:8081/ws';
}

String get apiUrl {
  return wsUrl
      .replaceAll('wss://', 'https://')
      .replaceAll('ws://', 'http://')
      .replaceAll('/ws', '');
}

// Global WebSocket Service
final WebSocketService ws = WebSocketService();

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  String get userId => userState.userId;
  String get name => userState.name;

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

      syncUserProfile();
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

  void syncUserProfile() {
    // Register the user to show up in Admin Panel
    send({
      'type': 'register_user',
      'userId': userId,
      'name': name,
      'email': userState.email,
      'phone': '555-0199',
      'city': 'Delhi',
    });
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      debugPrint("WS OUT: $data");
      _channel!.sink.add(jsonEncode(data));
    }
  }
}

class UserProfileState {
  static final UserProfileState _instance = UserProfileState._internal();
  factory UserProfileState() => _instance;
  UserProfileState._internal();

  String userId =
      "U_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
  String name = "Guest";
  String email = "guest@example.com";
  bool isLoggedIn = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? userId;
    name = prefs.getString('name') ?? "Guest";
    email = prefs.getString('email') ?? "guest@example.com";
    isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (prefs.getString('userId') == null) {
      await prefs.setString('userId', userId);
    }
  }

  Future<void> login({required String email, required String password}) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final doc = await FirebaseFirestore.instance
        .collection('users')
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
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('users')
        .doc(cred.user!.uid)
        .set(data);
    await _saveSession(cred.user!.uid, data);
  }

  Future<void> _saveSession(String uid, Map<String, dynamic> data) async {
    userId = uid;
    name = data['name'];
    email = data['email'];
    isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    await prefs.setString('name', name);
    await prefs.setString('email', email);
    await prefs.setBool('isLoggedIn', true);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    isLoggedIn = false;
  }
}

final userState = UserProfileState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await userState.init();
    await notificationService.init();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
    // Continue anyway to avoid white screen
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const QuickCabApp());
}

class QuickCabApp extends StatelessWidget {
  const QuickCabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickCab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Color(0xFFF3F3F3),
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.black),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
      home: userState.isLoggedIn ? const HomeScreen() : const LoginScreen(),
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
    this.initialCenter = const LatLng(28.6139, 77.2090), // Delhi
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
          userAgentPackageName: 'com.example.quickcab_user',
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
      ..color = Colors.black.withOpacity(0.03)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(100, 0), Offset(150, size.height), roadPaint);
    canvas.drawLine(Offset(0, 400), Offset(size.width, 450), roadPaint);
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
        await userState.login(
          email: emailController.text,
          password: passController.text,
        );
        ws.connect();
        ws.syncUserProfile();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
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
      ).showSnackBar(const SnackBar(content: Text("Please enter credentials")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "QuickCab",
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 48),
              const Text(
                "Welcome back",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              QuickCabTextField(
                controller: emailController,
                hint: "Email",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              QuickCabTextField(
                controller: passController,
                hint: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
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
                onPressed: _handleLogin,
                child: const Text(
                  "Log In",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    ),
                    child: const Text(
                      "Sign Up",
                      style: TextStyle(
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

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passController = TextEditingController();

  void _handleSignup() async {
    if (nameController.text.isNotEmpty &&
        emailController.text.isNotEmpty &&
        passController.text.isNotEmpty) {
      try {
        await userState.signup(
          name: nameController.text,
          email: emailController.text,
          password: passController.text,
        );
        ws.connect();
        ws.syncUserProfile();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
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
      ).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
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
                hint: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
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
                onPressed: _handleSignup,
                child: const Text(
                  "Create Profile",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
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

  const QuickCabTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.black),
        filled: true,
        fillColor: const Color(0xFFF3F3F3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }
}

//// ================= HOME =================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  void _checkLocation() {
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

    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    }
  }

  void _openBookingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const BookingSheet(),
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
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
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
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 25,
                    offset: Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Where to?",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _openBookingSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F3F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.search_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Enter destination",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildQuickAction(
                        Icons.home_rounded,
                        "Home",
                        "Add home address",
                      ),
                      const SizedBox(width: 16),
                      _buildQuickAction(
                        Icons.work_rounded,
                        "Work",
                        "Add work address",
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text(
                    "Recent Places",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRecentItem("Connaught Place", "Delhi, India"),
                  _buildRecentItem("Agra Fort", "Agra, Uttar Pradesh"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Colors.grey, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedRouteChip(String city) {
    return ActionChip(
      label: Text(city),
      backgroundColor: const Color(0xFFF3F3F3),
      onPressed: _openBookingSheet,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        color: Colors.black,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          const Icon(Icons.location_on_rounded, size: 64, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            "Location Access",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            "Our maps work best when we know where you are. This helps drivers find you faster.",
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
              "Allow Access",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Maybe Later",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Profile",
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
                    userState.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    userState.email,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Text(
            "SAVED PLACES",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          _buildProfileItem(
            context,
            Icons.home_rounded,
            "Home",
            "Delhi",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Home location set to Delhi")),
              );
            },
          ),
          _buildProfileItem(
            context,
            Icons.work_rounded,
            "Work",
            "Noida Sector 62",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Work location set to Noida")),
              );
            },
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
            Icons.payments_rounded,
            "Payment Methods",
            "Uber Cash, UPI",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Payment methods management coming soon"),
                ),
              );
            },
          ),
          _buildProfileItem(
            context,
            Icons.history_rounded,
            "Ride History",
            "24 recorded trips",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Loading ride history...")),
              );
            },
          ),
          _buildProfileItem(
            context,
            Icons.logout_rounded,
            "Log Out",
            "End session",
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

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key});

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final pickupController = TextEditingController(text: "Delhi");
  final dropController = TextEditingController(text: "Agra");
  final priceController = TextEditingController();

  String vehicleType = "Uber Go";
  String paymentMethod = "Cash";
  String profile = "For Me";

  int getEstimatedFare() {
    // Basic route pricing matrix (One-way)
    Map<String, Map<String, int>> pricing = {
      "Delhi-Agra": {
        "Uber Go": 2200,
        "Uber Premier": 2800,
        "Uber XL": 3500,
        "Intercity": 4500,
      },
      "Delhi-Jaipur": {
        "Uber Go": 2800,
        "Uber Premier": 3500,
        "Uber XL": 4500,
        "Intercity": 5500,
      },
      "Agra-Jaipur": {
        "Uber Go": 2500,
        "Uber Premier": 3200,
        "Uber XL": 4200,
        "Intercity": 5000,
      },
    };

    String p = pickupController.text;
    String d = dropController.text;
    String route = "$p-$d";
    String reverseRoute = "$d-$p";

    var base =
        pricing[route] ??
        pricing[reverseRoute] ??
        {
          "Uber Go": 2000,
          "Uber Premier": 2500,
          "Uber XL": 3200,
          "Intercity": 4000,
        };
    return base[vehicleType] ?? 2000;
  }

  void requestRide() {
    String p = pickupController.text.trim();
    String d = dropController.text.trim();
    if (p.isEmpty || d.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both locations")),
      );
      return;
    }

    int price = int.tryParse(priceController.text) ?? getEstimatedFare();
    final String rideId =
        "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}";

    ws.send({
      'type': 'ride_request',
      'rideId': rideId,
      'pickup': p,
      'drop': d,
      'userOffer': price,
      'userId': ws.userId,
      'userName': userState.name,
      'vehicleType': vehicleType,
      'paymentMethod': paymentMethod,
    });

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BargainScreen(
          rideId: rideId,
          initialPrice: price,
          pickup: p,
          drop: d,
          vehicleType: vehicleType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int currentFare = getEstimatedFare();
    if (priceController.text.isEmpty) {
      priceController.text = currentFare.toString();
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 0,
        right: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildLocationField(
                  pickupController,
                  "Pickup Location",
                  Icons.my_location,
                  Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildLocationField(
                  dropController,
                  "Destination",
                  Icons.location_on,
                  Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Category Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildCategoryTab("Economy", true),
                _buildCategoryTab("Premium", false),
                _buildCategoryTab("Rental", false),
                _buildCategoryTab("Outstation", false),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ride Options List
          SizedBox(
            height: 280,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                _buildVehicleItem(
                  "Uber Go",
                  "Fast & Affordable",
                  2200,
                  Icons.directions_car_filled_rounded,
                ),
                _buildVehicleItem(
                  "Uber Premier",
                  "High-rated drivers",
                  2800,
                  Icons.stars_rounded,
                ),
                _buildVehicleItem(
                  "Uber XL",
                  "Spacious 6-seater",
                  3500,
                  Icons.airport_shuttle_rounded,
                ),
                _buildVehicleItem(
                  "Intercity",
                  "Comfortable outstation",
                  4500,
                  Icons.map_rounded,
                ),
              ],
            ),
          ),

          // Payment & Schedule Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              children: [
                _buildActionChip(
                  Icons.payment,
                  paymentMethod,
                  () => _showPaymentPicker(),
                ),
                const SizedBox(width: 8),
                _buildActionChip(Icons.local_offer, "Promo", () {}),
                const Spacer(),
                _buildActionChip(Icons.schedule, "Schedule", () {}),
              ],
            ),
          ),

          // Confirm Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: requestRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  "Confirm $vehicleType",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              "Price is negotiable with drivers",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(String title, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.black : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Colors.black : Colors.grey.shade300,
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildActionChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select Payment Method",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.money),
              title: const Text("Cash"),
              onTap: () {
                setState(() => paymentMethod = "Cash");
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text("Wallet"),
              onTap: () {
                setState(() => paymentMethod = "Wallet");
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text("UPI"),
              onTap: () {
                setState(() => paymentMethod = "UPI");
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField(
    TextEditingController controller,
    String hint,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: color, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _buildVehicleItem(
    String title,
    String sub,
    int basePrice,
    IconData icon,
  ) {
    bool isSelected = vehicleType == title;
    return GestureDetector(
      onTap: () => setState(() => vehicleType = title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black.withOpacity(0.02) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.black, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              "₹$basePrice",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPill(String text, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(
    String title,
    String sub,
    int basePrice,
    IconData icon,
  ) {
    bool isSelected = vehicleType == title;
    return GestureDetector(
      onTap: () => setState(() => vehicleType = title),
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey.shade200,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.black,
              size: 32,
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                color: isSelected ? Colors.white70 : Colors.grey,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//// ================= BARGAIN =================

class BargainScreen extends StatefulWidget {
  final String rideId;
  final int initialPrice;
  final String pickup;
  final String drop;
  final String vehicleType;

  const BargainScreen({
    super.key,
    required this.rideId,
    required this.initialPrice,
    required this.pickup,
    required this.drop,
    required this.vehicleType,
  });

  @override
  State<BargainScreen> createState() => _BargainScreenState();
}

class _BargainScreenState extends State<BargainScreen> {
  List<Map<String, dynamic>> msgs = [];
  Map<String, Map<String, dynamic>> driverOffers =
      {}; // driverId -> { price, driverName, ... }
  final controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription _sub;

  int _latestUserPrice = 0;

  @override
  void initState() {
    super.initState();
    _latestUserPrice = widget.initialPrice;
    msgs.add({
      "text": "₹${widget.initialPrice} for ${widget.vehicleType}",
      "me": true,
    });

    ws.send({'type': 'join_ride', 'rideId': widget.rideId, 'role': 'user'});

    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'joined') {
        final history = msg['history'] as List?;
        if (history != null && mounted) {
          setState(() {
            msgs.clear();
            for (var entry in history) {
              msgs.add({"text": entry['text'], "me": entry['from'] == 'user'});
            }
          });
          _scrollToBottom();
        }
        return;
      }

      if (msg['type'] == 'driver_offer') {
        int offer = msg['price'] ?? 0;
        String? driverId = msg['driverId'];
        if (offer > 0 && driverId != null && mounted) {
          notificationService.showNotification(
            title: "New Offer!",
            body: "₹$offer from ${msg['driverName'] ?? 'Driver'}",
          );
          setState(() {
            driverOffers[driverId] = {
              'price': offer,
              'driverName': msg['driverName'] ?? 'Driver',
              'vehicleModel': msg['vehicleModel'] ?? 'Unknown Vehicle',
              'vehicleNumber': msg['vehicleNumber'] ?? '---',
            };
            msgs.add({
              "text": "₹$offer from ${msg['driverName'] ?? 'Driver'}",
              "me": false,
            });
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'user_offer') {
        if (mounted) {
          setState(() {
            msgs.add({"text": "Your new offer: ₹${msg['price']}", "me": true});
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'ride_booked' || msg['type'] == 'accept') {
        if (mounted) {
          final winnerDriverId = msg['driverId'];
          final winnerOffer = winnerDriverId != null
              ? driverOffers[winnerDriverId]
              : null;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverScreen(
                rideId: widget.rideId,
                price: msg['price'] ?? _latestUserPrice,
                pickup: widget.pickup,
                drop: widget.drop,
                driverName: msg['driverName'] ?? winnerOffer?['driverName'],
                vehicleModel:
                    msg['vehicleModel'] ?? winnerOffer?['vehicleModel'],
                vehicleNumber:
                    msg['vehicleNumber'] ?? winnerOffer?['vehicleNumber'],
              ),
            ),
          );
        }
      } else if (msg['type'] == 'chat_message') {
        if (mounted) {
          if (msg['role'] == 'user') return; // Already added locally
          if (msg['role'] == 'driver') {
            notificationService.showNotification(
              title: "Message from Driver",
              body: msg['text'],
            );
          }
          setState(() {
            msgs.add({
              "text": msg['text'],
              "me": msg['role'] == 'user',
              "from": msg['role'] == 'driver'
                  ? (msg['driverName'] ?? 'Driver')
                  : 'You',
            });
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'negotiation_cancelled') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Negotiation cancelled.")),
          );
          Navigator.pop(context);
        }
      }
    });

    // Mock an offer if none received after some time (legacy demo logic)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && driverOffers.isEmpty) {
        ws.send({
          'type': 'driver_offer',
          'rideId': widget.rideId,
          'price': widget.initialPrice + 150,
          'driverId': 'D_MOCK_1',
          'driverName': 'Ravi (Mock)',
          'vehicleModel': 'Swift Dzire',
          'vehicleNumber': 'DL 1C AB 1234',
        });
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
      ws.send({'type': 'user_offer', 'rideId': widget.rideId, 'price': price});
      setState(() {
        _latestUserPrice = price;
      });
    } else {
      ws.send({
        'type': 'chat_message',
        'rideId': widget.rideId,
        'role': 'user',
        'text': text,
        'userName': userState.name,
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
            "Make a Price Offer",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: priceC,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Enter amount (e.g. 500)",
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
                    'type': 'user_offer',
                    'rideId': widget.rideId,
                    'price': p,
                  });
                  setState(() {
                    _latestUserPrice = p;
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

  void acceptDeal(String driverId, int price) {
    ws.send({
      'type': 'accept',
      'rideId': widget.rideId,
      'role': 'user',
      'price': price,
      'driverId': driverId,
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sort offers by price (lowest first)
    final sortedOffers = driverOffers.entries.toList()
      ..sort(
        (a, b) => (a.value['price'] as int).compareTo(b.value['price'] as int),
      );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              "Bargaining with Drivers",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              widget.vehicleType,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () {
              ws.send({'type': 'cancel_negotiation', 'rideId': widget.rideId});
              Navigator.pop(context);
            },
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
                const Icon(Icons.location_on, size: 16, color: Colors.blue),
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
                Text(
                  "Offer: ₹$_latestUserPrice",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.blue,
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
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: me ? Colors.black : const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12).copyWith(
                          bottomRight: me ? Radius.zero : null,
                          bottomLeft: !me ? Radius.zero : null,
                        ),
                        border: !me
                            ? Border.all(color: Colors.grey.shade200)
                            : null,
                      ),
                      child: Text(
                        m["text"],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: me ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          if (sortedOffers.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Active Driver Offers",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: sortedOffers.length,
                      itemBuilder: (context, index) {
                        final entry = sortedOffers[index];
                        final driverId = entry.key;
                        final offer = entry.value;
                        final isLowest = index == 0;

                        return Container(
                          width: 260,
                          margin: const EdgeInsets.only(right: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isLowest ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isLowest
                                  ? Colors.black
                                  : Colors.grey.shade200,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isLowest
                                        ? Colors.white24
                                        : Colors.grey.shade100,
                                    child: Icon(
                                      Icons.person,
                                      color: isLowest
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          offer['driverName'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: isLowest
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        Text(
                                          "4.9 ★",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isLowest
                                                ? Colors.white70
                                                : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    "₹${offer['price']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                      color: Color(0xFF00C853),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "${offer['vehicleModel']} • ${offer['vehicleNumber']}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isLowest
                                      ? Colors.white70
                                      : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLowest
                                      ? Colors.white
                                      : Colors.black,
                                  foregroundColor: isLowest
                                      ? Colors.black
                                      : Colors.white,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () =>
                                    acceptDeal(driverId, offer['price']),
                                child: const Text(
                                  "Accept Offer",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                // Separate Bargaining Option
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
                      hintText: "Ask driver something...",
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

//// ================= DRIVER DETAILS =================

class DriverScreen extends StatefulWidget {
  final String rideId;
  final int price;
  final String pickup;
  final String drop;
  final String? driverName;
  final String? vehicleModel;
  final String? vehicleNumber;

  const DriverScreen({
    super.key,
    required this.rideId,
    required this.price,
    required this.pickup,
    required this.drop,
    this.driverName,
    this.vehicleModel,
    this.vehicleNumber,
  });

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  late StreamSubscription _sub;
  String otp = "1234";

  @override
  void initState() {
    super.initState();
    ws.send({'type': 'join_ride', 'rideId': widget.rideId, 'role': 'user'});
    ws.send({
      'type': 'set_ride_otp',
      'rideId': widget.rideId,
      'otp': otp,
      'price': widget.price,
      'pickup': widget.pickup,
      'drop': widget.drop,
      'userId': ws.userId,
    });

    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;
      if (msg['type'] == 'ride_started') {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TrackingScreen(
                rideId: widget.rideId,
                pickup: widget.pickup,
                drop: widget.drop,
                driverName: widget.driverName,
                vehicleModel: widget.vehicleModel,
                vehicleNumber: widget.vehicleNumber,
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const MockMapBackground(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D23).withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.35,
            left: MediaQuery.of(context).size.width * 0.4,
            child: TweenAnimationBuilder(
              duration: const Duration(seconds: 2),
              tween: Tween<double>(begin: 0, end: 1),
              onEnd: () {},
              builder: (context, double val, child) {
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4D7CFF).withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4D7CFF).withOpacity(0.2),
                        blurRadius: 30 * val,
                        spreadRadius: 10 * val,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_taxi_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D23),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Driver is arriving",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Provide OTP: $otp",
                            style: const TextStyle(
                              color: Color(0xFF00D2FF),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4D7CFF), Color(0xFF0061FF)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          "₹${widget.price}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundImage: NetworkImage(
                          "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=facearea&facepad=2&w=256&h=256&q=80",
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.driverName ?? "Ravi Sharma",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.vehicleModel ?? "Tesla Model 3 • White",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          widget.vehicleNumber ?? "DL 1C AB",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.pickup,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox(
                            height: 12,
                            child: VerticalDivider(
                              color: Colors.white24,
                              thickness: 1,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.drop,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4D7CFF),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          "Verifying your security code...",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//// ================= TRACKING =================

class TrackingScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String drop;
  final String? driverName;
  final String? vehicleModel;
  final String? vehicleNumber;

  const TrackingScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.drop,
    this.driverName,
    this.vehicleModel,
    this.vehicleNumber,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  double progress = 0.0;
  late StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    ws.send({'type': 'join_ride', 'rideId': widget.rideId, 'role': 'user'});
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;
      if (msg['type'] == 'driver_location') {
        if (mounted)
          setState(() {
            progress = msg['progress'] ?? progress;
          });
      } else if (msg['type'] == 'ride_complete') {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RatingScreen(rideId: widget.rideId),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const MockMapBackground(),

          // Live Taxi Icon
          Positioned(
            left: 50 + (250 * progress),
            top: 400 - (200 * progress),
            child: const Icon(Icons.local_taxi, size: 40, color: Colors.black),
          ),

          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: FloatingActionButton.small(
              backgroundColor: Colors.red,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Emergency SOS Alert Sent!")),
                );
              },
              child: const Icon(Icons.security, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                  const SizedBox(height: 8),
                  const Text(
                    "Trip in Progress",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.black,
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFFF3F3F3),
                        child: Icon(Icons.person, color: Colors.black),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.driverName ?? "James",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            widget.vehicleModel != null &&
                                    widget.vehicleNumber != null
                                ? "${widget.vehicleModel} • ${widget.vehicleNumber}"
                                : "Swift Dzire • DL 1C AB 1234",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      CircleAvatar(
                        backgroundColor: const Color(0xFFF3F3F3),
                        child: IconButton(
                          icon: const Icon(Icons.phone, color: Colors.black),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RatingScreen extends StatefulWidget {
  final String rideId;
  const RatingScreen({super.key, required this.rideId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
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
                "How was your trip?",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Your feedback helps us maintain the QuickCab pulse.",
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
                    'role': 'user',
                    'rating': rating,
                  });
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
                child: const Text(
                  "Submit",
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
