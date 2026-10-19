import 'package:flutter_test/flutter_test.dart';
import 'package:geniustransfer/net/wifi_qr.dart';

void main() {
  test('WPA network', () {
    expect(wifiQrPayload(ssid: 'AndroidShare_1234', password: 'k7qx9mz2'),
        'WIFI:T:WPA;S:AndroidShare_1234;P:k7qx9mz2;;');
  });

  test('special characters are escaped', () {
    expect(wifiQrPayload(ssid: r'My;Wi,Fi:"5G"\x', password: r'a;b,c:d"e\f'),
        r'WIFI:T:WPA;S:My\;Wi\,Fi\:\"5G\"\\x;P:a\;b\,c\:d\"e\\f;;');
  });

  test('non-ASCII names are kept as they are', () {
    expect(wifiQrPayload(ssid: 'Café Wi‑Fi 📶', password: 'pässwörd'),
        'WIFI:T:WPA;S:Café Wi‑Fi 📶;P:pässwörd;;');
  });

  test('open and hidden networks', () {
    expect(wifiQrPayload(ssid: 'Open'), 'WIFI:T:nopass;S:Open;;');
    expect(wifiQrPayload(ssid: 'Open', password: ''), 'WIFI:T:nopass;S:Open;;');
    expect(wifiQrPayload(ssid: 'H', password: 'secret12', hidden: true),
        'WIFI:T:WPA;S:H;P:secret12;H:true;;');
  });
}
