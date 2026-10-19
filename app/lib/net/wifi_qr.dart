/// The text of a QR code that joins a Wi-Fi network when scanned with the
/// stock camera (iPhone: iOS 11+; Android: the camera app or Google Lens).
///
/// Format: `WIFI:T:WPA;S:<name>;P:<password>;;`, the de facto standard
/// from ZXing. In the name and password, `\`, `;`, `,`, `"` and `:` are
/// escaped with a backslash. A null or empty [password] means an open
/// network.
String wifiQrPayload({required String ssid, String? password, bool hidden = false}) {
  final open = password == null || password.isEmpty;
  final b = StringBuffer('WIFI:')
    ..write(open ? 'T:nopass;' : 'T:WPA;')
    ..write('S:${_escape(ssid)};');
  if (!open) b.write('P:${_escape(password)};');
  if (hidden) b.write('H:true;');
  b.write(';');
  return b.toString();
}

String _escape(String s) => s.replaceAllMapped(
    RegExp(r'[\\;,":]'), (m) => '\\${m.group(0)}');
