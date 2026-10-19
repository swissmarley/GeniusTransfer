import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transfer_server/transfer_server.dart';

import '../platform/host_platform.dart';
import 'save_settings.dart';

/// Where a received file ended up.
enum SavedIn {
  /// iOS: Files › On My iPhone › GeniusTransfer › Received.
  iosReceived,

  /// A folder described by [ReceivedFile.location].
  folder,
}

/// A file a guest sent, now in its final place.
class ReceivedFile {
  ReceivedFile({
    required this.name,
    required this.size,
    required this.mime,
    required this.savedIn,
    required this.location,
    this.path,
    this.uri,
  });

  final String name;
  final int size;
  final String mime;
  final SavedIn savedIn;

  /// The folder, for people: "Pictures/GeniusTransfer", "~/Downloads/…".
  final String location;

  /// The file on disk, when there is a path we can use (not on Android).
  final String? path;

  /// Android: the content URI.
  final String? uri;

  /// iOS: added to the Photos library.
  bool savedToPhotos = false;

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
}

/// Moves received files from the server's staging folder to where the user
/// expects them, honouring the chosen save folder.
class Delivery {
  Delivery({required this.platform, required this.settings});

  final HostPlatform platform;
  final SaveSettings settings;

  /// Set when the chosen folder could not be used and a file went to the
  /// default folder instead.
  bool fellBack = false;

  /// Moves [staged] (named [name] by the server) to its final place.
  Future<ReceivedFile> deliver(File staged, String name) async {
    final size = await staged.length();
    final mime = lookupMimeType(name) ?? 'application/octet-stream';
    final folder = settings.folder;
    if (folder != null) {
      try {
        return await _toChosenFolder(staged, name, size, mime, folder);
      } on FolderUnavailableException catch (e) {
        debugPrint('Save folder unavailable, using the default: $e');
        fellBack = true;
      }
    }
    return _toDefault(staged, name, size, mime);
  }

  Future<ReceivedFile> _toChosenFolder(File staged, String name, int size,
      String mime, SaveFolder folder) async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final done = await platform.deliverFile(
          source: staged.path, name: name, mime: mime, folderId: folder.id);
      final refreshed = done.refreshedFolderId;
      if (refreshed != null) await settings.refreshFolderId(refreshed);
      return ReceivedFile(
        name: done.name,
        size: size,
        mime: mime,
        savedIn: SavedIn.folder,
        location: done.location,
        path: Platform.isAndroid ? null : done.uri,
        uri: Platform.isAndroid ? done.uri : null,
      );
    }
    final dir = Directory(folder.id);
    if (!await dir.exists()) {
      throw FolderUnavailableException('${folder.id} does not exist.');
    }
    final file = await _moveInto(staged, dir, name);
    return ReceivedFile(
      name: _baseName(file.path),
      size: size,
      mime: mime,
      savedIn: SavedIn.folder,
      location: folder.name,
      path: file.path,
    );
  }

  Future<ReceivedFile> _toDefault(
      File staged, String name, int size, String mime) async {
    if (Platform.isAndroid) {
      final done = await platform.deliverFile(
          source: staged.path, name: name, mime: mime);
      return ReceivedFile(
        name: done.name,
        size: size,
        mime: mime,
        savedIn: SavedIn.folder,
        location: done.location,
        uri: done.uri,
      );
    }
    final dir = await defaultFolder();
    await dir.create(recursive: true);
    final file = await _moveInto(staged, dir, name);
    return ReceivedFile(
      name: _baseName(file.path),
      size: size,
      mime: mime,
      savedIn: Platform.isIOS ? SavedIn.iosReceived : SavedIn.folder,
      location: Platform.isIOS ? 'Received' : await describeDefaultFolder(),
      path: file.path,
    );
  }

  /// The default folder on iOS and computers. (Android uses MediaStore.)
  static Future<Directory> defaultFolder() async {
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.path}/Received');
    }
    final downloads = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(
        '${downloads.path}${Platform.pathSeparator}GeniusTransfer');
  }

  /// The default folder on a computer, as people know it: on macOS the app
  /// sees Downloads through its sandbox container, so resolve that link and
  /// abbreviate the home folder.
  static Future<String> describeDefaultFolder() async {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) return (await defaultFolder()).path;
    var path = downloads.path;
    try {
      path = await downloads.resolveSymbolicLinks();
    } on FileSystemException {
      // Keep the unresolved path.
    }
    final sep = Platform.pathSeparator;
    if (Platform.isMacOS) {
      final home = Directory(path).parent.path;
      if (path.startsWith('/Users/')) path = '~${path.substring(home.length)}';
    }
    return '$path${sep}GeniusTransfer';
  }

  /// Moves [source] into [dir] under a name that is not taken yet. Uses a
  /// rename when both are on the same volume, else copies.
  static Future<File> _moveInto(File source, Directory dir, String name) async {
    final unique = uniqueName(dir, name, <String>{});
    final target = '${dir.path}${Platform.pathSeparator}$unique';
    try {
      return await source.rename(target);
    } on FileSystemException {
      final partial = File(target);
      try {
        await source.copy(target);
      } catch (_) {
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
      await source.delete();
      return partial;
    }
  }

  static String _baseName(String path) =>
      path.split(Platform.isWindows ? RegExp(r'[\\/]') : RegExp('/')).last;
}

/// Where a receiving session writes uploads before they are accepted and
/// moved: private to the app, and emptied at the start and end of each
/// session.
Future<Directory> receiveStagingDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}incoming');
}
