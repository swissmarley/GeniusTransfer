import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:transfer_server/transfer_server.dart';

import 'helpers.dart';

const gib = 1024 * 1024 * 1024;

void main() {
  late Directory dir;

  setUp(() async => dir = await tempDir());
  tearDown(() async {
    await FdFileReader.shared.shutdown();
    await dir.delete(recursive: true);
  });

  /// A sparse file of [size] bytes with [marker] written at [markerAt].
  Future<File> sparseFile(int size, int markerAt, List<int> marker) async {
    final file = File('${dir.path}/sparse.bin');
    final raf = await file.open(mode: FileMode.write);
    await raf.setPosition(markerAt);
    await raf.writeFrom(marker);
    await raf.truncate(size);
    await raf.close();
    return file;
  }

  group('large files', () {
    test('Range beyond 4 GiB in a 5 GiB file', () async {
      const markerAt = 4 * gib + 12345;
      final marker = pattern(4096);
      final file = await sparseFile(5 * gib, markerAt, marker);
      final server = await startServer([await LocalSharedFile.fromPath(file.path)]);
      final r = await send(server, '/${server.token}/f/0/x',
          headers: {'range': 'bytes=$markerAt-${markerAt + 4095}'});
      expect(r.status, 206);
      expect(r.header('content-range'), 'bytes $markerAt-${markerAt + 4095}/${5 * gib}');
      expect(r.body, marker);
      final head = await send(server, '/${server.token}/f/0/x', method: 'HEAD');
      expect(head.header('content-length'), '${5 * gib}');
      await server.stop();
    });

    test('backpressure: a slow guest does not make the server buffer the file',
        () async {
      final file = await sparseFile(gib, gib - 1, [1]);
      final server = await startServer([await LocalSharedFile.fromPath(file.path)],
          config: const ServerConfig(
              preferredPort: 0, progressInterval: Duration.zero));
      var sent = 0;
      server.events.listen((e) {
        if (e is DownloadProgress) sent = e.sent;
      });
      final rssBefore = ProcessInfo.currentRss;

      // A guest that sends a request and then never reads the response.
      final socket = await Socket.connect(loopback, server.port!);
      final subscription = socket.listen((_) {})..pause();
      socket.write('GET /${server.token}/f/0/x HTTP/1.1\r\n'
          'Host: 127.0.0.1:${server.port}\r\n\r\n');
      await Future<void>.delayed(const Duration(seconds: 1));
      final sentAfterOneSecond = sent;
      await Future<void>.delayed(const Duration(seconds: 2));

      // Only socket buffers' worth was produced, not the whole 1 GiB, and
      // production stopped once the buffers were full.
      expect(sentAfterOneSecond, greaterThan(0));
      expect(sent, lessThan(64 * 1024 * 1024));
      expect(sent - sentAfterOneSecond, lessThan(8 * 1024 * 1024));
      expect(ProcessInfo.currentRss - rssBefore, lessThan(100 * 1024 * 1024));
      await subscription.cancel();
      socket.destroy();
      await server.stop();
    });

    test('a full 1 GiB download keeps memory flat', () async {
      final file = await sparseFile(gib, gib - 3, [7, 8, 9]);
      final server = await startServer([await LocalSharedFile.fromPath(file.path)]);
      final rssBefore = ProcessInfo.currentRss;
      var maxRss = rssBefore;
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final rss = ProcessInfo.currentRss;
        if (rss > maxRss) maxRss = rss;
      });

      final client = HttpClient();
      final req = await client.get('127.0.0.1', server.port!, '/${server.token}/f/0/x');
      final res = await req.close();
      var total = 0;
      List<int> tail = const [];
      await for (final chunk in res) {
        total += chunk.length;
        tail = chunk;
      }
      timer.cancel();
      expect(total, gib);
      expect(tail.sublist(tail.length - 3), [7, 8, 9]);
      expect(maxRss - rssBefore, lessThan(200 * 1024 * 1024));
      client.close(force: true);
      await server.stop();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('FdSharedFile', () {
    final libc = DynamicLibrary.process();
    final open = libc.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)>('open');
    final fcntl = libc.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('fcntl');
    const oRdonly = 0;
    const fGetfd = 1;

    int openFd(String path) {
      final p = path.toNativeUtf8();
      try {
        final fd = open(p, oRdonly);
        expect(fd, greaterThanOrEqualTo(0));
        return fd;
      } finally {
        malloc.free(p);
      }
    }

    test('reads ranges through a descriptor, in the helper isolate', () async {
      final data = pattern(3 * FdSharedFile.chunkSize + 17);
      final file = await writeFile(dir, 'a.bin', data);
      final shared =
          FdSharedFile(openFd(file.path), name: 'a.bin', length: data.length);

      Future<Uint8List> collect(int start, int end) async {
        final b = BytesBuilder();
        await for (final chunk in shared.openRead(start, end)) {
          b.add(chunk);
        }
        return b.takeBytes();
      }

      expect(await collect(0, data.length), data);
      expect(await collect(5, 10), data.sublist(5, 10));
      expect(await collect(FdSharedFile.chunkSize - 3, FdSharedFile.chunkSize + 3),
          data.sublist(FdSharedFile.chunkSize - 3, FdSharedFile.chunkSize + 3));
      expect(await collect(data.length, data.length), isEmpty);
      await shared.close();
    });

    test('serves downloads and Range like a regular file', () async {
      final data = pattern(700000);
      final file = await writeFile(dir, 'b.mov', data);
      final shared =
          FdSharedFile(openFd(file.path), name: 'b.mov', length: data.length);
      final server = await startServer([shared]);
      final full = await send(server, '/${server.token}/f/0/b.mov');
      expect(full.body, data);
      expect(full.header('content-type'), 'video/quicktime');
      final part = await send(server, '/${server.token}/f/0/b.mov',
          headers: {'range': 'bytes=600000-600099'});
      expect(part.status, 206);
      expect(part.body, data.sublist(600000, 600100));
      await server.stop();
    });

    test('offsets beyond 4 GiB', () async {
      const markerAt = 4 * gib + 999;
      final marker = pattern(1000, offset: 3);
      final file = await sparseFile(5 * gib, markerAt, marker);
      final shared = FdSharedFile(openFd(file.path),
          name: 'sparse.bin', length: 5 * gib);
      final b = BytesBuilder();
      await for (final chunk in shared.openRead(markerAt, markerAt + 1000)) {
        b.add(chunk);
      }
      expect(b.takeBytes(), marker);
      await shared.close();
    });

    test('stop() closes the descriptor', () async {
      final file = await writeFile(dir, 'c.bin', pattern(10));
      final fd = openFd(file.path);
      expect(fcntl(fd, fGetfd), isNot(-1));
      final server = await startServer(
          [FdSharedFile(fd, name: 'c.bin', length: 10)]);
      await server.stop();
      expect(fcntl(fd, fGetfd), -1);
    });

    test('a file shorter than announced fails instead of hanging', () async {
      final file = await writeFile(dir, 'd.bin', pattern(100));
      final shared = FdSharedFile(openFd(file.path), name: 'd.bin', length: 200);
      expect(shared.openRead(0, 200).drain<void>(),
          throwsA(isA<FileSystemException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await shared.close();
    });
  });
}
