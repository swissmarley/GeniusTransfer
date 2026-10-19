import 'dart:io';

/// A file the host shares in a session.
///
/// Implementations stream bytes from disk: nothing ever loads a whole file
/// into memory, so multi-GB files are fine.
abstract interface class SharedFile {
  /// The name shown to the guest and suggested for the saved file. Only used
  /// for display and headers, never as a path on the host.
  String get name;

  /// Size in bytes.
  int get length;

  /// Last modification time, if known (used for `Last-Modified` / `ETag`).
  DateTime? get lastModified;

  /// Streams bytes [start, end) (end exclusive).
  Stream<List<int>> openRead(int start, int end);

  /// Releases resources held for this file, such as an open descriptor.
  Future<void> close();
}

/// A shared file that is a regular file on the host's file system.
class LocalSharedFile implements SharedFile {
  LocalSharedFile(this.file,
      {required this.name, required this.length, this.lastModified});

  /// Builds a [LocalSharedFile] from [path], reading size and modification
  /// time from the file system. [name] defaults to the path's last segment.
  static Future<LocalSharedFile> fromPath(String path, {String? name}) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Not a regular file', path);
    }
    return LocalSharedFile(file,
        name: name ?? file.uri.pathSegments.last,
        length: stat.size,
        lastModified: stat.modified);
  }

  final File file;
  @override
  final String name;
  @override
  final int length;
  @override
  final DateTime? lastModified;

  @override
  Stream<List<int>> openRead(int start, int end) => file.openRead(start, end);

  @override
  Future<void> close() async {}
}
