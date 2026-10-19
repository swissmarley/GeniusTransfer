import 'dart:io';

import 'package:transfer_server/transfer_server.dart';

/// What kind of link an interface is, as far as its name tells.
enum LanKind { wifi, wired, hotspot, other }

/// A private IPv4 address of this device that a guest on the same network
/// can reach.
class LanAddress {
  const LanAddress(this.address, this.interfaceName, this.kind);

  final InternetAddress address;
  final String interfaceName;
  final LanKind kind;

  @override
  bool operator ==(Object other) =>
      other is LanAddress &&
      other.address == address &&
      other.interfaceName == interfaceName;

  @override
  int get hashCode => Object.hash(address, interfaceName);

  @override
  String toString() => '${address.address} ($interfaceName)';
}

/// Unix-style names (iOS, Android, macOS) that never lead to a guest on the
/// local network: cellular, VPN tunnels, Apple peer-to-peer links, loopback.
final _unixExcluded = RegExp(
    r'^(lo|pdp_ip|rmnet|ccmni|seth_|v4-|clat|dummy|ifb|utun|ipsec|tun|ppp|'
    r'awdl|llw|anpi|gif|stf|ip6tnl|sit|p2p|docker|veth|vmnet|vboxnet)');

/// Wi-Fi client interfaces: `en0` on iOS (and on most Macs), `wlan0` on
/// Android.
final _unixWifi = RegExp(r'^(en0|wlan0)$');

/// Other wired or Wi-Fi ports on Macs (`en1`, `en2`…).
final _unixWired = RegExp(r'^en\d+$');

/// Hotspot interfaces: iOS Personal Hotspot uses `bridge100`; Android
/// hotspots use vendor-specific names.
final _unixHotspot =
    RegExp(r'^(bridge\d+|ap\d+|swlan\d+|softap\d*|wlan[1-9]\d*)$');

/// Windows reports adapters by their (localized) friendly name.
final _windowsExcluded = RegExp(
    r'vethernet|virtualbox|vmware|hyper-v|wsl|docker|loopback|bluetooth|'
    r'tailscale|zerotier|hamachi|wireguard|openvpn|tap-|nordlynx|vpn|teredo|'
    r'isatap|npcap|pseudo',
    caseSensitive: false);
final _windowsWifi = RegExp(r'wi-?fi|wlan|wireless', caseSensitive: false);
final _windowsWired = RegExp(r'ethernet|^lan', caseSensitive: false);

/// Windows Mobile Hotspot shows up as "Local Area Connection* 12".
final _windowsHotspot = RegExp(r'\*', caseSensitive: false);

/// Classifies an interface by name, or returns null for interfaces that
/// never reach a local guest. Exposed for tests.
LanKind? classifyInterface(String name, {bool windows = false}) {
  if (windows) {
    if (_windowsExcluded.hasMatch(name)) return null;
    if (_windowsWifi.hasMatch(name)) return LanKind.wifi;
    if (_windowsHotspot.hasMatch(name)) return LanKind.hotspot;
    if (_windowsWired.hasMatch(name)) return LanKind.wired;
    return LanKind.other;
  }
  if (_unixExcluded.hasMatch(name)) return null;
  if (_unixWifi.hasMatch(name)) return LanKind.wifi;
  if (_unixHotspot.hasMatch(name)) return LanKind.hotspot;
  if (_unixWired.hasMatch(name)) return LanKind.wired;
  return LanKind.other;
}

/// Usable private IPv4 addresses, best first: Wi-Fi, wired, hotspot, then
/// anything else that is private.
List<LanAddress> rankAddresses(
  Iterable<(String, InternetAddress)> candidates, {
  bool windows = false,
}) {
  final found = <LanAddress>[];
  for (final (name, address) in candidates) {
    final kind = classifyInterface(name, windows: windows);
    if (kind == null || !isPrivateIpv4(address)) continue;
    final candidate = LanAddress(address, name, kind);
    if (!found.contains(candidate)) found.add(candidate);
  }
  // Stable sort keeps the system's order within one kind.
  final indexed = found.asMap().entries.toList()
    ..sort((a, b) {
      final byKind = a.value.kind.index.compareTo(b.value.kind.index);
      return byKind != 0 ? byKind : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// This device's usable LAN addresses, best first. Empty when it is on no
/// local network (no Wi-Fi, no cable, no hotspot).
Future<List<LanAddress>> findLanAddresses() async {
  final interfaces = await NetworkInterface.list(
      includeLoopback: false, type: InternetAddressType.IPv4);
  return rankAddresses([
    for (final i in interfaces)
      for (final a in i.addresses) (i.name, a),
  ], windows: Platform.isWindows);
}
