import 'dart:convert';
import 'dart:io';

import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  late TransferServer server;
  late String t;
  final content = pattern(300 * 1024);

  setUp(() async {
    dir = await tempDir();
    final f = await writeFile(dir, 'photo.jpg', content);
    server = await startServer([await LocalSharedFile.fromPath(f.path)],
        secure: true);
    t = server.token;
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  group('certificate', () {
    test('is accepted by TLS for its addresses', () {
      final id = TlsIdentity.generateSync(
          [InternetAddress('192.168.1.23'), InternetAddress.loopbackIPv4]);
      expect(id.certificatePem, startsWith('-----BEGIN CERTIFICATE-----\n'));
      expect(id.privateKeyPem, startsWith('-----BEGIN EC PRIVATE KEY-----\n'));
      expect(id.fingerprint, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
      // Loads into BoringSSL as a server identity and as a trust anchor.
      id.securityContext;
      SecurityContext(withTrustedRoots: false)
          .setTrustedCertificatesBytes(utf8.encode(id.certificatePem));
    });

    test('has what browsers require', () {
      final id = TlsIdentity.generateSync([InternetAddress('10.0.0.7')],
          now: DateTime.utc(2026, 11, 22, 12));
      final der = id.certificateDer;
      bool has(List<int> bytes) {
        outer:
        for (var i = 0; i + bytes.length <= der.length; i++) {
          for (var j = 0; j < bytes.length; j++) {
            if (der[i + j] != bytes[j]) continue outer;
          }
          return true;
        }
        return false;
      }

      expect(has([0x87, 4, 10, 0, 0, 7]), isTrue, reason: 'iPAddress SAN');
      expect(has([0x06, 0x08, 0x2b, 6, 1, 5, 5, 7, 3, 1]), isTrue,
          reason: 'serverAuth');
      expect(has([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 2]), isTrue,
          reason: 'ecdsa-with-SHA256');
      expect(has(ascii.encode('261121120000Z')), isTrue, reason: 'notBefore');
      expect(has(ascii.encode('261222120000Z')), isTrue, reason: 'notAfter');
    });

    test('a new one every time, with a different key', () {
      final a = TlsIdentity.generateSync([InternetAddress.loopbackIPv4]);
      final b = TlsIdentity.generateSync([InternetAddress.loopbackIPv4]);
      expect(a.fingerprint, isNot(b.fingerprint));
      expect(a.privateKeyPem, isNot(b.privateKeyPem));
      expect(SHA256Digest().process(a.certificateDer), hasLength(32));
    });
  });

  group('HTTPS session', () {
    test('the URL is https', () {
      expect(server.url!.scheme, 'https');
      expect(server.tlsIdentity, isNotNull);
    });

    test('serves the page and the file over TLS', () async {
      final page = await send(server, '/$t/');
      expect(page.status, 200);
      expect(page.text, contains('photo.jpg'));
      final file = await send(server, '/$t/f/0/photo.jpg');
      expect(file.status, 200);
      expect(file.body, content);
      final range = await send(server, '/$t/f/0/photo.jpg',
          headers: {'range': 'bytes=10-19'});
      expect(range.status, 206);
      expect(range.body, content.sublist(10, 20));
    });

    test('still refuses requests without the token', () async {
      expect((await send(server, '/nope/')).status, 404);
    });

    test('a client that does not trust the certificate cannot connect',
        () async {
      final client = HttpClient();
      try {
        await expectLater(
            () async => (await client.getUrl(server.url!)).close(),
            throwsA(isA<HandshakeException>()));
      } finally {
        client.close(force: true);
      }
    });

    test('plain HTTP on the HTTPS port fails fast, server keeps working',
        () async {
      final stopwatch = Stopwatch()..start();
      await rawExchange(server.port!,
          ascii.encode('GET /$t/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      expect((await send(server, '/$t/')).status, 200);
    });

    test('keeps the certificate across suspend and resume', () async {
      final before = server.tlsIdentity!.fingerprint;
      await server.suspend();
      await server.resume([loopback]);
      expect(server.tlsIdentity!.fingerprint, before);
      expect((await send(server, '/$t/')).status, 200);
    });

    test('the PIN cookie is Secure', () async {
      final f = await writeFile(dir, 'a.txt', [1, 2, 3]);
      final s = TransferServer(
          files: [await LocalSharedFile.fromPath(f.path)],
          pin: '1234',
          secure: true,
          config: const ServerConfig(preferredPort: 0));
      await s.start([loopback]);
      try {
        final r = await send(s, '/${s.token}/pin',
            method: 'POST',
            headers: {'content-type': 'application/x-www-form-urlencoded'},
            body: ascii.encode('pin=1234'));
        expect(r.status, 303);
        final cookie = r.headers[HttpHeaders.setCookieHeader]!.single;
        expect(cookie.toLowerCase(), contains('secure'));
      } finally {
        await s.stop();
      }
    });
  });
}
