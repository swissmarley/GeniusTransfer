import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  late TransferServer server;
  late String t;
  late List<ServerEvent> events;
  final photo = pattern(5000);

  Future<TransferServer> start({String? pin, SessionMode mode = SessionMode.send}) async {
    final s = TransferServer(
      files: mode == SessionMode.send
          ? [
              await LocalSharedFile.fromPath(
                  (await writeFile(dir, 'IMG_0412.HEIC', photo)).path),
              await LocalSharedFile.fromPath(
                  (await writeFile(dir, 'notes.pdf', [1, 2, 3])).path),
            ]
          : const [],
      mode: mode,
      receiveOptions:
          mode == SessionMode.receive ? ReceiveOptions(stagingDir: dir) : null,
      pin: pin,
      config: const ServerConfig(preferredPort: 0),
    );
    await s.start([loopback]);
    return s;
  }

  Future<Reply> enter(String pin, {String? tokenSegment}) => send(
        server,
        '/${tokenSegment ?? t}/pin',
        method: 'POST',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: utf8.encode('pin=$pin'),
      );

  /// The `name=value` part of the PIN cookie in [r].
  String cookieOf(Reply r) =>
      r.header('set-cookie')!.split(';').first.trim();

  setUp(() async {
    dir = await tempDir();
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  group('with a PIN', () {
    setUp(() async {
      server = await start(pin: '2468');
      t = server.token;
      events = recordEvents(server);
    });

    test('nothing is shown before the PIN', () async {
      for (final path in ['/$t/', '/$t/f/0/IMG_0412.HEIC', '/$t/v/0/x']) {
        final r = await send(server, path);
        expect(r.status, 401, reason: path);
        expect(r.text, contains('Enter the PIN'), reason: path);
        expect(r.text, isNot(contains('IMG_0412')), reason: path);
        expect(r.text, contains('action="/$t/pin"'), reason: path);
        expect(r.text, contains('inputmode="numeric"'), reason: path);
        expect(r.text, isNot(contains('<script')), reason: path);
      }
      final status = await send(server, '/$t/status');
      expect(status.status, 401);
      expect(jsonDecode(status.text), {'error': 'pin'});
    });

    test('the right PIN sets a cookie for this session only', () async {
      final r = await enter('2468');
      expect(r.status, 303);
      expect(r.header('location'), '/$t/');
      final setCookie = r.header('set-cookie')!;
      expect(setCookie, startsWith('gt_pin='));
      expect(setCookie, contains('Path=/$t/'));
      expect(setCookie, contains('HttpOnly'));
      expect(setCookie.toLowerCase(), contains('samesite=lax'));

      final cookie = {'cookie': cookieOf(r)};
      final page = await send(server, '/$t/', headers: cookie);
      expect(page.status, 200);
      expect(page.text, contains('IMG_0412.HEIC'));
      final file = await send(server, '/$t/f/0/IMG_0412.HEIC', headers: cookie);
      expect(file.status, 200);
      expect(file.body, photo);
      expect((await send(server, '/$t/status', headers: cookie)).status, 200);
    });

    test('the cookie path follows the typed form of the token', () async {
      final typed = groupToken(t).toLowerCase();
      final r = await enter('2468', tokenSegment: typed);
      expect(r.status, 303);
      expect(r.header('location'), '/$typed/');
      expect(r.header('set-cookie'), contains('Path=/$typed/'));
    });

    test('made-up cookies do not count', () async {
      final r = await send(server, '/$t/', headers: {'cookie': 'gt_pin=abc'});
      expect(r.status, 401);
      final bad = await send(server, '/$t/', headers: {'cookie': 'gt_pin'});
      expect(bad.status, 401);
    });

    test('wrong PINs count down, then lock everyone out', () async {
      final early = await enter('2468');
      final cookie = {'cookie': cookieOf(early)};

      for (var left = 4; left >= 1; left--) {
        final r = await enter('1111');
        expect(r.status, 401);
        expect(r.text,
            contains(left == 1 ? 'Wrong PIN. 1 try left.' : 'Wrong PIN. $left tries left.'));
      }
      final last = await enter('');
      expect(last.status, 403);
      expect(last.text, contains('Too many wrong PINs'));
      expect(last.text, isNot(contains('<form')));
      expect(server.pinLockedOut, isTrue);

      // Even the right PIN is refused now.
      final late = await enter('2468');
      expect(late.status, 403);
      expect(late.header('set-cookie'), isNull);

      // Guests already in keep going.
      expect((await send(server, '/$t/', headers: cookie)).status, 200);

      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<PinRejected>().map((e) => e.attemptsLeft),
          [4, 3, 2, 1, 0]);
      expect(events.whereType<PinLockedOut>(), hasLength(1));
    });

    test('PIN entry needs POST; odd bodies are wrong PINs', () async {
      final get = await send(server, '/$t/pin');
      expect(get.status, 401);
      expect(get.text, contains('Enter the PIN'));
      final junk = await send(server, '/$t/pin',
          method: 'POST', body: List.filled(5000, 0x41));
      expect(junk.status, 401);
      expect(junk.text, contains('Wrong PIN. 4 tries left.'));
    });
  });

  test('receiving sessions ask for the PIN too', () async {
    server = await start(pin: '1357', mode: SessionMode.receive);
    t = server.token;
    final page = await send(server, '/$t/');
    expect(page.status, 401);
    final offer = await send(server, '/$t/offer',
        method: 'POST', body: utf8.encode('{"files":[{"name":"a","size":1}]}'));
    expect(offer.status, 401);
    expect(jsonDecode(offer.text), {'error': 'pin'});
    final form = await send(server, '/$t/u',
        method: 'POST',
        headers: {'content-type': 'multipart/form-data; boundary=x'},
        body: utf8.encode('--x--\r\n'));
    expect(form.status, 401);
    expect(form.text, contains('Enter the PIN'));
  });

  test('a PIN must be 4 to 8 digits', () {
    for (final bad in ['123', '123456789', '12a4', ' 1234', '']) {
      expect(() => TransferServer(files: const [], pin: bad),
          throwsArgumentError,
          reason: bad);
    }
    TransferServer(files: const [], pin: '0000');
    TransferServer(files: const [], pin: '12345678');
  });

  group('without a PIN', () {
    setUp(() async {
      server = await start();
      t = server.token;
    });

    test('v/ shows the file in the browser instead of downloading it',
        () async {
      final r = await send(server, '/$t/v/0/IMG_0412.HEIC');
      expect(r.status, 200);
      expect(r.header('content-disposition'), startsWith('inline;'));
      expect(r.header('content-type'), 'image/heic');
      expect(r.body, photo);
      final range = await send(server, '/$t/v/0/IMG_0412.HEIC',
          headers: {'range': 'bytes=0-9'});
      expect(range.status, 206);
      final download = await send(server, '/$t/f/0/IMG_0412.HEIC');
      expect(download.header('content-disposition'), startsWith('attachment;'));
    });

    test('iPhone guests get an Open link for photos and videos only',
        () async {
      final iphone =
          await send(server, '/$t/', headers: {'user-agent': uaIphoneSafari});
      expect(iphone.text, contains('<a class="view" href="v/0/IMG_0412.HEIC">Open</a>'));
      expect(iphone.text, isNot(contains('href="v/1/')));
      expect(iphone.text, contains('To put a photo or video in Photos'));

      final android =
          await send(server, '/$t/', headers: {'user-agent': uaAndroidChrome});
      expect(android.text, isNot(contains('class="view"')));
      expect(android.text, isNot(contains('To put a photo or video in Photos')));
    });
  });
}
