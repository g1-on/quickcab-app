import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// QuickCab realtime WebSocket server (no external dependencies).
///
/// Run from project root:
///   dart quickcab_realtime_server.dart
///
/// Connect from apps using:
///   ws://localhost:8080/ws
///
/// Protocol (JSON):
/// - ride_request { rideId, pickup, drop, userOffer }
/// - join_ride    { rideId, role: "user"|"driver" }
/// - user_offer   { rideId, price }
/// - driver_offer { rideId, price }
/// - accept       { rideId, role, price }
/// - ride_booked  { rideId, price }
/// - set_ride_otp { rideId, otp }
/// - verify_start_otp { rideId, otp }
/// - ride_started { rideId }
/// - chat_message { rideId, role, text }
/// - driver_location { rideId, lat, lng, progress }
///
/// The server broadcasts ride_request to all online drivers.
/// For a given rideId, messages are broadcast to all sockets that joined that ride.
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8081') ?? 8081;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('QuickCab realtime server listening on port $port');
  print('Admin panel: http://localhost:$port/admin');

  final rooms = <String, Set<WebSocket>>{};
  final driverSockets = <WebSocket>{};
  final acceptState = <String, Map<String, int>>{};

  // Persistent Storage
  final userFile = File('users_db.json');
  final driverFile = File('drivers_db.json');
  final ridesFile = File('rides_db.json');

  Map<String, dynamic> userDb = {};
  Map<String, dynamic> driverDb = {};
  Map<String, dynamic> ridesDb = {};

  if (await userFile.exists()) {
    try {
      userDb = jsonDecode(await userFile.readAsString());
    } catch (_) {}
  }
  if (await driverFile.exists()) {
    try {
      driverDb = jsonDecode(await driverFile.readAsString());
    } catch (_) {}
  }
  if (await ridesFile.exists()) {
    try {
      ridesDb = jsonDecode(await ridesFile.readAsString());
    } catch (_) {}
  }

  void saveDbs() async {
    await userFile.writeAsString(jsonEncode(userDb));
    await driverFile.writeAsString(jsonEncode(driverDb));
    await ridesFile.writeAsString(jsonEncode(ridesDb));
  }

  final users = <String, Map<String, dynamic>>{};
  final drivers = <String, Map<String, dynamic>>{};
  final rides = ridesDb; // Use persistent DB for rides too
  final socketDriverId = <WebSocket, String>{};

  const adminHtml = '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>QuickCab Admin Portal</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #F9FAFB;
      --surface: #FFFFFF;
      --text: #111827;
      --text-muted: #6B7280;
      --border: #E5E7EB;
      --primary: #000000;
      --accent: #10B981;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', sans-serif;
      background-color: var(--bg);
      color: var(--text);
      display: flex;
      height: 100vh;
      overflow: hidden;
    }
    .sidebar {
      width: 260px;
      background-color: var(--surface);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      padding: 24px;
    }
    .sidebar-brand {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 40px;
    }
    .brand-icon {
      width: 32px;
      height: 32px;
      background: var(--primary);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
      font-weight: 800;
      font-size: 18px;
    }
    .brand-text {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.5px;
    }
    .nav-item {
      padding: 12px 16px;
      background: var(--bg);
      border-radius: 8px;
      font-weight: 600;
      font-size: 14px;
      color: var(--primary);
      margin-bottom: 8px;
      cursor: pointer;
    }
    
    .main-content {
      flex: 1;
      display: flex;
      flex-direction: column;
      overflow-y: auto;
    }
    .header {
      padding: 32px 40px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .header h1 {
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.5px;
    }
    
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 20px;
      padding: 0 40px;
      margin-bottom: 32px;
    }
    .stat-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
      transition: transform 0.2s;
    }
    .stat-card:hover {
      transform: translateY(-2px);
    }
    .stat-label {
      color: var(--text-muted);
      font-size: 13px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 8px;
    }
    .stat-value {
      font-size: 32px;
      font-weight: 800;
      color: var(--primary);
    }
    
    .filters {
      padding: 0 40px;
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 20px;
      margin-bottom: 24px;
    }
    .filter-input {
      background: var(--surface);
      border: 1px solid var(--border);
      padding: 12px 16px;
      border-radius: 12px;
      font-size: 14px;
      font-family: inherit;
      width: 100%;
      outline: none;
      transition: border-color 0.2s;
    }
    .filter-input:focus {
      border-color: var(--primary);
    }
    
    .dashboard-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 24px;
      padding: 0 40px 40px 40px;
    }
    
    .panel {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 16px;
      display: flex;
      flex-direction: column;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
      overflow: hidden;
    }
    .rides-panel {
      grid-column: span 2;
    }
    
    .panel-header {
      padding: 20px 24px;
      border-bottom: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: #FAFAFA;
    }
    .panel-header h2 {
      font-size: 16px;
      font-weight: 700;
    }
    .record-count {
      font-size: 12px;
      color: var(--text-muted);
      font-weight: 600;
      background: var(--border);
      padding: 4px 10px;
      border-radius: 999px;
    }
    
    .panel-body {
      padding: 0;
      max-height: 400px;
      overflow-y: auto;
    }
    
    .item-row {
      padding: 16px 24px;
      border-bottom: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .item-row:last-child {
      border-bottom: none;
    }
    .item-title {
      font-size: 14px;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .item-sub {
      font-size: 13px;
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
    }
    
    .badge {
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .badge.gray { background: #F3F4F6; color: #4B5563; }
    .badge.green { background: #D1FAE5; color: #065F46; }
    .badge.red { background: #FEE2E2; color: #991B1B; }
    .badge.blue { background: #DBEAFE; color: #1E40AF; }
    .badge.orange { background: #FEF3C7; color: #92400E; }

    .log-container {
      margin-top: 10px;
      display: flex;
      gap: 8px;
      overflow-x: auto;
      padding-bottom: 8px;
    }
    .log-pill {
      flex: 0 0 auto;
      background: #F3F4F6;
      border: 1px solid #E5E7EB;
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 11px;
      white-space: nowrap;
    }
    .log-pill .log-who {
      font-weight: 800;
      text-transform: uppercase;
      font-size: 9px;
      margin-bottom: 2px;
      color: var(--text-muted);
    }
    .log-pill.user { border-left: 3px solid #000; }
    .log-pill.driver { border-left: 3px solid #3B82F6; }
  </style>
</head>
<body>
  
  <div class="sidebar">
    <div class="sidebar-brand">
      <div class="brand-icon">Q</div>
      <div class="brand-text">QuickCab</div>
    </div>
    <div class="nav-item">Network Matrix</div>
  </div>

  <div class="main-content">
    <div class="header">
      <h1>Live Administration</h1>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">Total Users</div>
        <div class="stat-value" id="statUsers">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Drivers</div>
        <div class="stat-value" id="statDrivers">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Drivers Online</div>
        <div class="stat-value" id="statOnline">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Rides</div>
        <div class="stat-value" id="statRides">0</div>
      </div>
    </div>

    <div class="filters">
      <input type="text" class="filter-input" id="filterUserId" placeholder="Filter Users..." />
      <input type="text" class="filter-input" id="filterDriverId" placeholder="Filter Drivers..." />
      <input type="text" class="filter-input" id="filterRideId" placeholder="Filter Rides..." />
    </div>

    <div class="dashboard-grid">
      
      <div class="panel">
        <div class="panel-header">
          <h2>Active Users</h2>
          <span class="record-count" id="uCount">0</span>
        </div>
        <div class="panel-body" id="usersList"></div>
      </div>

      <div class="panel">
        <div class="panel-header">
          <h2>Driver Fleet</h2>
          <span class="record-count" id="dCount">0</span>
        </div>
        <div class="panel-body" id="driversList"></div>
      </div>

      <div class="panel rides-panel">
        <div class="panel-header">
          <h2>Live Dispatch Board</h2>
          <span class="record-count" id="rCount">0</span>
        </div>
        <div class="panel-body" id="ridesList"></div>
      </div>

    </div>
  </div>

  <script>
    function fmtTs(ts){ if(!ts) return '-'; return new Date(ts).toLocaleTimeString(); }
    function txt(v){ return (v || '').toString().toLowerCase(); }
    
    function getStatusBadge(status) {
      if(status === 'booked' || status === 'in_progress' || status === 'completed') return 'green';
      if(status === 'bargaining') return 'orange';
      return 'blue';
    }

    async function refresh() {
      try {
        const res = await fetch('/api/admin/state');
        const data = await res.json();
        
        const userFilter = txt(document.getElementById('filterUserId').value).trim();
        const driverFilter = txt(document.getElementById('filterDriverId').value).trim();
        const rideFilter = txt(document.getElementById('filterRideId').value).trim();

        const users = (data.users || []).filter(u => !userFilter || txt(u.userId).includes(userFilter));
        const drivers = (data.drivers || []).filter(d => !driverFilter || txt(d.driverId).includes(driverFilter));
        const rides = (data.rides || []).filter(r => !rideFilter || txt(r.rideId).includes(rideFilter));

        const onlineDrivers = drivers.filter(d => d.online).length;

        document.getElementById('statUsers').textContent = users.length;
        document.getElementById('statDrivers').textContent = drivers.length;
        document.getElementById('statOnline').textContent = onlineDrivers;
        document.getElementById('statRides').textContent = rides.length;
        
        document.getElementById('uCount').textContent = users.length;
        document.getElementById('dCount').textContent = drivers.length;
        document.getElementById('rCount').textContent = rides.length;

        const usersEl = document.getElementById('usersList');
        usersEl.innerHTML = users.length ? '' : '<div class="item-row"><span style="color:var(--text-muted)">No users connected</span></div>';
        users.forEach(u => {
          usersEl.innerHTML += `
            <div class="item-row">
              <div class="item-title">
                \${u.name || 'Unknown User'} 
                <span class="badge gray">\${u.userId}</span>
              </div>
              <div class="item-sub">
                Seen: \${fmtTs(u.lastSeen)}
              </div>
            </div>
          `;
        });

        const driversEl = document.getElementById('driversList');
        driversEl.innerHTML = drivers.length ? '' : '<div class="item-row"><span style="color:var(--text-muted)">No drivers connected</span></div>';
        drivers.forEach(d => {
          const statusBadge = d.online ? 'green' : 'red';
          const statusText = d.online ? 'ONLINE' : 'OFFLINE';
          driversEl.innerHTML += `
            <div class="item-row">
              <div class="item-title">
                \${d.name || 'Unknown Driver'} 
                <span class="badge \${statusBadge}">\${statusText}</span>
              </div>
              <div class="item-sub">
                \${d.vehicleModel || '-'} (\${d.vehicleNumber || '-'}) • Seen: \${fmtTs(d.lastSeen)}
              </div>
            </div>
          `;
        });

        const ridesEl = document.getElementById('ridesList');
        ridesEl.innerHTML = rides.length ? '' : '<div class="item-row"><span style="color:var(--text-muted)">No active rides</span></div>';
        rides.forEach(r => {
          let logHtml = '';
          if (r.logs && r.logs.length) {
            logHtml = `<div class="log-container">`;
            r.logs.forEach(l => {
              logHtml += `
                <div class="log-pill \${l.from === 'user' ? 'user' : 'driver'}">
                  <div class="log-who">\${l.from} • \${fmtTs(l.ts)}</div>
                  <div>\${l.text}</div>
                </div>
              `;
            });
            logHtml += `</div>`;
          }

          ridesEl.innerHTML += `
            <div class="item-row">
              <div style="display:flex; flex-direction:row; justify-content:space-between; align-items:center;">
                <div style="display:flex; flex-direction:column; gap:6px;">
                  <div class="item-title">
                    \${r.pickup || '?'} → \${r.drop || '?'}
                    <span class="badge \${getStatusBadge(r.status)}">\${r.status || 'requested'}</span>
                    <span class="badge gray">ID: \${r.rideId}</span>
                  </div>
                  <div class="item-sub">
                    User: \${r.userId || '-'} • Driver: \${r.driverId || '-'} • Updated: \${fmtTs(r.updatedAt)}
                  </div>
                </div>
                <div style="font-size: 20px; font-weight: 800;">
                  ₹\${r.finalPrice || r.userOffer || '-'}
                </div>
              </div>
              \${logHtml}
            </div>
          `;
        });

      } catch (err) {
        console.error("Admin poll failed:", err);
      }
    }

    ['filterUserId','filterDriverId','filterRideId'].forEach(id => {
      document.getElementById(id).addEventListener('input', fetch);
    });
    
    refresh();
    setInterval(refresh, 1000);
  </script>
</body>
</html>
''';

  Future<void> broadcastToRoom(String rideId, Map<String, dynamic> msg) async {
    final room = rooms[rideId];
    if (room == null) return;
    final text = jsonEncode(msg);
    for (final s in room.toList()) {
      try {
        s.add(text);
      } catch (_) {
        room.remove(s);
      }
    }
  }

  void broadcastToDrivers(Map<String, dynamic> msg) {
    final text = jsonEncode(msg);
    for (final s in driverSockets.toList()) {
      try {
        s.add(text);
      } catch (_) {
        driverSockets.remove(s);
      }
    }
  }

  Future<void> broadcastToAll(Map<String, dynamic> msg) async {
    final text = jsonEncode(msg);
    // Broadcast to drivers
    for (final s in driverSockets.toList()) {
      try {
        s.add(text);
      } catch (_) {
        driverSockets.remove(s);
      }
    }
    // Broadcast to everyone in rooms
    for (final room in rooms.values) {
      for (final s in room.toList()) {
        try {
          s.add(text);
        } catch (_) {}
      }
    }
  }

  Future<void> bookRideIfMatched(
    String rideId,
    Map<String, int> state, {
    String? targetDriverId,
  }) async {
    final userPrice = state['user'];
    if (userPrice == null) return;

    String? winnerDriverId = targetDriverId;
    int? winningPrice;

    if (winnerDriverId != null) {
      winningPrice = state[winnerDriverId];
    } else {
      // If no specific driver, check if any driver matches the user price
      for (final entry in state.entries) {
        if (entry.key != 'user' && entry.value == userPrice) {
          winnerDriverId = entry.key;
          winningPrice = entry.value;
          break;
        }
      }
    }

    if (winnerDriverId == null ||
        winningPrice == null ||
        userPrice != winningPrice) {
      return;
    }

    if (rides[rideId]?['status'] == 'booked') return;

    final ride = rides[rideId];
    final driver = drivers[winnerDriverId];

    await broadcastToRoom(rideId, {
      'type': 'ride_booked',
      'rideId': rideId,
      'price': winningPrice,
      'driverId': winnerDriverId,
      'driverName': driver?['name'],
      'vehicleModel': driver?['vehicleModel'],
      'vehicleNumber': driver?['vehicleNumber'],
    });

    if (ride != null) {
      ride['status'] = 'booked';
      ride['finalPrice'] = winningPrice;
      ride['driverId'] = winnerDriverId;
      ride['updatedAt'] = DateTime.now().toIso8601String();
    }
  }

  await for (final req in server) {
    if (req.uri.path == '/admin') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(adminHtml);
      await req.response.close();
      continue;
    }

    if (req.uri.path == '/api/admin/state') {
      final usersList = users.values.toList()
        ..sort(
          (a, b) => (b['lastSeen'] ?? '').toString().compareTo(
            (a['lastSeen'] ?? '').toString(),
          ),
        );
      final driversList = drivers.values.toList()
        ..sort(
          (a, b) => (b['lastSeen'] ?? '').toString().compareTo(
            (a['lastSeen'] ?? '').toString(),
          ),
        );
      final ridesList = rides.values.toList()
        ..sort(
          (a, b) => (b['updatedAt'] ?? '').toString().compareTo(
            (a['updatedAt'] ?? '').toString(),
          ),
        );
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'users': usersList,
          'drivers': driversList,
          'rides': ridesList,
        }),
      );
      await req.response.close();
      continue;
    }

    // --- CORS HEADERS ---
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add(
      'Access-Control-Allow-Methods',
      'POST, GET, OPTIONS',
    );
    req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.ok;
      await req.response.close();
      return;
    }

    if (req.uri.path == '/api/signup' && req.method == 'POST') {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body);
      final role = data['role'];
      final email = data['email'];
      final password = data['password'];
      final name = data['name'];
      final db = role == 'user' ? userDb : driverDb;
      if (db.containsKey(email)) {
        req.response
          ..statusCode = 400
          ..write(jsonEncode({'error': 'Email already exists'}))
          ..close();
        return;
      }
      db[email] = {
        'id': role == 'user'
            ? "U_${DateTime.now().millisecondsSinceEpoch}"
            : "D_${DateTime.now().millisecondsSinceEpoch}",
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      };
      saveDbs();
      req.response
        ..statusCode = 200
        ..write(jsonEncode(db[email]))
        ..close();
      return;
    }

    if (req.uri.path == '/api/login' && req.method == 'POST') {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body);
      final email = data['email'];
      final password = data['password'];
      final role = data['role'];
      final db = role == 'user' ? userDb : driverDb;
      if (db.containsKey(email) && db[email]['password'] == password) {
        req.response
          ..statusCode = 200
          ..write(jsonEncode(db[email]))
          ..close();
      } else {
        req.response
          ..statusCode = 401
          ..write(jsonEncode({'error': 'Invalid credentials'}))
          ..close();
      }
      return;
    }

    if (req.uri.path != '/ws') {
      req.response.statusCode = HttpStatus.notFound;
      req.response.write('Not found');
      await req.response.close();
      continue;
    }

    final socket = await WebSocketTransformer.upgrade(req);

    socket.listen(
      (dynamic data) async {
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(data as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        final type = msg['type'];
        if (type is! String) return;

        switch (type) {
          case 'register_user':
            final userId = (msg['userId'] ?? '').toString();
            if (userId.isEmpty) return;
            final current =
                users[userId] ?? <String, dynamic>{'userId': userId};
            final name = (msg['name'] ?? '').toString().trim();
            final email = (msg['email'] ?? '').toString().trim();
            final phone = (msg['phone'] ?? '').toString().trim();
            final city = (msg['city'] ?? '').toString().trim();
            final homeCity = (msg['homeCity'] ?? '').toString().trim();
            final workCity = (msg['workCity'] ?? '').toString().trim();
            if (name.isNotEmpty) current['name'] = name;
            if (email.isNotEmpty) current['email'] = email;
            if (phone.isNotEmpty) current['phone'] = phone;
            if (city.isNotEmpty) current['city'] = city;
            if (homeCity.isNotEmpty) current['homeCity'] = homeCity;
            if (workCity.isNotEmpty) current['workCity'] = workCity;
            current['lastSeen'] = DateTime.now().toIso8601String();
            users[userId] = current;
            return;

          case 'register_driver':
            final driverId = (msg['driverId'] ?? '').toString();
            if (driverId.isEmpty) return;
            socketDriverId[socket] = driverId;
            final current =
                drivers[driverId] ?? <String, dynamic>{'driverId': driverId};
            final name = (msg['name'] ?? '').toString().trim();
            final email = (msg['email'] ?? '').toString().trim();
            final phone = (msg['phone'] ?? '').toString().trim();
            final city = (msg['city'] ?? '').toString().trim();
            final vehicleModel = (msg['vehicleModel'] ?? '').toString().trim();
            final vehicleNumber = (msg['vehicleNumber'] ?? '')
                .toString()
                .trim();
            final licenseNumber = (msg['licenseNumber'] ?? '')
                .toString()
                .trim();
            if (name.isNotEmpty) current['name'] = name;
            if (email.isNotEmpty) current['email'] = email;
            if (phone.isNotEmpty) current['phone'] = phone;
            if (city.isNotEmpty) current['city'] = city;
            if (vehicleModel.isNotEmpty) current['vehicleModel'] = vehicleModel;
            if (vehicleNumber.isNotEmpty)
              current['vehicleNumber'] = vehicleNumber;
            if (licenseNumber.isNotEmpty)
              current['licenseNumber'] = licenseNumber;
            current['online'] = current['online'] ?? false;
            current['lastSeen'] = DateTime.now().toIso8601String();
            drivers[driverId] = current;
            return;

          case 'driver_online':
            driverSockets.add(socket);
            final driverId = (msg['driverId'] ?? socketDriverId[socket] ?? '')
                .toString();
            if (driverId.isNotEmpty) {
              socketDriverId[socket] = driverId;
              final current =
                  drivers[driverId] ?? <String, dynamic>{'driverId': driverId};
              current['online'] = true;
              current['lastSeen'] = DateTime.now().toIso8601String();
              drivers[driverId] = current;
            }
            socket.add(jsonEncode({'type': 'driver_online_ack'}));

            // Push active 'finding' rides to the newly connected driver
            for (final r in rides.values) {
              if (r['status'] == 'finding') {
                socket.add(jsonEncode({'type': 'ride_request', ...r}));
              }
            }
            return;

          case 'driver_offline':
            driverSockets.remove(socket);
            final driverId = (msg['driverId'] ?? socketDriverId[socket] ?? '')
                .toString();
            if (driverId.isNotEmpty) {
              final current =
                  drivers[driverId] ?? <String, dynamic>{'driverId': driverId};
              current['online'] = false;
              current['lastSeen'] = DateTime.now().toIso8601String();
              drivers[driverId] = current;
            }
            return;

          case 'ride_request':
            final rideId = msg['rideId'];
            if (rideId is! String || rideId.isEmpty) return;
            msg['status'] = 'finding';
            msg['vehicleType'] = msg['vehicleType'] ?? 'Uber Go';
            msg['paymentMethod'] = msg['paymentMethod'] ?? 'Cash';
            msg['createdAt'] = DateTime.now().toIso8601String();
            msg['updatedAt'] = msg['createdAt'];
            msg['logs'] = [];

            final userOffer = msg['userOffer'] is num
                ? (msg['userOffer'] as num).toInt()
                : null;
            if (userOffer != null) {
              (msg['logs'] as List).add({
                'ts': DateTime.now().toIso8601String(),
                'from': 'user',
                'text': 'Initial offer: ₹$userOffer',
              });
            }

            rooms.putIfAbsent(rideId, () => <WebSocket>{}).add(socket);
            acceptState[rideId] = {if (userOffer != null) 'user': userOffer};

            rides[rideId] = msg;
            await broadcastToAll({'type': 'ride_request', ...msg});
            return;

          case 'submit_rating':
            final rideId = msg['rideId'];
            if (rideId == null) return;
            // In a real app, we'd save this to a DB. For now, we just broadcast acknowledgement.
            await broadcastToRoom(rideId, {
              'type': 'rating_received',
              'rideId': rideId,
              'from': msg['role'],
              'rating': msg['rating'],
              'comment': msg['comment'] ?? '',
            });
            return;

          case 'join_ride':
            final rideId = msg['rideId'];
            final role = (msg['role'] ?? '').toString();
            if (rideId is! String || rideId.isEmpty) return;
            rooms.putIfAbsent(rideId, () => <WebSocket>{}).add(socket);
            if (role == 'driver') {
              final driverId = (msg['driverId'] ?? socketDriverId[socket] ?? '')
                  .toString();
              if (driverId.isNotEmpty && rides.containsKey(rideId)) {
                rides[rideId]!['driverId'] = driverId;
                rides[rideId]!['status'] = 'driver_joined';
                rides[rideId]!['updatedAt'] = DateTime.now().toIso8601String();
              }
            }
            socket.add(
              jsonEncode({
                'type': 'joined',
                'rideId': rideId,
                'history': rides.containsKey(rideId)
                    ? rides[rideId]!['logs']
                    : [],
              }),
            );
            saveDbs();
            return;

          case 'chat_message':
            final rideId = msg['rideId'];
            final text = msg['text'];
            final role = msg['role'];
            if (rideId is! String || text is! String || role is! String) return;

            final logEntry = {
              'ts': DateTime.now().toIso8601String(),
              'from': role,
              'text': text,
              'userName': msg['userName'],
            };

            if (rides.containsKey(rideId)) {
              rides[rideId]!['updatedAt'] = logEntry['ts'];
              (rides[rideId]!['logs'] as List?)?.add(logEntry);
              saveDbs();
            }

            await broadcastToRoom(rideId, {
              'type': 'chat_message',
              'rideId': rideId,
              'role': role,
              'text': text,
              'userName': msg['userName'],
              'ts': logEntry['ts'],
            });
            return;

          case 'user_offer':
          case 'driver_offer':
            final rideId = msg['rideId'];
            final price = msg['price'];
            if (rideId is! String || price is! num) return;
            final state = acceptState.putIfAbsent(
              rideId,
              () => <String, int>{},
            );

            String key = 'user';
            if (type == 'driver_offer') {
              key = (msg['driverId'] ?? socketDriverId[socket] ?? '')
                  .toString();
              if (key.isEmpty) return;
            }

            state[key] = price.toInt();
            await broadcastToRoom(rideId, {
              'type': type,
              'rideId': rideId,
              'price': price.toInt(),
              if (type == 'driver_offer') ...{
                'driverId': key,
                'driverName': msg['driverName'],
                'vehicleModel': msg['vehicleModel'],
                'vehicleNumber': msg['vehicleNumber'],
              },
            });
            if (rides.containsKey(rideId)) {
              if (type == 'user_offer') {
                rides[rideId]!['userOffer'] = price.toInt();
              } else {
                rides[rideId]!['driverOffer'] = price.toInt();
              }
              rides[rideId]!['status'] = 'bargaining';
              rides[rideId]!['updatedAt'] = DateTime.now().toIso8601String();

              final logEntry = {
                'ts': rides[rideId]!['updatedAt'],
                'from': type == 'user_offer' ? 'user' : 'driver',
                'driverId': type == 'driver_offer' ? key : null,
                'text': 'Offer: ₹${price.toInt()}',
              };
              (rides[rideId]!['logs'] as List?)?.add(logEntry);
            }
            await bookRideIfMatched(
              rideId,
              state,
              targetDriverId: type == 'driver_offer' ? key : null,
            );
            return;

          case 'accept':
            final rideId = msg['rideId'];
            final role = msg['role'];
            final price = msg['price'];
            if (rideId is! String || role is! String || price is! num) return;

            final state = acceptState.putIfAbsent(
              rideId,
              () => <String, int>{},
            );
            String key = role;
            if (role == 'driver') {
              key = (msg['driverId'] ?? socketDriverId[socket] ?? '')
                  .toString();
            } else if (role == 'user' && msg['driverId'] != null) {
              // User accepts a specific driver's offer
              key = 'user';
              state['user'] = price.toInt();
              await bookRideIfMatched(
                rideId,
                state,
                targetDriverId: msg['driverId'],
              );
              return;
            }

            state[key] = price.toInt();

            await broadcastToRoom(rideId, {
              'type': 'accept',
              'rideId': rideId,
              'role': role,
              'price': price.toInt(),
              'driverId': key != 'user' ? key : null,
              'driverName': msg['driverName'],
              'vehicleModel': msg['vehicleModel'],
              'vehicleNumber': msg['vehicleNumber'],
            });

            if (rides.containsKey(rideId)) {
              final logEntry = {
                'ts': DateTime.now().toIso8601String(),
                'from': role,
                'text': 'ACCEPTED: ₹${price.toInt()}',
              };
              (rides[rideId]!['logs'] as List?)?.add(logEntry);
            }

            await bookRideIfMatched(
              rideId,
              state,
              targetDriverId: role == 'driver' ? key : null,
            );
            return;

          case 'set_ride_otp':
            final rideId = msg['rideId'];
            final otp = (msg['otp'] ?? '').toString();
            if (rideId is! String || rideId.isEmpty || otp.isEmpty) return;
            final ride = rides.putIfAbsent(
              rideId,
              () => <String, dynamic>{'rideId': rideId},
            );
            ride['startOtp'] = otp;
            ride['status'] = 'otp_pending';
            ride['pickup'] = (msg['pickup'] ?? ride['pickup'] ?? '').toString();
            ride['drop'] = (msg['drop'] ?? ride['drop'] ?? '').toString();
            ride['userId'] = (msg['userId'] ?? ride['userId'] ?? '').toString();
            ride['userPhone'] = (msg['userPhone'] ?? ride['userPhone'] ?? '')
                .toString();
            if (msg['price'] is num) {
              ride['finalPrice'] = (msg['price'] as num).toInt();
            }
            ride['updatedAt'] = DateTime.now().toIso8601String();
            await broadcastToRoom(rideId, {
              'type': 'ride_otp_set',
              'rideId': rideId,
            });
            return;

          case 'verify_start_otp':
            final rideId = msg['rideId'];
            final otp = (msg['otp'] ?? '').toString();
            if (rideId is! String || rideId.isEmpty || otp.isEmpty) return;
            final ride = rides[rideId];
            if (ride == null) return;
            if ((ride['startOtp'] ?? '').toString() != otp) {
              await broadcastToRoom(rideId, {
                'type': 'otp_invalid',
                'rideId': rideId,
              });
              return;
            }
            ride['rideStarted'] = true;
            ride['status'] = 'in_progress';
            ride['updatedAt'] = DateTime.now().toIso8601String();
            await broadcastToRoom(rideId, {
              'type': 'otp_verified',
              'rideId': rideId,
            });
            await broadcastToRoom(rideId, {
              'type': 'ride_started',
              'rideId': rideId,
            });
            return;

          case 'driver_location':
            final rideId = msg['rideId'];
            final lat = msg['lat'];
            final lng = msg['lng'];
            if (rideId is! String ||
                rideId.isEmpty ||
                lat is! num ||
                lng is! num)
              return;
            await broadcastToRoom(rideId, {
              'type': 'driver_location',
              'rideId': rideId,
              'lat': lat.toDouble(),
              'lng': lng.toDouble(),
              if (msg['progress'] is num)
                'progress': (msg['progress'] as num).toDouble(),
            });
            if (rides.containsKey(rideId)) {
              rides[rideId]!['status'] = (rides[rideId]!['rideStarted'] == true)
                  ? 'in_progress'
                  : 'otp_pending';
              rides[rideId]!['driverLocation'] = {
                'lat': lat.toDouble(),
                'lng': lng.toDouble(),
              };
              if (msg['progress'] is num) {
                rides[rideId]!['progress'] = (msg['progress'] as num)
                    .toDouble();
              }
              rides[rideId]!['updatedAt'] = DateTime.now().toIso8601String();
            }
            return;

          case 'ride_complete':
            final rideId = msg['rideId'];
            if (rideId is! String || rideId.isEmpty) return;
            final finalPrice = msg['finalPrice'];
            await broadcastToRoom(rideId, {
              'type': 'ride_complete',
              'rideId': rideId,
              if (finalPrice is num) 'finalPrice': finalPrice.toInt(),
              'completedAt': DateTime.now().toIso8601String(),
            });
            if (rides.containsKey(rideId)) {
              rides[rideId]!['status'] = 'completed';
              if (finalPrice is num)
                rides[rideId]!['finalPrice'] = finalPrice.toInt();
              rides[rideId]!['updatedAt'] = DateTime.now().toIso8601String();
            }
            return;

          case 'chat_message':
            final rideId = msg['rideId'];
            final text = msg['text'];
            final role = msg['role'];
            print("Chat from $role in room $rideId: $text");
            if (rideId is! String || text is! String || role is! String) return;

            await broadcastToRoom(rideId, {
              'type': 'chat_message',
              'rideId': rideId,
              'role': role,
              'text': text,
              'driverId': role == 'driver'
                  ? (msg['driverId'] ?? socketDriverId[socket])
                  : null,
              'driverName': role == 'driver' ? msg['driverName'] : null,
              'userName': role == 'user' ? (msg['userName']) : null,
            });

            if (rides.containsKey(rideId)) {
              final logEntry = {
                'ts': DateTime.now().toIso8601String(),
                'from': role,
                'text': text,
              };
              (rides[rideId]!['logs'] as List?)?.add(logEntry);
              saveDbs();
            }
            return;

          case 'cancel_negotiation':
            final rideId = msg['rideId'];
            if (rideId is! String || rideId.isEmpty) return;
            await broadcastToRoom(rideId, {
              'type': 'negotiation_cancelled',
              'rideId': rideId,
              'reason': msg['reason'] ?? 'User or Driver cancelled',
            });
            if (rides.containsKey(rideId)) {
              rides[rideId]!['status'] = 'cancelled';
              rides[rideId]!['updatedAt'] = DateTime.now().toIso8601String();
            }
            // Optional: Clean up room
            rooms.remove(rideId);
            acceptState.remove(rideId);
            return;

          default:
            return;
        }
      },
      onDone: () {
        driverSockets.remove(socket);
        final driverId = socketDriverId[socket];
        if (driverId != null && drivers.containsKey(driverId)) {
          drivers[driverId]!['online'] = false;
          drivers[driverId]!['lastSeen'] = DateTime.now().toIso8601String();
        }
        socketDriverId.remove(socket);
        for (final room in rooms.values) {
          room.remove(socket);
        }
      },
      onError: (_) {
        driverSockets.remove(socket);
        final driverId = socketDriverId[socket];
        if (driverId != null && drivers.containsKey(driverId)) {
          drivers[driverId]!['online'] = false;
          drivers[driverId]!['lastSeen'] = DateTime.now().toIso8601String();
        }
        socketDriverId.remove(socket);
        for (final room in rooms.values) {
          room.remove(socket);
        }
      },
      cancelOnError: true,
    );
  }
}
