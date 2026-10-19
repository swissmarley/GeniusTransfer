import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transfer_server/transfer_server.dart';

import '../platform/host_platform.dart';

/// A private copy of a picked file that is deleted when released.
///
/// iOS pickers always hand us copies in the app's temporary folder (the
/// photo library has no plain files); on Android this is the fallback for
/// sources that cannot seek, such as cloud files.
class TempSharedFile implements SharedFile {
  TempSharedFile(this._inner);

  static Future<TempSharedFile> fromPath(String path, {String? name}) async =>
      TempSharedFile(await LocalSharedFile.fromPath(path, name: name));

  final LocalSharedFile _inner;

  File get file => _inner.file;

  @override
  String get name => _inner.name;
  @override
  int get length => _inner.length;
  @override
  DateTime? get lastModified => _inner.lastModified;
  @override
  Stream<List<int>> openRead(int start, int end) => _inner.openRead(start, end);

  @override
  Future<void> close() async {
    try {
      await _inner.file.delete();
    } on FileSystemException {
      // Already gone; nothing to release.
    }
  }
}

/// The files chosen for one sharing session.
///
/// The selection owns its files until [takeAll] hands them to the server;
/// [discard] releases them (closes descriptors, deletes copies).
class Selection extends ChangeNotifier {
  Selection(this._platform);

  final HostPlatform _platform;
  final _files = <SharedFile>[];
  bool _busy = false;

  List<SharedFile> get files => List.unmodifiable(_files);
  bool get isEmpty => _files.isEmpty;
  int get totalBytes => _files.fold(0, (sum, f) => sum + f.length);

  /// True while a picker is open or picked files are being prepared.
  bool get busy => _busy;

  /// Lets the user pick photos and videos. Originals are kept: HEIC stays
  /// HEIC, HEVC stays HEVC.
  Future<void> pickMedia() => _pick(() async {
        if (Platform.isAndroid) return _fromAndroid(await _platform.pickMedia());
        final picked = await FilePicker.pickFiles(
          type: FileType.media,
          darwinOptions: const DarwinOptions(
              assetRepresentationMode: DarwinAssetRepresentationMode.current),
        );
        return _fromPaths(picked);
      });

  /// Lets the user pick any files.
  Future<void> pickFiles() => _pick(() async {
        if (Platform.isAndroid) {
          return _fromAndroid(await _platform.pickDocuments());
        }
        return _fromPaths(await FilePicker.pickFiles(type: FileType.any));
      });

  Future<void> _pick(Future<List<SharedFile>> Function() pick) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      _files.addAll(await pick());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// iOS pickers hand over private copies, released by deleting them.
  /// Desktop pickers hand over the user's original files, which must never
  /// be deleted.
  Future<List<SharedFile>> _fromPaths(List<PlatformFile> picked) async => [
        for (final p in picked)
          if (p.path != null)
            Platform.isIOS
                ? await TempSharedFile.fromPath(p.path!, name: p.name)
                : await LocalSharedFile.fromPath(p.path!, name: p.name),
      ];

  List<SharedFile> _fromAndroid(List<AndroidPickedFile> picked) => [
        for (final p in picked)
          if (p.fd != null)
            FdSharedFile(p.fd!,
                name: p.name, length: p.length, lastModified: p.lastModified)
          else
            TempSharedFile(LocalSharedFile(File(p.path!),
                name: p.name, length: p.length, lastModified: p.lastModified)),
      ];

  /// Adds files another app shared with us (Android).
  void addShared(List<AndroidPickedFile> picked) {
    if (picked.isEmpty) return;
    _files.addAll(_fromAndroid(picked));
    notifyListeners();
  }

  /// Removes one file and releases it.
  Future<void> removeAt(int index) async {
    final file = _files.removeAt(index);
    notifyListeners();
    await file.close();
  }

  /// Hands every file to the caller (the session), which must release them.
  List<SharedFile> takeAll() {
    final taken = List.of(_files);
    _files.clear();
    notifyListeners();
    return taken;
  }

  /// Releases every file without sharing it.
  Future<void> discard() async {
    for (final file in takeAll()) {
      await file.close();
    }
    await cleanUpTemporaryFiles(_platform);
  }
}

/// iOS and macOS hosts: a JPEG copy of a HEIC photo, for guests whose
/// devices may not open HEIC. Made in the temporary folder and deleted when
/// the session releases it. Null if the photo cannot be converted.
Future<SharedFile?> makeJpegCopy(HostPlatform platform, SharedFile heic) async {
  final source = switch (heic) {
    TempSharedFile(:final file) => file.path,
    LocalSharedFile(:final file) => file.path,
    _ => null,
  };
  if (source == null) return null;
  final dir = await Directory(
          '${(await getTemporaryDirectory()).path}/jpeg')
      .createTemp();
  final name = jpegName(heic.name);
  final target = '${dir.path}/$name';
  if (!await platform.convertToJpeg(source, target)) {
    await dir.delete(recursive: true);
    return null;
  }
  return TempSharedFile.fromPath(target, name: name);
}

/// Deletes leftovers from earlier sessions (e.g. after a crash).
Future<void> cleanUpTemporaryFiles(HostPlatform platform) async {
  try {
    if (Platform.isIOS) await FilePicker.clearTemporaryFiles();
    await platform.clearPickerCopies();
  } catch (e) {
    debugPrint('Temporary file clean-up failed: $e');
  }
}
