import 'dart:io';

/// Whether [address] belongs to a local network, i.e. a guest we are willing
/// to serve: RFC 1918 private ranges, link-local, loopback, carrier-grade NAT
/// (100.64.0.0/10, used by some hotspots) and 192.0.0.0/24 (CLAT on phone
/// hotspots). Everything else is refused, as defence in depth: the server is
/// only ever bound to a LAN address in the first place.
bool isLanAddress(InternetAddress address) {
  var a = address;
  if (a.type == InternetAddressType.IPv6) {
    final mapped = _ipv4Mapped(a);
    if (mapped == null) return a.isLoopback || a.isLinkLocal || _isUniqueLocalV6(a);
    a = mapped;
  }
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254) ||
      b[0] == 127 ||
      (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
      (b[0] == 192 && b[1] == 0 && b[2] == 0);
}

/// Whether [address] is an RFC 1918 private IPv4 address, the kind we put in
/// the QR code.
bool isPrivateIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

InternetAddress? _ipv4Mapped(InternetAddress a) {
  final b = a.rawAddress;
  if (b.length != 16) return null;
  for (var i = 0; i < 10; i++) {
    if (b[i] != 0) return null;
  }
  if (b[10] != 0xff || b[11] != 0xff) return null;
  return InternetAddress.fromRawAddress(b.sublist(12));
}

bool _isUniqueLocalV6(InternetAddress a) => (a.rawAddress[0] & 0xfe) == 0xfc;
