# QuickCab Ride-Hailing Matrix

An ultra-modern, pure-Dart realtime ecosystem mirroring a premium, minimalist Uber-style aesthetic. It contains a high-performance custom WebSocket orchestration layer, a Native App for the User, and an optimized App for the Driver.

### The System Component Matrix
This repository powers 3 interconnected applications:
1. **Central Matrix Server (`quickcab_realtime_server.dart`)**: Handles live location orchestration, dispatch coordination, and runs the SaaS Operations Dashboard.
2. **User Application (`quickcab_user`)**: The rider interface where passengers bargain and request rides. 
3. **Driver Application (`quickcab_driver`)**: The dispatcher layer where drivers receive localized pings, counter-offer prices, verify OTPs, and trace location vectors. 

---

## How to Run Locally

If you cloned this repository, follow these standard steps to activate the realtime mesh on your local environment.

### Prerequisites
- [Dart SDK](https://dart.dev/get-dart)
- [Flutter SDK](https://docs.flutter.dev/get-started/install)

### 1. Boot the Matrix Server
The server acts as the central brain. It must be running first.
```bash
# In the root repository folder
dart quickcab_realtime_server.dart
```
**Access the Web Administration Panel**: Navigate to `http://localhost:8080/admin` in any web browser.

### 2. Boot the Driver App
Connect a driver to the Live Matrix. 
```bash
cd quickcab_driver
flutter pub get
flutter run -d chrome
```

### 3. Boot the User App
Connect a rider to the matrix. 
```bash
cd quickcab_user
flutter pub get
flutter run -d chrome
```

## How It Works
- By default, both the Driver and User Apps communicate over `ws://localhost:8080/ws`. (Or `10.0.2.2` if running on Android Emulators).
- As soon as the Driver App loads, it emits a `driver_online` heartbeat.
- When the User App sends a `ride_request`, the WebSockets server instantly pushes the location geometry over to the Driver. 
- The integrated Bargain system creates real-time synced chat-bubbles, finalizing only when both parties agree.
- The Live Operations Center natively reads from the Dart in-memory dictionary to visualize map congestion globally.

## Production Environment

The QuickCab matrix server is deployed on Render at `https://quickcab-matrix.onrender.com`.

To build and run the User or Driver applications pointing to the production server, use the `--dart-define` flag to dynamically set the `WS_URL` environment variable:

```bash
# Run User App on Chrome connected to Production
cd quickcab_user
flutter run -d chrome --dart-define=WS_URL=wss://quickcab-matrix.onrender.com/ws

# Run Driver App on Chrome connected to Production
cd quickcab_driver
flutter run -d chrome --dart-define=WS_URL=wss://quickcab-matrix.onrender.com/ws
```

VS Code launch configurations are also provided in `.vscode/launch.json` for one-click deployment to the production server.
