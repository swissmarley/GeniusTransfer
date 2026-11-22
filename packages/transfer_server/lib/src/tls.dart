import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// A self-signed certificate and its private key, for serving HTTPS on the
/// local network.
///
/// No certificate authority signs certificates for private IP addresses, and
/// the app works offline, so the certificate is self-signed. Browsers warn
/// about it once; after that the connection is encrypted, so other devices
/// on the same Wi-Fi (or the hotspot) cannot read the files in transit.
///
/// The certificate follows what Apple and Chrome require of TLS server
/// certificates (ECDSA P-256 with SHA-256, the address in subjectAltName,
/// extendedKeyUsage serverAuth, a short validity), so the warning can be
/// bypassed in every browser instead of the connection failing outright.
class TlsIdentity {
  TlsIdentity._(this.certificateDer, this.privateKeyDer);

  /// The certificate, DER encoded.
  final Uint8List certificateDer;

  /// The private key, as a SEC 1 `EC PRIVATE KEY`, DER encoded.
  final Uint8List privateKeyDer;

  String get certificatePem => _pem('CERTIFICATE', certificateDer);
  String get privateKeyPem => _pem('EC PRIVATE KEY', privateKeyDer);

  /// SHA-256 of the certificate, as browsers show it (`AB:CD:…`).
  String get fingerprint => [
        for (final b in SHA256Digest().process(certificateDer))
          b.toRadixString(16).padLeft(2, '0').toUpperCase()
      ].join(':');

  /// A [SecurityContext] that serves this certificate.
  SecurityContext get securityContext => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  /// Makes a new key and a certificate valid for [addresses], in a
  /// background isolate (key generation takes a moment on a phone).
  static Future<TlsIdentity> generate(List<InternetAddress> addresses,
      {DateTime? now}) {
    final raw = [for (final a in addresses) a.rawAddress];
    final time = now ?? DateTime.now();
    return Isolate.run(() {
      final (cert, key) = _generate(raw, time);
      return TlsIdentity._(cert, key);
    });
  }

  /// Same as [generate], on the calling isolate.
  static TlsIdentity generateSync(List<InternetAddress> addresses,
      {DateTime? now}) {
    final (cert, key) = _generate(
        [for (final a in addresses) a.rawAddress], now ?? DateTime.now());
    return TlsIdentity._(cert, key);
  }
}

/// Validity: a day back for guests whose clock is behind, 30 days ahead.
const _validBefore = Duration(days: 1);
const _validAfter = Duration(days: 30);

(Uint8List, Uint8List) _generate(List<Uint8List> addresses, DateTime now) {
  final random = FortunaRandom()
    ..seed(KeyParameter(_secureBytes(32)));
  final domain = ECCurve_secp256r1();
  final generator = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(domain), random));
  final pair = generator.generateKeyPair();
  final privateKey = pair.privateKey;
  final publicKey = pair.publicKey;
  final point = publicKey.Q!.getEncoded(false); // 04 || X || Y

  // Positive, nonzero, at most 20 bytes (RFC 5280).
  final serial = _secureBytes(16)..[0] = (_secureBytes(1)[0] & 0x7f) | 0x01;

  final name = _seq([
    _set([
      _seq([_oid(_oidCommonName), _utf8('GeniusTransfer')])
    ])
  ]);
  final ecdsaSha256 = _seq([_oid(_oidEcdsaWithSha256)]);
  final sans = [
    for (final ip in addresses) _tlv(0x87, ip), // iPAddress
    _tlv(0x82, ascii.encode('localhost')), // dNSName
  ];
  final extensions = _seq([
    _extension(_oidBasicConstraints, _seq([]), critical: true),
    // digitalSignature only.
    _extension(_oidKeyUsage, _tlv(0x03, [0x07, 0x80]), critical: true),
    _extension(_oidExtKeyUsage, _seq([_oid(_oidServerAuth)])),
    _extension(_oidSubjectAltName, _seq(sans)),
  ]);
  final tbs = _seq([
    _tlv(0xa0, _int([2])), // v3
    _int(serial),
    ecdsaSha256,
    name,
    _seq([_time(now.subtract(_validBefore)), _time(now.add(_validAfter))]),
    name,
    _seq([
      _seq([_oid(_oidEcPublicKey), _oid(_oidPrime256v1)]),
      _bitString(point),
    ]),
    _tlv(0xa3, extensions),
  ]);

  final signer = Signer('SHA-256/DET-ECDSA')
    ..init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
  final sig = signer.generateSignature(tbs) as ECSignature;
  final signature = _seq([_bigInt(sig.r), _bigInt(sig.s)]);
  final certificate = _seq([tbs, ecdsaSha256, _bitString(signature)]);

  final key = _seq([
    _int([1]),
    _tlv(0x04, _fixed(privateKey.d!, 32)),
    _tlv(0xa0, _oid(_oidPrime256v1)),
    _tlv(0xa1, _bitString(point)),
  ]);
  return (certificate, key);
}

const _oidCommonName = [2, 5, 4, 3];
const _oidEcPublicKey = [1, 2, 840, 10045, 2, 1];
const _oidPrime256v1 = [1, 2, 840, 10045, 3, 1, 7];
const _oidEcdsaWithSha256 = [1, 2, 840, 10045, 4, 3, 2];
const _oidBasicConstraints = [2, 5, 29, 19];
const _oidKeyUsage = [2, 5, 29, 15];
const _oidExtKeyUsage = [2, 5, 29, 37];
const _oidSubjectAltName = [2, 5, 29, 17];
const _oidServerAuth = [1, 3, 6, 1, 5, 5, 7, 3, 1];

Uint8List _secureBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
}

String _pem(String label, Uint8List der) {
  final b64 = base64.encode(der);
  final lines = [
    for (var i = 0; i < b64.length; i += 64)
      b64.substring(i, min(i + 64, b64.length))
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

// Minimal DER encoding: just what the certificate above needs.

Uint8List _tlv(int tag, List<int> value) {
  final n = value.length;
  final List<int> length;
  if (n < 0x80) {
    length = [n];
  } else {
    final bytes = <int>[];
    for (var v = n; v > 0; v >>= 8) {
      bytes.insert(0, v & 0xff);
    }
    length = [0x80 | bytes.length, ...bytes];
  }
  return Uint8List.fromList([tag, ...length, ...value]);
}

Uint8List _seq(List<List<int>> items) =>
    _tlv(0x30, [for (final i in items) ...i]);

Uint8List _set(List<List<int>> items) =>
    _tlv(0x31, [for (final i in items) ...i]);

/// An INTEGER from unsigned big-endian bytes.
Uint8List _int(List<int> bytes) {
  var b = bytes;
  while (b.length > 1 && b[0] == 0 && b[1] < 0x80) {
    b = b.sublist(1);
  }
  return _tlv(0x02, b[0] >= 0x80 ? [0, ...b] : b);
}

Uint8List _bigInt(BigInt v) => _int(_unsigned(v));

List<int> _unsigned(BigInt v) {
  final bytes = <int>[];
  for (var x = v; x > BigInt.zero; x >>= 8) {
    bytes.insert(0, (x & BigInt.from(0xff)).toInt());
  }
  return bytes.isEmpty ? [0] : bytes;
}

List<int> _fixed(BigInt v, int length) {
  final b = _unsigned(v);
  return [...List.filled(length - b.length, 0), ...b];
}

Uint8List _bitString(List<int> bytes) => _tlv(0x03, [0, ...bytes]);

Uint8List _utf8(String s) => _tlv(0x0c, utf8.encode(s));

Uint8List _oid(List<int> parts) {
  final out = <int>[40 * parts[0] + parts[1]];
  for (final p in parts.skip(2)) {
    final chunk = <int>[p & 0x7f];
    for (var v = p >> 7; v > 0; v >>= 7) {
      chunk.insert(0, 0x80 | (v & 0x7f));
    }
    out.addAll(chunk);
  }
  return _tlv(0x06, out);
}

/// UTCTime, valid until 2049 (RFC 5280).
Uint8List _time(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return _tlv(
      0x17,
      ascii.encode('${two(u.year % 100)}${two(u.month)}${two(u.day)}'
          '${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
}

Uint8List _extension(List<int> oid, List<int> value, {bool critical = false}) =>
    _seq([
      _oid(oid),
      if (critical) _tlv(0x01, [0xff]),
      _tlv(0x04, value),
    ]);
