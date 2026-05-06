
import 'dart:io';

void main() {
  final content = File('quickcab_realtime_server.dart').readAsStringSync();
  int braces = 0;
  int lineNum = 1;
  for (int i = 0; i < content.length; i++) {
    if (content[i] == '{') braces++;
    if (content[i] == '}') braces--;
    if (content[i] == '\n') {
      //print('$lineNum: $braces');
      lineNum++;
    }
    if (lineNum >= 1290 && lineNum <= 1326) {
       // Check if it's negative at any point here
       if (braces < 0) {
         print('CRITICAL: Braces negative at line $lineNum');
       }
    }
  }
  print('Final brace count: $braces');
}
