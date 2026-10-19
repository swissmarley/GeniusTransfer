import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geniustransfer/net/lan_address.dart';

(String, InternetAddress) nic(String name, String ip) =>
    (name, InternetAddress(ip));

void main() {
  group('iOS, Android and macOS interface names', () {
    test('Wi-Fi first, cellular and VPN never', () {
      final ranked = rankAddresses([
        nic('pdp_ip0', '10.20.30.40'), // Cellular.
        nic('utun3', '10.8.0.2'), // VPN.
        nic('bridge100', '172.20.10.1'), // iPhone Personal Hotspot.
        nic('en0', '192.168.1.23'), // Wi-Fi.
        nic('lo0', '127.0.0.1'),
      ]);
      expect([for (final a in ranked) a.interfaceName], ['en0', 'bridge100']);
      expect(ranked.first.kind, LanKind.wifi);
      expect(ranked[1].kind, LanKind.hotspot);
    });

    test('Android: wlan0 is Wi-Fi, hotspot names are hotspots', () {
      for (final name in ['wlan1', 'swlan0', 'ap0', 'softap0']) {
        expect(classifyInterface(name), LanKind.hotspot, reason: name);
      }
      expect(classifyInterface('wlan0'), LanKind.wifi);
      for (final name in ['rmnet_data0', 'ccmni1', 'tun0', 'p2p-wlan0-0', 'v4-rmnet']) {
        expect(classifyInterface(name), isNull, reason: name);
      }
    });

    test('Macs: other en ports count as wired, VM bridges rank last', () {
      final ranked = rankAddresses([
        nic('bridge101', '192.168.64.1'),
        nic('en1', '192.168.1.50'),
        nic('en0', '192.168.1.51'),
      ]);
      expect([for (final a in ranked) a.interfaceName], ['en0', 'en1', 'bridge101']);
    });

    test('only private IPv4 addresses', () {
      expect(rankAddresses([nic('en0', '8.8.8.8')]), isEmpty);
      expect(rankAddresses([nic('en0', '169.254.3.4')]), isEmpty);
      expect(rankAddresses([nic('en0', '172.16.0.5')]), hasLength(1));
    });
  });

  group('Windows adapter names', () {
    List<String> rank(List<(String, InternetAddress)> nics) => [
          for (final a in rankAddresses(nics, windows: true)) a.interfaceName,
        ];

    test('Wi-Fi, then Ethernet, then Mobile Hotspot; virtual adapters never',
        () {
      expect(
        rank([
          nic('vEthernet (WSL)', '172.25.48.1'),
          nic('VirtualBox Host-Only Network', '192.168.56.1'),
          nic('Local Area Connection* 12', '192.168.137.1'),
          nic('Ethernet', '192.168.1.10'),
          nic('Wi-Fi', '192.168.1.11'),
          nic('Bluetooth Network Connection', '192.168.44.1'),
          nic('Tailscale', '100.100.1.1'),
        ]),
        ['Wi-Fi', 'Ethernet', 'Local Area Connection* 12'],
      );
    });

    test('localized names', () {
      expect(classifyInterface('WLAN', windows: true), LanKind.wifi);
      expect(classifyInterface('Ethernet 2', windows: true), LanKind.wired);
      expect(classifyInterface('Connessione alla rete locale (LAN)', windows: true),
          LanKind.other);
    });
  });
}
