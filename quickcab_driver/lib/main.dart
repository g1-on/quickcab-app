import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String get wsUrl {
  const envUrl = String.fromEnvironment('WS_URL');
  if (envUrl.isNotEmpty) return envUrl;
  if (kIsWeb) return 'ws://localhost:8080/ws';
  if (!kIsWeb && Platform.isAndroid) return 'ws://10.0.2.2:8080/ws';
  return 'ws://localhost:8080/ws';
}

final WebSocketService ws = WebSocketService();

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _controller = StreamController.broadcast();

  final String driverId = "D_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
  final String name = "James (Driver)";

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect() {
    if (_channel != null) return;
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
        onError: (e) => debugPrint("WS Error: $e"),
        onDone: () => debugPrint("WS Done"),
      );

      send({
        'type': 'register_driver',
        'driverId': driverId,
        'name': name,
        'email': 'james@quickcab.com',
        'phone': '555-5000',
        'city': 'Delhi',
        'vehicleModel': 'Swift Dzire',
        'vehicleNumber': 'DL 1C AB 1234',
        'licenseNumber': 'DL-1234567',
      });
      send({
        'type': 'driver_online',
        'driverId': driverId,
      });
    } catch (e) {
      debugPrint("WS Connection Exception: $e");
    }
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      debugPrint("WS OUT: $data");
      _channel!.sink.add(jsonEncode(data));
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const LoginScreen(),
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

class MockMapBackground extends StatelessWidget {
  const MockMapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFE5E5E5),
      child: CustomPaint(painter: GridPainter()),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 2;

    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
    final boldPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8;
    canvas.drawLine(Offset(100, 0), Offset(150, size.height), boldPaint);
    canvas.drawLine(Offset(0, 200), Offset(size.width, 250), boldPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

//// ================= LOGIN =================

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                child: Center(
                  child: Text(
                    "QuickCab\nDriver",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.5,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const Text(
                "Earn on\nyour terms.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text("Go Online", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: () {
                  ws.connect();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverHome()),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
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

  @override
  void initState() {
    super.initState();
    _sub = ws.stream.listen((msg) {
      if (msg['type'] == 'ride_request') {
        if (mounted) {
          setState(() {
            activeRequest = msg;
          });
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
    
    // Join the ride room implicitly before bargaining
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

    setState(() { activeRequest = null; });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverBargainScreen(
          rideId: rideId,
          pickup: pickup,
          drop: drop,
          userOffer: userOffer,
        ),
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
            top: 50, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 24,
                  child: Icon(Icons.menu, color: Colors.black),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text("ONLINE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                )
              ],
            ),
          ),
          
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: activeRequest == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                       SizedBox(height: 20),
                       CircularProgressIndicator(color: Colors.black),
                       SizedBox(height: 24),
                       Text("Finding rides...", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                          const Text("New Ride Request", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("₹${activeRequest!['userOffer']}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.my_location, color: Colors.black),
                        title: const Text("Pickup", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        subtitle: Text(activeRequest!['pickup'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_on, color: Colors.black),
                        title: const Text("Drop", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        subtitle: Text(activeRequest!['drop'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                      const SizedBox(height: 24),
                      BlackButton(
                        onPressed: _reviewRequest,
                        text: "Negotiate Offer",
                      )
                    ],
                  ),
            ),
          ),
        ],
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

  const DriverBargainScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.drop,
    required this.userOffer,
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
    msgs.add({"text": "₹${widget.userOffer}", "me": false}); // Note: me:false because it's User's offer

    // Listen to real-time user counter-offers and acceptances
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'user_offer') {
        int offer = msg['price'] ?? 0;
        if (offer > 0 && mounted) {
          setState(() {
            _latestPrice = offer;
            msgs.add({"text": "₹$offer", "me": false});
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'ride_booked') {
        // Deal locked in
        if (mounted) {
           Navigator.pushReplacement(
             context,
             MaterialPageRoute(
               builder: (_) => DriverExecutionScreen(
                 rideId: widget.rideId,
                 price: _latestPrice,
                 pickup: widget.pickup,
                 drop: widget.drop,
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
    int price = int.tryParse(controller.text) ?? 0;
    if (price <= 0) return;

    ws.send({'type': 'driver_offer', 'rideId': widget.rideId, 'price': price});

    setState(() {
      _latestPrice = price;
      msgs.add({"text": "₹$price", "me": true});
    });

    controller.clear();
    _scrollToBottom();
  }

  void acceptDeal() {
    ws.send({'type': 'accept', 'rideId': widget.rideId, 'role': 'driver', 'price': _latestPrice});
  }

  @override
  Widget build(BuildContext context) {
    bool isUserTurn = msgs.isNotEmpty && !msgs.last["me"];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Negotiating...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text("${widget.pickup} → ${widget.drop}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.grey[100],
            width: double.infinity,
            child: const Center(
              child: Text("User is waiting for your response...", style: TextStyle(fontSize: 12, color: Colors.black54)),
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
                return Align(
                  alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: me ? Colors.black : const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(me ? 20 : 0),
                        bottomRight: Radius.circular(me ? 0 : 20),
                      ),
                    ),
                    child: Text(
                      m["text"],
                      style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: me ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          if (isUserTurn)
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
               child: BlackButton(
                 onPressed: acceptDeal,
                 text: "Accept Deal for ₹$_latestPrice",
               ),
             ),

          Container(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "Counter offer...",
                      filled: true,
                      fillColor: const Color(0xFFF3F3F3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.black,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: sendOffer,
                  ),
                )
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

  const DriverExecutionScreen({
    super.key,
    required this.rideId,
    required this.price,
    required this.pickup,
    required this.drop,
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
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'otp_verified' || msg['type'] == 'ride_started') {
        if (mounted) {
          setState(() { rideStarted = true; });
        }
      } else if (msg['type'] == 'otp_invalid') {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP! Try again.")));
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
    setState(() { progress = value; });
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriverHome()));
    }
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
            child: const Icon(Icons.local_taxi, size: 40, color: Colors.blue), // Driver car is blue
          ),
          
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: SafeArea(
                top: false,
                child: !rideStarted 
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Arrived at Pickup", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                         Text("Ask user for OTP to verify.", style: TextStyle(color: Colors.grey[600])),
                        const SizedBox(height: 24),
                        TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                          maxLength: 4,
                          decoration: InputDecoration(
                            hintText: "0000",
                            filled: true,
                            fillColor: const Color(0xFFF3F3F3),
                            counterText: "",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 24),
                        BlackButton(onPressed: _verifyOtp, text: "Verify OTP & Start Ride")
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Driving to Drop-off", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                              child: Text("₹${widget.price}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text("Slide to update routing progress (Demo):", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Slider(
                          value: progress,
                          onChanged: _updateProgress,
                          activeColor: Colors.black,
                          inactiveColor: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        if (progress == 1.0)
                          const Text("Ride Complete! Redirecting...", textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                      ],
                    )
              ),
            ),
          ),
        ],
      ),
    );
  }
}
