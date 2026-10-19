import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_server/src/guest_page.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

void main() {
  group('sanitizeFileName', () {
    test('keeps ordinary names', () {
      expect(sanitizeFileName('IMG_0412.HEIC'), 'IMG_0412.HEIC');
      expect(sanitizeFileName('Contrat signé (v2).pdf'), 'Contrat signé (v2).pdf');
      expect(sanitizeFileName('写真 1.jpg'), '写真 1.jpg');
    });

    test('keeps only the last path segment', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'C:\Users\x\evil.exe'), 'evil.exe');
      expect(sanitizeFileName('a/b/'), 'file');
    });

    test('drops control, bidi and Windows-forbidden characters', () {
      expect(sanitizeFileName('a\u0000b\nc\u007f.txt'), 'abc.txt');
      expect(sanitizeFileName('photo\u202Egpj.exe'), 'photogpj.exe');
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'abcdefgh.txt');
    });

    test('dots, spaces and empty names', () {
      expect(sanitizeFileName(''), 'file');
      expect(sanitizeFileName('..'), 'file');
      expect(sanitizeFileName('   '), 'file');
      expect(sanitizeFileName('name. . '), 'name');
      expect(sanitizeFileName('.bashrc'), '_bashrc');
      expect(sanitizeFileName('..hidden.txt'), '_hidden.txt');
    });

    test('Windows reserved names get a prefix', () {
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('nul.txt'), '_nul.txt');
      expect(sanitizeFileName('com1.tar.gz'), '_com1.tar.gz');
      expect(sanitizeFileName('console.txt'), 'console.txt');
    });

    test('long names are cut to 200 UTF-8 bytes, keeping the extension', () {
      final ascii = sanitizeFileName('${'a' * 300}.jpeg');
      expect(utf8.encode(ascii).length, lessThanOrEqualTo(200));
      expect(ascii, endsWith('.jpeg'));
      final wide = sanitizeFileName('${'é' * 300}.mp4');
      expect(utf8.encode(wide).length, lessThanOrEqualTo(200));
      expect(wide, endsWith('.mp4'));
      expect(wide.contains('\uFFFD'), isFalse);
    });
  });

  group('uniqueName', () {
    late Directory dir;
    setUp(() async => dir = await tempDir());
    tearDown(() => dir.delete(recursive: true));

    test('numbers duplicates, ignoring case', () async {
      await writeFile(dir, 'a.jpg', [1]);
      final taken = <String>{};
      expect(uniqueName(dir, 'b.jpg', taken), 'b.jpg');
      expect(uniqueName(dir, 'B.JPG', taken), 'B (1).JPG');
      expect(uniqueName(dir, 'a.jpg', taken), 'a (1).jpg');
      expect(uniqueName(dir, 'a.jpg', taken), 'a (2).jpg');
      expect(uniqueName(dir, 'noext', taken), 'noext');
      expect(uniqueName(dir, 'noext', taken), 'noext (1)');
    });
  });

  group('receive session', () {
    late Directory staging;
    late TransferServer server;
    late String t;
    late List<ServerEvent> events;
    int? freeBytes;

    Future<TransferServer> startReceiving(
        {int maxFiles = 500,
        int maxBatchBytes = 20000000000,
        Duration offerTimeout = const Duration(minutes: 10),
        Duration longPoll = const Duration(seconds: 20)}) async {
      final s = TransferServer(
        mode: SessionMode.receive,
        receiveOptions: ReceiveOptions(
          stagingDir: staging,
          maxFiles: maxFiles,
          maxBatchBytes: maxBatchBytes,
          freeBytes: () async => freeBytes,
          reserveBytes: 1000,
          offerTimeout: offerTimeout,
          longPollTimeout: longPoll,
        ),
        config: const ServerConfig(
            preferredPort: 0, progressInterval: Duration.zero),
      );
      await s.start([loopback]);
      return s;
    }

    setUp(() async {
      staging = await tempDir();
      freeBytes = null;
      server = await startReceiving();
      t = server.token;
      events = recordEvents(server);
    });

    tearDown(() async {
      await server.stop();
      if (await staging.exists()) await staging.delete(recursive: true);
    });

    Future<Reply> offer(List<Map<String, Object>> files,
            {Map<String, String> headers = const {}}) =>
        send(server, '/$t/offer',
            method: 'POST',
            headers: {'content-type': 'application/json', ...headers},
            body: utf8.encode(jsonEncode({'files': files})));

    Future<String> offerId(List<Map<String, Object>> files) async {
      final r = await offer(files);
      expect(r.status, 200, reason: r.text);
      return (jsonDecode(r.text) as Map)['id'] as String;
    }

    Future<Reply> upload(String id, int index, List<int> bytes,
            {Map<String, String> headers = const {}}) =>
        send(server, '/$t/u/$id/$index',
            method: 'POST', headers: headers, body: bytes);

    Future<Map<String, dynamic>> poll(String id) async {
      final r = await send(server, '/$t/offer/$id');
      expect(r.status, 200);
      return jsonDecode(r.text) as Map<String, dynamic>;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('the receive page has a form that works without JavaScript', () async {
      final r = await send(server, '/$t/', headers: {'user-agent': uaIphoneSafari});
      expect(r.status, 200);
      expect(r.text, contains('Send files to the other device'));
      expect(r.text,
          contains('<form id="form" method="post" action="u" enctype="multipart/form-data">'));
      expect(r.text, contains('type="file" name="f" multiple'));
      expect(r.text, isNot(contains('http://')));
      expect(r.text, isNot(contains('https://')));
    });

    test('the receive script is ES5 only', () {
      for (final forbidden in [
        '=>', '`', 'let ', 'const ', 'class ', 'fetch(', 'Promise', //
        'async ', 'await ', '...', '?.', '??', 'includes(', 'FormData',
      ]) {
        expect(receivePageScriptForTest, isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('send-mode sessions have no upload routes', () async {
      final sendServer = await startServer(const []);
      try {
        final r = await send(sendServer, '/${sendServer.token}/offer',
            method: 'POST', body: utf8.encode('{"files":[]}'));
        expect(r.status, 404);
      } finally {
        await sendServer.stop();
      }
    });

    test('a receive session needs options', () {
      expect(() => TransferServer(mode: SessionMode.receive),
          throwsArgumentError);
    });

    test('offer, accept, upload: files arrive with their content', () async {
      final a = pattern(150000);
      final b = pattern(10, offset: 3);
      final id = await offerId([
        {'name': 'IMG_1.HEIC', 'size': a.length, 'type': 'image/heic'},
        {'name': '../../secret.txt', 'size': b.length, 'type': ''},
        {'name': 'empty', 'size': 0, 'type': ''},
      ]);
      await settle();
      final offered = events.whereType<UploadOffered>().single;
      expect(offered.id, id);
      expect(offered.quarantined, isFalse);
      expect(offered.totalBytes, a.length + b.length);
      expect(offered.files.map((f) => f.name),
          ['IMG_1.HEIC', 'secret.txt', 'empty']);
      expect(offered.device.platform, GuestPlatform.other);

      // Uploading before approval is refused.
      expect((await upload(id, 0, a)).status, 403);

      expect(await server.approveUpload(id), isTrue);
      expect(await server.approveUpload(id), isFalse);
      expect((await poll(id))['state'], 'accepted');

      expect((await upload(id, 0, a)).status, 200);
      expect((await upload(id, 0, a)).status, 409);
      expect((await upload(id, 1, b)).status, 200);
      expect((await upload(id, 2, const [])).status, 200);
      final state = await poll(id);
      expect(state['state'], 'done');
      expect(state['received'], [0, 1, 2]);

      await settle();
      final received = events.whereType<UploadFileReceived>().toList();
      expect(received.map((e) => e.name), ['IMG_1.HEIC', 'secret.txt', 'empty']);
      expect(await received[0].file.readAsBytes(), a);
      expect(await received[1].file.readAsBytes(), b);
      expect(received[1].file.parent.path, server.uploadFolder(id)!.path);
      expect(File('${staging.path}/secret.txt').existsSync(), isFalse);
      expect(events.whereType<UploadProgress>(), isNotEmpty);
      final finished = events.whereType<UploadBatchFinished>().single;
      expect(finished.fileCount, 3);
    });

    test('the long poll answers as soon as the host decides', () async {
      final id = await offerId([
        {'name': 'a.jpg', 'size': 1, 'type': 'image/jpeg'}
      ]);
      final watch = Stopwatch()..start();
      final answer = poll(id);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await server.declineUpload(id);
      expect((await answer)['state'], 'declined');
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect((await upload(id, 0, [1])).status, 403);
    });

    test('the long poll gives up after its timeout', () async {
      await server.stop();
      server = await startReceiving(longPoll: const Duration(milliseconds: 300));
      t = server.token;
      final r = await offer([
        {'name': 'a.jpg', 'size': 1, 'type': ''}
      ]);
      final id = (jsonDecode(r.text) as Map)['id'] as String;
      expect((await poll(id))['state'], 'pending');
    });

    test('duplicate names are numbered', () async {
      final id = await offerId([
        {'name': 'a.jpg', 'size': 1, 'type': ''},
        {'name': 'A.JPG', 'size': 1, 'type': ''},
        {'name': 'sub/a.jpg', 'size': 1, 'type': ''},
      ]);
      await server.approveUpload(id);
      for (var i = 0; i < 3; i++) {
        expect((await upload(id, i, [i])).status, 200);
      }
      await settle();
      expect(events.whereType<UploadFileReceived>().map((e) => e.name),
          ['a.jpg', 'A (1).JPG', 'a (2).jpg']);
    });

    test('one pending offer at a time', () async {
      await offerId([
        {'name': 'a', 'size': 1, 'type': ''}
      ]);
      final r = await offer([
        {'name': 'b', 'size': 1, 'type': ''}
      ]);
      expect(r.status, 409);
      expect(jsonDecode(r.text), {'error': 'busy'});
    });

    test('a new offer is allowed once the previous one is decided', () async {
      final id = await offerId([
        {'name': 'a', 'size': 1, 'type': ''}
      ]);
      await server.approveUpload(id);
      await offerId([
        {'name': 'b', 'size': 1, 'type': ''}
      ]);
    });

    test('limits: number of files, total size, free space', () async {
      await server.stop();
      server = await startReceiving(maxFiles: 2, maxBatchBytes: 1000);
      t = server.token;
      var r = await offer([
        for (var i = 0; i < 3; i++) {'name': '$i', 'size': 1, 'type': ''}
      ]);
      expect(r.status, 413);
      expect(jsonDecode(r.text), {'error': 'too_many_files'});

      r = await offer([
        {'name': 'a', 'size': 600, 'type': ''},
        {'name': 'b', 'size': 401, 'type': ''},
      ]);
      expect(r.status, 413);
      expect(jsonDecode(r.text), {'error': 'too_large'});

      freeBytes = 1500; // Minus the 1000-byte reserve leaves 500.
      r = await offer([
        {'name': 'a', 'size': 501, 'type': ''}
      ]);
      expect(r.status, 507);
      expect(jsonDecode(r.text), {'error': 'no_space'});
      r = await offer([
        {'name': 'a', 'size': 500, 'type': ''}
      ]);
      expect(r.status, 200);
    });

    test('malformed offers are refused', () async {
      for (final body in [
        'not json',
        '{}',
        '{"files":[]}',
        '{"files":[{"name":"a"}]}',
        '{"files":[{"name":"a","size":-1}]}',
        '{"files":[{"name":"a","size":1.5}]}',
        '{"files":[{"name":3,"size":1}]}',
      ]) {
        final r = await send(server, '/$t/offer',
            method: 'POST', body: utf8.encode(body));
        expect(r.status, 400, reason: body);
        expect(jsonDecode(r.text), {'error': 'bad_request'}, reason: body);
      }
      final big = await send(server, '/$t/offer',
          method: 'POST', body: List.filled(64 * 1024 + 1, 0x20));
      expect(big.status, 413);
    });

    test('cross-site requests are refused; Origin null is fine', () async {
      var r = await offer([
        {'name': 'a', 'size': 1, 'type': ''}
      ], headers: {'origin': 'http://evil.example'});
      expect(r.status, 403);
      r = await offer([
        {'name': 'a', 'size': 1, 'type': ''}
      ], headers: {'origin': 'null'});
      expect(r.status, 200);
      final id = (jsonDecode(r.text) as Map)['id'] as String;
      await server.approveUpload(id);
      r = await upload(id, 0, [1], headers: {'origin': 'http://evil.example'});
      expect(r.status, 403);
      r = await upload(id, 0, [1],
          headers: {'origin': 'http://127.0.0.1:${server.port}'});
      expect(r.status, 200);
    });

    test('the token is required', () async {
      final r = await send(server, '/offer',
          method: 'POST', body: utf8.encode('{"files":[]}'));
      expect(r.status, 404);
      final u = await send(server, '/AAAA/u', method: 'POST', body: [1]);
      expect(u.status, 404);
    });

    test('uploads must match the offered size and have a length', () async {
      final id = await offerId([
        {'name': 'a', 'size': 5, 'type': ''}
      ]);
      await server.approveUpload(id);
      expect((await upload(id, 0, [1, 2, 3])).status, 400);
      expect((await upload(id, 1, [1])).status, 404);
      expect((await send(server, '/$t/u/$id/00', method: 'POST', body: [1]))
          .status, 404);
      expect((await send(server, '/$t/u/nope/0', method: 'POST', body: [1]))
          .status, 404);

      // Chunked: no Content-Length.
      final reply = await rawExchange(
          server.port!,
          ascii.encode('POST /$t/u/$id/0 HTTP/1.1\r\n'
              'Host: 127.0.0.1:${server.port}\r\n'
              'Transfer-Encoding: chunked\r\n\r\n'
              '5\r\nhello\r\n0\r\n\r\n'));
      expect(ascii.decode(reply, allowInvalid: true), startsWith('HTTP/1.1 411'));
      expect((await upload(id, 0, [1, 2, 3, 4, 5])).status, 200);
    });

    test('a cut-off upload leaves no partial file and can be retried',
        () async {
      final id = await offerId([
        {'name': 'big.bin', 'size': 100000, 'type': ''}
      ]);
      await server.approveUpload(id);
      final socket = await Socket.connect(loopback, server.port!);
      socket.add(ascii.encode('POST /$t/u/$id/0 HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n'
          'Content-Length: 100000\r\n\r\n'));
      socket.add(pattern(5000));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File('${staging.path}/$id/.part-0').existsSync(), isTrue);
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(File('${staging.path}/$id/.part-0').existsSync(), isFalse);
      expect(events.whereType<UploadFileFailed>(), hasLength(1));

      expect((await upload(id, 0, pattern(100000))).status, 200);
      expect((await poll(id))['state'], 'done');
    });

    test('stop deletes partial files and keeps finished ones', () async {
      final id = await offerId([
        {'name': 'done.txt', 'size': 3, 'type': ''},
        {'name': 'partial.bin', 'size': 100000, 'type': ''},
      ]);
      await server.approveUpload(id);
      expect((await upload(id, 0, [1, 2, 3])).status, 200);
      final socket = await Socket.connect(loopback, server.port!);
      socket.add(ascii.encode('POST /$t/u/$id/1 HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n'
          'Content-Length: 100000\r\n\r\n'));
      socket.add(pattern(5000));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await server.stop();
      socket.destroy();
      final left = Directory('${staging.path}/$id')
          .listSync(recursive: true)
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toSet();
      expect(left, {'files', 'done.txt'});
    });

    test('unanswered offers expire', () async {
      await server.stop();
      server =
          await startReceiving(offerTimeout: const Duration(milliseconds: 200));
      t = server.token;
      events = recordEvents(server);
      final id = await offerId([
        {'name': 'a', 'size': 1, 'type': ''}
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events.whereType<UploadOfferExpired>().single.id, id);
      expect((await poll(id))['state'], 'expired');
      expect(await server.approveUpload(id), isFalse);
    });

    group('without JavaScript', () {
      List<int> multipart(Map<String, List<int>> files,
          {String boundary = 'XyZ'}) {
        final out = <int>[];
        files.forEach((name, bytes) {
          out
            ..addAll(utf8.encode('--$boundary\r\n'
                'Content-Disposition: form-data; name="f"; filename="$name"\r\n'
                'Content-Type: application/octet-stream\r\n\r\n'))
            ..addAll(bytes)
            ..addAll(utf8.encode('\r\n'));
        });
        out.addAll(utf8.encode('--$boundary--\r\n'));
        return out;
      }

      Future<Reply> post(List<int> body, {String boundary = 'XyZ'}) =>
          send(server, '/$t/u',
              method: 'POST',
              headers: {
                'content-type': 'multipart/form-data; boundary=$boundary'
              },
              body: body);

      test('files wait in quarantine until accepted', () async {
        final a = pattern(70000);
        final r = await post(multipart({'Fête.jpg': a, '../x.txt': [1, 2]}));
        expect(r.status, 303);
        final location = r.header('location')!;
        expect(location, startsWith('wait/'));
        final id = location.substring(5);
        await settle();
        final offered = events.whereType<UploadOffered>().single;
        expect(offered.quarantined, isTrue);
        expect(offered.files.map((f) => f.name), ['Fête.jpg', 'x.txt']);
        expect(offered.files.map((f) => f.size), [a.length, 2]);
        expect(Directory('${staging.path}/q-$id').existsSync(), isTrue);

        var page = await send(server, '/$t/wait/$id');
        expect(page.text, contains('http-equiv="refresh"'));
        expect(page.text, contains('Your files have arrived'));

        expect(await server.approveUpload(id), isTrue);
        await settle();
        final received = events.whereType<UploadFileReceived>().toList();
        expect(received.map((e) => e.name), ['Fête.jpg', 'x.txt']);
        expect(await received[0].file.readAsBytes(), a);
        expect(Directory('${staging.path}/q-$id').existsSync(), isFalse);
        expect(events.whereType<UploadBatchFinished>(), hasLength(1));

        page = await send(server, '/$t/wait/$id');
        expect(page.text, isNot(contains('http-equiv="refresh"')));
        expect(page.text, contains('2 files sent.'));
        expect(page.text, contains('href="../"'));
      });

      test('declining deletes the quarantined files', () async {
        final r = await post(multipart({'a.bin': [1, 2, 3]}));
        final id = r.header('location')!.substring(5);
        expect(await server.declineUpload(id), isTrue);
        expect(Directory('${staging.path}/q-$id').existsSync(), isFalse);
        final page = await send(server, '/$t/wait/$id');
        expect(page.text, contains('declined'));
      });

      test('an empty form says to choose files', () async {
        final body = utf8.encode('--XyZ\r\n'
            'Content-Disposition: form-data; name="f"; filename=""\r\n'
            'Content-Type: application/octet-stream\r\n\r\n\r\n--XyZ--\r\n');
        final r = await post(body);
        expect(r.status, 400);
        expect(r.text, contains('Choose at least one file first.'));
        expect(staging.listSync(), isEmpty);
      });

      test('too many files are refused and nothing is kept', () async {
        await server.stop();
        server = await startReceiving(maxFiles: 1);
        t = server.token;
        final r = await post(multipart({'a': [1], 'b': [2]}));
        expect(r.status, 413);
        expect(r.text, contains('Send at most 1.'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(staging.listSync(), isEmpty);
      });

      test('a body larger than the limit is refused up front', () async {
        await server.stop();
        server = await startReceiving(maxBatchBytes: 100);
        t = server.token;
        final r = await post(multipart({'a': pattern(500)}));
        expect(r.status, 413);
        expect(staging.listSync(), isEmpty);
      });

      test('busy while another offer is pending', () async {
        await offerId([
          {'name': 'a', 'size': 1, 'type': ''}
        ]);
        final r = await post(multipart({'a': [1]}));
        expect(r.status, 409);
        expect(r.text, contains('still deciding'));
      });

      test('stop deletes the quarantine', () async {
        final r = await post(multipart({'a': [1]}));
        final id = r.header('location')!.substring(5);
        await server.stop();
        expect(Directory('${staging.path}/q-$id').existsSync(), isFalse);
      });
    });
  });

  test('wait page has no script and no external resources', () {
    final html = renderWaitPage(
        title: 'T', body: 'B', refresh: true, strings: GuestStrings.english);
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('http://')));
    expect(html, isNot(contains('https://')));
  });
}
