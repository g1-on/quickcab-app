import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Determines localhost equivalent
String get wsUrl {
  if (kIsWeb) return 'ws://localhost:8080/ws';
  if (!kIsWeb && Platform.isAndroid) return 'ws://10.0.2.2:8080/ws';
  return 'ws://localhost:8080/ws';
}

// Global WebSocket Service
final WebSocketService ws = WebSocketService();

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  final String userId =
      "U_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
  final String name = "Alex (User)";

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

      // Register the user to show up in Admin Panel
      send({
        'type': 'register_user',
        'userId': userId,
        'name': name,
        'email': 'alex@example.com',
        'phone': '555-0199',
        'city': 'Delhi',
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
                    "QuickCab",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
              ),
              const Text(
                "Get there,\nfast and safely.",
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
                child: const Text(
                  "Get Started",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  // Connect to Realtime Server upon login
                  ws.connect();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openBookingSheet(BuildContext context) {
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
      body: Stack(
        children: [
          const MockMapBackground(),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 24,
                  child: Icon(Icons.menu, color: Colors.black),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.amber),
                      SizedBox(width: 4),
                      Text(
                        "4.9",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Good morning",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => _openBookingSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F3F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search, size: 28),
                          SizedBox(width: 12),
                          Text(
                            "Where to?",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
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
  String pickup = "Delhi";
  String drop = "Agra";
  final priceController = TextEditingController();
  final cities = ["Delhi", "Agra", "Jaipur", "Noida", "Gurugram"];

  void requestRide() {
    int price = int.tryParse(priceController.text) ?? 0;
    if (price <= 0) return;

    // Generate new Ride ID
    final String rideId =
        "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}";

    // Dispatch real-time ride request
    ws.send({
      'type': 'ride_request',
      'rideId': rideId,
      'pickup': pickup,
      'drop': drop,
      'userOffer': price,
      'userId': ws.userId,
    });

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BargainScreen(
          rideId: rideId,
          initialPrice: price,
          pickup: pickup,
          drop: drop,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Plan your ride",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField(
            initialValue: pickup,
            items: cities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => pickup = v!),
            decoration: InputDecoration(
              labelText: "Pickup",
              filled: true,
              fillColor: const Color(0xFFF3F3F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField(
            initialValue: drop,
            items: cities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => drop = v!),
            decoration: InputDecoration(
              labelText: "Drop",
              filled: true,
              fillColor: const Color(0xFFF3F3F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Offer your fare (₹)",
              prefixIcon: const Icon(Icons.local_offer, color: Colors.green),
              filled: true,
              fillColor: const Color(0xFFF3F3F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 32),
          BlackButton(onPressed: requestRide, text: "Request Ride"),
        ],
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

  const BargainScreen({
    super.key,
    required this.rideId,
    required this.initialPrice,
    required this.pickup,
    required this.drop,
  });

  @override
  State<BargainScreen> createState() => _BargainScreenState();
}

class _BargainScreenState extends State<BargainScreen> {
  List<Map<String, dynamic>> msgs = [];
  final controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription _sub;

  int _latestPrice = 0;

  @override
  void initState() {
    super.initState();
    _latestPrice = widget.initialPrice;
    msgs.add({"text": "₹${widget.initialPrice}", "me": true});

    // Listen to real-time driver offers
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'driver_offer') {
        int offer = msg['price'] ?? 0;
        if (offer > 0 && mounted) {
          setState(() {
            _latestPrice = offer;
            msgs.add({"text": "₹$offer", "me": false});
          });
          _scrollToBottom();
        }
      } else if (msg['type'] == 'ride_booked') {
        // Driver accepted our offer, or booked normally
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverScreen(
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

    // Mock driver reply if testing alone, otherwise remove this in prod
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && msgs.length == 1) {
        // Simulate a driver reply via web socket
        ws.send({
          'type': 'driver_offer',
          'rideId': widget.rideId,
          'price': widget.initialPrice + 200,
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
    int price = int.tryParse(controller.text) ?? 0;
    if (price <= 0) return;

    ws.send({'type': 'user_offer', 'rideId': widget.rideId, 'price': price});

    setState(() {
      _latestPrice = price;
      msgs.add({"text": "₹$price", "me": true});
    });

    controller.clear();
    _scrollToBottom();
  }

  void acceptDeal() {
    ws.send({
      'type': 'accept',
      'rideId': widget.rideId,
      'role': 'user',
      'price': _latestPrice,
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDriverTurn = msgs.isNotEmpty && !msgs.last["me"];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              "Finding a driver...",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "To ${widget.drop}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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
              child: Text(
                "Drivers are reviewing your offer.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: me ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (isDriverTurn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: BlackButton(
                onPressed: acceptDeal,
                text: "Accept Deal for ₹$_latestPrice",
              ),
            ),

          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
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

  const DriverScreen({
    super.key,
    required this.rideId,
    required this.price,
    required this.pickup,
    required this.drop,
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
    // Dispatch OTP configuration immediately when driver assigned
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
              builder: (_) =>
                  TrackingScreen(rideId: widget.rideId, price: widget.price),
            ),
          );
        }
      }
    });

    debugPrint(
      "To start ride, Driver app must send: {'type':'verify_start_otp', 'rideId': '${widget.rideId}', 'otp':'$otp'}",
    );
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
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          const Positioned(
            top: 250,
            left: 150,
            child: Icon(Icons.local_taxi, size: 60, color: Colors.black),
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
                            "Meet driver at pickup",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Provide OTP: $otp",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage(
                          "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=facearea&facepad=2&w=256&h=256&q=80",
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Ravi Sharma",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Swift Dzire",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
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
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "DL 1C AB",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Waiting for driver to verify OTP...",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
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
  final int price;
  const TrackingScreen({super.key, required this.rideId, required this.price});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late StreamSubscription _sub;
  double progress = 0.0;

  @override
  void initState() {
    super.initState();
    _sub = ws.stream.listen((msg) {
      if (msg['rideId'] != widget.rideId) return;

      if (msg['type'] == 'driver_location') {
        if (msg['progress'] != null && mounted) {
          setState(() {
            progress = (msg['progress'] as num).toDouble();
          });
        }
      } else if (msg['type'] == 'ride_complete') {
        if (mounted) {
          setState(() {
            progress = 1.0;
          });
        }
      }
    });

    // Optional self-driving mock if no driver is alive
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && progress == 0) {
        ws.send({
          'type': 'ride_complete',
          'rideId': widget.rideId,
          'finalPrice': widget.price,
        });
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
            left: 50 + (250 * progress),
            top: 400 - (200 * progress),
            child: const Icon(Icons.local_taxi, size: 40, color: Colors.black),
          ),
          const Positioned(
            left: 38,
            top: 400,
            child: Icon(Icons.location_on, color: Colors.green, size: 30),
          ),
          const Positioned(
            left: 300,
            top: 180,
            child: Icon(Icons.location_on, color: Colors.red, size: 30),
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
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          progress < 1
                              ? "Heading to destination"
                              : "You have arrived",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "₹${widget.price}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFFEEEEEE),
                        color: Colors.black,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (progress >= 1)
                      BlackButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HomeScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        text: "Close Ride",
                      ),
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
