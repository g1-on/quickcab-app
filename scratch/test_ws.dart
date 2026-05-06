import 'dart:io';

void main() async {
  try {
    print('Attempting to connect to wss://quickcab-matrix.onrender.com/ws');
    final socket = await WebSocket.connect('wss://quickcab-matrix.onrender.com/ws');
    print('Connected!');
    socket.add('{"type": "register_user", "userId": "test1234", "name": "Test User"}');
    print('Sent message');
    socket.listen((data) {
      print('Received: $data');
    }, onDone: () {
      print('Socket closed');
    }, onError: (e) {
      print('Socket error: $e');
    });
    await Future.delayed(Duration(seconds: 2));
    await socket.close();
  } catch (e) {
    print('Connection failed: $e');
  }
}
