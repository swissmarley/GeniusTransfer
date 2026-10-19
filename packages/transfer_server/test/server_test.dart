import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  late TransferServer server;
  late String t; // The session token.
  final photo = pattern(300000);
  final pdf = pattern(1234, offset: 99);

  setUp(() async {
    dir = await tempDir();
    final files = [
      await LocalSharedFile.fromPath(
          (await writeFile(dir, 'IMG_0412.HEIC', photo)).path),
      await LocalSharedFile.fromPath(
          (await writeFile(dir, 'Contract é.pdf', pdf)).path),
      await LocalSharedFile.fromPath(
          (await writeFile(dir, 'empty.txt', const [])).path),
    ];
    server = await startServer(files);
    t = server.token;
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  group('token gate', () {
    test('the page is served under the token', () async {
      final r = await send(server, '/$t/', headers: {'user-agent': uaIphoneSafari});
      expect(r.status, 200);
      expect(r.header('content-type'), startsWith('text/html'));
      expect(r.text, contains('IMG_0412.HEIC'));
      expect(r.text, contains('3 files for you'));
    });

    test('the token is case-insensitive', () async {
      final r = await send(server, '/${t.toLowerCase()}/');
      expect(r.status, 200);
    });

    test('without the trailing slash, redirects to it', () async {
      final r = await send(server, '/$t');
      expect(r.status, 302);
      expect(r.header('location'), '/$t/');
    });

    test('requests without the right token reveal nothing', () async {
      final wrong = '${t.substring(0, 25)}${t[25] == 'A' ? 'B' : 'A'}';
      for (final path in [
        '/',
        '/favicon.ico',
        '/f/0/IMG_0412.HEIC',
        '/status',
        '/$wrong/',
        '/$wrong/f/0/x',
        '/${t.substring(0, 25)}/',
        '/${t}A/',
        '/%2F$t/',
        '//$t/',
      ]) {
        final r = await send(server, path);
        expect(r.status, 404, reason: path);
        expect(r.text, contains('This link has expired'), reason: path);
        final visible =
            r.text.replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), '');
        expect(visible, isNot(contains('IMG_0412')), reason: path);
        expect(visible, isNot(contains(t)), reason: path);
        expect(visible, isNot(contains('file')), reason: path);
        expect(visible, isNot(contains('<script')), reason: path);
      }
    });

    test('a wrong Host header is refused (DNS rebinding)', () async {
      final r =
          await send(server, '/$t/', hostOverride: 'attacker.example');
      expect(r.status, 400);
      expect(r.text, isEmpty);
    });

    test('other methods are refused', () async {
      expect((await send(server, '/$t/', method: 'POST')).status, 405);
      expect((await send(server, '/$t/f/0/x', method: 'PUT')).status, 405);
      expect((await send(server, '/$t/f/0/x', method: 'DELETE')).status, 405);
    });
  });

  group('downloads', () {
    test('a whole file, with the right headers', () async {
      final r = await send(server, '/$t/f/0/IMG_0412.HEIC');
      expect(r.status, 200);
      expect(r.body, photo);
      expect(r.header('content-length'), '${photo.length}');
      expect(r.header('accept-ranges'), 'bytes');
      expect(r.header('content-type'), 'image/heic');
      expect(r.header('content-disposition'),
          'attachment; filename="IMG_0412.HEIC"; filename*=UTF-8\'\'IMG_0412.HEIC');
      expect(r.header('etag'), isNotNull);
      expect(r.header('last-modified'), isNotNull);
      expect(r.header('cache-control'), 'no-store');
      expect(r.header('x-content-type-options'), 'nosniff');
    });

    test('the name segment is decoration only', () async {
      for (final path in [
        '/$t/f/1/anything.exe',
        '/$t/f/1/..%2F..%2F..%2Fetc%2Fpasswd',
        '/$t/f/1/',
        '/$t/f/1',
      ]) {
        final r = await send(server, path);
        expect(r.status, 200, reason: path);
        expect(r.body, pdf, reason: path);
        expect(r.header('content-disposition'), contains('Contract'));
      }
    });

    test('bad indexes and traversal attempts are 404', () async {
      for (final path in [
        '/$t/f/3/x',
        '/$t/f/-1/x',
        '/$t/f/01/x',
        '/$t/f/1a/x',
        '/$t/f/+1/x',
        '/$t/f/1.0/x',
        '/$t/f/9999999999/x',
        '/$t/f//x',
        '/$t/f/0/x/y',
        '/$t/f/../../../../etc/passwd',
        '/$t/../../etc/passwd',
        '/$t/%2e%2e/%2e%2e/etc/passwd',
        '/$t/f/0%2F..%2F..%2Fetc%2Fpasswd/x',
      ]) {
        final r = await send(server, path);
        expect(r.status, 404, reason: path);
        expect(r.text, isNot(contains('root:')), reason: path);
      }
    });

    test('raw (un-normalized) traversal paths never reach the disk', () async {
      for (final path in [
        '/$t/f/../../../../etc/passwd',
        '/$t/../../../etc/passwd',
        '/$t/f/0/../../../../etc/passwd',
        '/$t/f/..%2f..%2f..%2fetc%2fpasswd/x',
        '/$t/f/0/%2e%2e%2f%2e%2e%2fetc%2fpasswd',
        '/$t\\..\\..\\etc\\passwd',
      ]) {
        final reply = String.fromCharCodes(await rawExchange(
            server.port!,
            'GET $path HTTP/1.1\r\nHost: 127.0.0.1:${server.port}\r\n'
                    'Connection: close\r\n\r\n'
                .codeUnits));
        expect(reply, isNot(contains('root:')), reason: path);
        final status = reply.isEmpty ? '' : reply.split('\r\n').first;
        // Either refused, or file 0 (the name segment is decoration).
        if (status.contains('200')) {
          expect(reply, contains('filename="IMG_0412.HEIC"'), reason: path);
        }
      }
    });

    test('HEAD sends headers without a body', () async {
      final r = await send(server, '/$t/f/0/x', method: 'HEAD');
      expect(r.status, 200);
      expect(r.header('content-length'), '${photo.length}');
      expect(r.body, isEmpty);
    });

    test('an empty file', () async {
      final r = await send(server, '/$t/f/2/empty.txt');
      expect(r.status, 200);
      expect(r.body, isEmpty);
      expect(r.header('content-length'), '0');
    });

    test('Range: one range', () async {
      final r = await send(server, '/$t/f/0/x', headers: {'range': 'bytes=100-199'});
      expect(r.status, 206);
      expect(r.header('content-range'), 'bytes 100-199/${photo.length}');
      expect(r.header('content-length'), '100');
      expect(r.body, photo.sublist(100, 200));
    });

    test('Range: open-ended, suffix and last byte', () async {
      final open = await send(server, '/$t/f/0/x', headers: {'range': 'bytes=299990-'});
      expect(open.status, 206);
      expect(open.body, photo.sublist(299990));
      final suffix = await send(server, '/$t/f/0/x', headers: {'range': 'bytes=-5'});
      expect(suffix.body, photo.sublist(photo.length - 5));
      final last = await send(server, '/$t/f/0/x',
          headers: {'range': 'bytes=${photo.length - 1}-${photo.length - 1}'});
      expect(last.body, [photo.last]);
    });

    test('Range: past the end is 416', () async {
      final r = await send(server, '/$t/f/0/x',
          headers: {'range': 'bytes=${photo.length}-'});
      expect(r.status, 416);
      expect(r.header('content-range'), 'bytes */${photo.length}');
      expect(r.body, isEmpty);
    });

    test('Range: several ranges get the whole file', () async {
      final r = await send(server, '/$t/f/0/x',
          headers: {'range': 'bytes=0-1,5-6'});
      expect(r.status, 200);
      expect(r.body, photo);
    });

    test('If-Range: matching ETag gets the range, other values the file',
        () async {
      final etag = (await send(server, '/$t/f/0/x', method: 'HEAD'))
          .header('etag')!;
      final ok = await send(server, '/$t/f/0/x',
          headers: {'range': 'bytes=0-9', 'if-range': etag});
      expect(ok.status, 206);
      final stale = await send(server, '/$t/f/0/x',
          headers: {'range': 'bytes=0-9', 'if-range': '"stale"'});
      expect(stale.status, 200);
      expect(stale.body, photo);
    });
  });

  group('page', () {
    test('security headers', () async {
      final r = await send(server, '/$t/');
      final csp = r.header('content-security-policy')!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, matches(RegExp(r"script-src 'nonce-[A-Za-z0-9_-]{20,}'")));
      final nonce =
          RegExp(r"'nonce-([A-Za-z0-9_-]+)'").firstMatch(csp)!.group(1);
      expect(r.text, contains('<script nonce="$nonce">'));
      expect(r.header('referrer-policy'), 'no-referrer');
      expect(r.header('cache-control'), 'no-store');
    });

    test('a new nonce for every response', () async {
      final a = (await send(server, '/$t/')).header('content-security-policy');
      final b = (await send(server, '/$t/')).header('content-security-policy');
      expect(a, isNot(b));
    });

    test('status reports the session is alive', () async {
      final r = await send(server, '/$t/status');
      expect(r.status, 200);
      expect(jsonDecode(r.text), {'files': 3});
    });
  });

  group('events', () {
    test('a guest is announced once, with its device', () async {
      final events = recordEvents(server);
      await send(server, '/$t/', headers: {'user-agent': uaAndroidChrome});
      await send(server, '/$t/', headers: {'user-agent': uaAndroidChrome});
      await send(server, '/$t/f/1/x', headers: {'user-agent': uaAndroidChrome});
      await pumpEventQueue();
      final guests = events.whereType<GuestConnected>().toList();
      expect(guests, hasLength(1));
      expect(guests.single.address, '127.0.0.1');
      expect(guests.single.device.label, 'Android · Chrome');
    });

    test('downloads report start and completion', () async {
      final events = recordEvents(server);
      await send(server, '/$t/f/0/x', headers: {'range': 'bytes=10-'});
      await pumpEventQueue();
      final started = events.whereType<DownloadStarted>().single;
      expect(started.fileIndex, 0);
      expect(started.start, 10);
      expect(started.end, photo.length);
      final ended = events.whereType<DownloadEnded>().single;
      expect(ended.id, started.id);
      expect(ended.completed, isTrue);
      expect(ended.sent, photo.length - 10);
    });

    test('a guest that disconnects mid-download is reported', () async {
      final big = await writeFile(dir, 'big.bin', pattern(32 * 1024 * 1024));
      final s = await startServer([await LocalSharedFile.fromPath(big.path)]);
      final events = recordEvents(s);
      final socket = await Socket.connect(loopback, s.port!);
      socket.write('GET /${s.token}/f/0/x HTTP/1.1\r\n'
          'Host: 127.0.0.1:${s.port}\r\n\r\n');
      await socket.first; // Read one chunk, then hang up.
      socket.destroy();
      final ended = await s.events
          .firstWhere((e) => e is DownloadEnded)
          .timeout(const Duration(seconds: 10)) as DownloadEnded;
      expect(ended.completed, isFalse);
      expect(ended.sent, lessThan(32 * 1024 * 1024));
      expect(events.whereType<DownloadStarted>(), hasLength(1));
      await s.stop();
    });
  });

  group('robustness', () {
    test('a TLS handshake on the HTTP port fails fast, server keeps working',
        () async {
      // Start of a TLS ClientHello, as sent by browsers that try HTTPS first.
      final hello = [0x16, 0x03, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0xfc];
      final stopwatch = Stopwatch()..start();
      await rawExchange(server.port!, hello);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      expect((await send(server, '/$t/')).status, 200);
    });

    test('too many requests from one address get 503', () async {
      final big = await writeFile(dir, 'big.bin', pattern(16 * 1024 * 1024));
      final s = await startServer([await LocalSharedFile.fromPath(big.path)],
          config: const ServerConfig(
              preferredPort: 0, maxRequestsPerAddress: 2));
      // Two downloads that stay open because nobody reads them.
      final sockets = <Socket>[];
      for (var i = 0; i < 2; i++) {
        final socket = await Socket.connect(loopback, s.port!);
        socket.write('GET /${s.token}/f/0/x HTTP/1.1\r\n'
            'Host: 127.0.0.1:${s.port}\r\n\r\n');
        sockets.add(socket);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final r = await send(s, '/${s.token}/');
      expect(r.status, 503);
      expect(r.header('retry-after'), '2');
      for (final socket in sockets) {
        socket.destroy();
      }
      await s.stop();
    });
  });

  group('lifecycle', () {
    test('stop closes the port and the session for good', () async {
      final port = server.port!;
      await server.stop();
      await expectLater(
          Socket.connect(loopback, port), throwsA(isA<SocketException>()));
      expect(server.isStopped, isTrue);
      expect(() => server.resume([loopback]), throwsStateError);
    });

    test('a new session on the same port rejects the old token', () async {
      final port = server.port!;
      final oldToken = t;
      await server.stop();
      final next = TransferServer(
          files: const [], config: ServerConfig(preferredPort: port));
      await next.start([loopback]);
      expect(next.port, port);
      expect(next.token, isNot(oldToken));
      final client = HttpClient();
      final req = await client.get('127.0.0.1', port, '/$oldToken/status');
      final res = await req.close();
      expect(res.statusCode, 404);
      await res.drain<void>();
      client.close(force: true);
      await next.stop();
    });

    test('suspend refuses new connections, resume brings back the same URL',
        () async {
      final url = server.url;
      await server.suspend();
      expect(server.isListening, isFalse);
      await expectLater(Socket.connect(loopback, server.port!),
          throwsA(isA<SocketException>()));
      await server.resume([loopback]);
      expect(server.isListening, isTrue);
      expect(server.url, url);
      expect((await send(server, '/$t/')).status, 200);
    });

    test('a download in progress survives suspend', () async {
      final big = await writeFile(dir, 'big.bin', pattern(8 * 1024 * 1024));
      final s = await startServer([await LocalSharedFile.fromPath(big.path)]);
      final client = HttpClient();
      final req = await client.get('127.0.0.1', s.port!, '/${s.token}/f/0/x');
      final res = await req.close();
      final received = <int>[];
      var suspended = false;
      await for (final chunk in res) {
        received.addAll(chunk);
        if (!suspended) {
          suspended = true;
          await s.suspend();
        }
      }
      expect(received.length, 8 * 1024 * 1024);
      client.close(force: true);
      await s.stop();
    });

    test('idle sessions are reported', () async {
      final s = await startServer(const [],
          config: const ServerConfig(
              preferredPort: 0,
              idleTimeout: Duration(milliseconds: 200),
              idleCheckInterval: Duration(milliseconds: 50)));
      await expectLater(s.events, emitsThrough(isA<SessionIdle>()));
      await s.stop();
    });

    test('the URL has the token and the bound address', () {
      expect(server.url.toString(),
          'http://127.0.0.1:${server.port}/$t/');
    });
  });
}
