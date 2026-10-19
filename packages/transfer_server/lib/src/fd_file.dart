import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'shared_file.dart';

/// A shared file read through an already-open file descriptor.
///
/// On Android, files picked with the system picker or received from the
/// share sheet are `content://` URIs. The app opens them natively, detaches
/// the descriptor and hands the number here, so multi-GB files are served
/// without copying them. The descriptor must be seekable (a regular file),
/// because reads use `pread` at explicit offsets, which also makes HTTP
/// Range requests cheap.
class FdSharedFile implements SharedFile {
  FdSharedFile(this.fd,
      {required this.name,
      required this.length,
      this.lastModified,
      FdFileReader? reader})
      : _reader = reader ?? FdFileReader.shared;

  /// Bytes requested from the reader isolate per round trip.
  static const chunkSize = 512 * 1024;

  final int fd;
  @override
  final String name;
  @override
  final int length;
  @override
  final DateTime? lastModified;
  final FdFileReader _reader;
  bool _closed = false;

  @override
  Stream<List<int>> openRead(int start, int end) async* {
    var position = start;
    while (position < end && !_closed) {
      final want = end - position < chunkSize ? end - position : chunkSize;
      final bytes = await _reader.read(fd, position, want);
      if (bytes.isEmpty) {
        throw FileSystemException(
            'Unexpected end of file at byte $position of $length', name);
      }
      position += bytes.length;
      yield bytes;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _Libc.instance.close(fd);
  }
}

/// Performs blocking `pread` calls on a dedicated helper isolate, so they
/// never block the isolate that runs the UI and the HTTP server.
class FdFileReader {
  FdFileReader._();

  /// The process-wide reader, started on first use.
  static final FdFileReader shared = FdFileReader._();

  SendPort? _requests;
  Future<void>? _starting;
  ReceivePort? _replies;
  Isolate? _isolate;
  int _nextId = 0;
  final _pending = <int, Completer<Uint8List>>{};

  /// Stops the helper isolate. Reads still pending fail. A later [read]
  /// starts a new helper.
  Future<void> shutdown() async {
    final starting = _starting;
    if (starting == null) return;
    await starting;
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    for (final c in _pending.values) {
      c.completeError(const FileSystemException('Reader stopped'));
    }
    _pending.clear();
    _requests = null;
    _replies = null;
    _isolate = null;
    _starting = null;
  }

  /// Reads up to [length] bytes at [offset]. Returns fewer bytes only at end
  /// of file, and an empty list exactly at end of file.
  Future<Uint8List> read(int fd, int offset, int length) async {
    await (_starting ??= _start());
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _requests!.send([id, fd, offset, length]);
    return completer.future;
  }

  Future<void> _start() async {
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final list = message as List;
      final completer = _pending.remove(list[0] as int);
      if (completer == null) return;
      final payload = list[1];
      if (payload is TransferableTypedData) {
        completer.complete(payload.materialize().asUint8List());
      } else {
        completer.completeError(FileSystemException(payload as String));
      }
    });
    _isolate = await Isolate.spawn(_readerMain, replies.sendPort,
        debugName: 'fd-reader', errorsAreFatal: false);
    _requests = await ready.future;
  }
}

/// Entry point of the reader isolate.
void _readerMain(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  final libc = _Libc.instance;
  var buffer = calloc<Uint8>(FdSharedFile.chunkSize);
  var capacity = FdSharedFile.chunkSize;

  requests.listen((message) {
    final m = message as List;
    final id = m[0] as int;
    final fd = m[1] as int;
    final offset = m[2] as int;
    final length = m[3] as int;
    if (length > capacity) {
      calloc.free(buffer);
      buffer = calloc<Uint8>(length);
      capacity = length;
    }
    var filled = 0;
    var failures = 0;
    while (filled < length) {
      final n = libc.pread(
          fd, buffer + filled, length - filled, offset + filled);
      if (n > 0) {
        filled += n;
      } else if (n == 0) {
        break; // End of file.
      } else if (++failures > 3) {
        // -1: retry a few times in case of EINTR, then give up.
        replies.send([id, 'pread failed on descriptor $fd at $offset']);
        return;
      }
    }
    // fromList copies the bytes out of the native buffer.
    replies.send(
        [id, TransferableTypedData.fromList([buffer.asTypedList(filled)])]);
  });
}

/// The few libc functions we need. Android and Linux use the explicit 64-bit
/// variants so offsets above 2 GiB work on 32-bit ABIs too.
final class _Libc {
  _Libc._(DynamicLibrary lib)
      : pread = lib.lookupFunction<
            IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
            int Function(int, Pointer<Uint8>, int, int)>(
          Platform.isAndroid || Platform.isLinux ? 'pread64' : 'pread',
        ),
        close = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
            'close');

  static final _Libc instance = _Libc._(Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process());

  final int Function(int fd, Pointer<Uint8> buf, int count, int offset) pread;
  final int Function(int fd) close;
}
