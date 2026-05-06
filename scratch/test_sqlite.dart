import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.open('quickcab.db');
  final result = db.select('SELECT * FROM ride_history');
  print('Ride History count: ${result.length}');
  for (final row in result) {
    print(row);
  }
  db.dispose();
}
