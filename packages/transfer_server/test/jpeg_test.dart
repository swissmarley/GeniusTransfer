import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

/// A converted copy that remembers being released.
class FakeCopy implements SharedFile {
  FakeCopy(this.name, this.bytes);
  @override
  final String name;
  final List<int> bytes;
  bool closed = false;
  @override
  int get length => bytes.length;
  @override
  DateTime? get lastModified => null;
  @override
  Stream<List<int>> openRead(int start, int end) =>
      Stream.value(bytes.sublist(start, end));
  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory dir;
  late TransferServer server;
  late String t;
  late List<ServerEvent> events;
  var conversions = 0;
  final heic = pattern(4000);
  final jpeg = pattern(9000, offset: 5);
  FakeCopy? copy;

  Future<void> start(Future<SharedFile?> Function(SharedFile)? convert) async {
    server = TransferServer(
      files: [
        await LocalSharedFile.fromPath(
            (await writeFile(dir, 'IMG_0412.HEIC', heic)).path),
        await LocalSharedFile.fromPath(
            (await writeFile(dir, 'notes.pdf', [1, 2, 3])).path),
      ],
      jpegCopy: convert,
      config: const ServerConfig(preferredPort: 0),
    );
    await server.start([loopback]);
    t = server.token;
    events = recordEvents(server);
  }

  Future<SharedFile?> convert(SharedFile original) async {
    conversions++;
    expect(original.name, 'IMG_0412.HEIC');
    return copy = FakeCopy('IMG_0412.jpg', jpeg);
  }

  setUp(() async {
    dir = await tempDir();
    conversions = 0;
    copy = null;
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  test('Android and Windows guests get a JPG link for HEIC photos', () async {
    await start(convert);
    for (final ua in [uaAndroidChrome, uaSamsung, null]) {
      final page = await send(server, '/$t/',
          headers: {'user-agent': ?ua});
      expect(page.text,
          contains('<a class="view" href="j/0/IMG_0412.jpg" download>Download as JPG</a>'),
          reason: ua);
      expect(page.text, contains('“Download as JPG” gets a copy'), reason: ua);
      expect(page.text, isNot(contains('href="j/1/')), reason: ua);
    }
    for (final ua in [uaIphoneSafari, uaIpadDesktop]) {
      final page = await send(server, '/$t/', headers: {'user-agent': ua});
      expect(page.text, isNot(contains('Download as JPG')), reason: ua);
    }
    expect(conversions, 0, reason: 'converted only when asked for');
  });

  test('the copy is made once, served as a download, released on stop',
      () async {
    await start(convert);
    final r = await send(server, '/$t/j/0/IMG_0412.jpg');
    expect(r.status, 200);
    expect(r.body, jpeg);
    expect(r.header('content-type'), 'image/jpeg');
    expect(r.header('content-disposition'),
        startsWith('attachment; filename="IMG_0412.jpg"'));
    final etag = r.header('etag')!;
    expect(etag, startsWith('"j0-'));

    final range =
        await send(server, '/$t/j/0/IMG_0412.jpg', headers: {'range': 'bytes=10-19'});
    expect(range.status, 206);
    expect(range.body, jpeg.sublist(10, 20));
    expect(conversions, 1);

    await Future<void>.delayed(Duration.zero);
    final started = events.whereType<DownloadStarted>().first;
    expect(started.converted, isTrue);
    expect(started.end, jpeg.length);

    // The original is untouched.
    final original = await send(server, '/$t/f/0/IMG_0412.HEIC');
    expect(original.body, heic);

    await server.stop();
    expect(copy!.closed, isTrue);
  });

  test('a failed conversion says so', () async {
    await start((_) async => null);
    final r = await send(server, '/$t/j/0/IMG_0412.jpg');
    expect(r.status, 404);
    expect(r.text, contains('could not be converted'));
  });

  test('a conversion that throws says so too', () async {
    await start((_) async => throw const FileSystemException('broken'));
    final r = await send(server, '/$t/j/0/IMG_0412.jpg');
    expect(r.status, 404);
    expect(r.text, contains('could not be converted'));
  });

  test('only HEIC files, and only when the host can convert', () async {
    await start(convert);
    expect((await send(server, '/$t/j/1/notes.jpg')).status, 404);
    expect((await send(server, '/$t/j/9/x.jpg')).status, 404);
    await server.stop();
    await start(null);
    expect((await send(server, '/$t/j/0/IMG_0412.jpg')).status, 404);
    final page =
        await send(server, '/$t/', headers: {'user-agent': uaAndroidChrome});
    expect(page.text, isNot(contains('Download as JPG')));
  });
}
