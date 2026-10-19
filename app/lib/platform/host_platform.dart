import 'dart:io';

import 'package:flutter/services.dart';

/// A file the Android picker or share sheet handed us, already opened.
///
/// Either [fd] is a seekable descriptor (served without copying) or [path]
/// is a private copy, made when the source could not seek (cloud files).
class AndroidPickedFile {
  AndroidPickedFile.fromMap(Map<Object?, Object?> m)
      : name = m['name'] as String,
        length = m['size'] as int,
        lastModified = (m['modified'] as int?) == null || m['modified'] == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['modified'] as int),
        fd = m['fd'] as int?,
        path = m['path'] as String?;

  final String name;
  final int length;
  final DateTime? lastModified;
  final int? fd;
  final String? path;
}

/// A folder the user chose for received files. [id] is opaque: an Android
/// tree URI, a base64 bookmark on iOS and macOS, a plain path on Windows.
class SaveFolder {
  const SaveFolder({required this.id, required this.name});

  final String id;

  /// What to show the user: "Download", "~/Documents/Inbox"…
  final String name;
}

/// Where the native side put a received file.
class NativeDelivery {
  NativeDelivery.fromMap(Map<Object?, Object?> m)
      : name = m['name'] as String,
        location = m['location'] as String,
        uri = m['uri'] as String?,
        refreshedFolderId = m['folder'] as String?;

  /// The final file name (after de-duplication).
  final String name;

  /// The folder, for people: "Pictures/GeniusTransfer".
  final String location;

  /// A content URI (Android) or an absolute path.
  final String? uri;

  /// A fresh bookmark when the stored one was stale (iOS, macOS).
  final String? refreshedFolderId;
}

/// The chosen save folder can no longer be used (deleted, permission
/// revoked, unplugged).
class FolderUnavailableException implements Exception {
  const FolderUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A Wi-Fi network this phone created for the guest to join.
class HotspotInfo {
  const HotspotInfo({required this.ssid, required this.password});

  final String ssid;

  /// Null for an open network.
  final String? password;
}

/// Why the hotspot could not be started.
enum HotspotFailure {
  /// The user refused the permission it needs.
  permission,

  /// Android 8–12: Location is off, and the system requires it.
  locationOff,

  /// The phone's own hotspot or tethering is on.
  tetheringOn,

  /// Anything else (no channel available, not allowed, Wi-Fi problem).
  failed,
}

class HotspotException implements Exception {
  const HotspotException(this.failure, [this.message]);
  final HotspotFailure failure;
  final String? message;

  @override
  String toString() => 'HotspotException(${failure.name}, $message)';
}

/// The native side of the app: our own small Kotlin and Swift code.
class HostPlatform {
  HostPlatform() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'stopRequested':
          onStopRequested?.call();
        case 'backgroundTimeExpired':
          onBackgroundTimeExpired?.call();
        case 'hotspotStopped':
          onHotspotStopped?.call();
        case 'sharedFilesAvailable':
          onSharedFilesAvailable?.call();
      }
    });
  }

  static const _channel = MethodChannel('geniustransfer/host');

  /// Android: the user tapped "Stop" in the sharing notification.
  void Function()? onStopRequested;

  /// iOS: the extra background time is about to run out.
  void Function()? onBackgroundTimeExpired;

  /// Android: the system turned our hotspot off.
  void Function()? onHotspotStopped;

  /// Android: another app shared files with us ("Share › GeniusTransfer");
  /// fetch them with [takeSharedFiles].
  void Function()? onSharedFilesAvailable;

  /// Android: opens the system photo picker (photos and videos).
  Future<List<AndroidPickedFile>> pickMedia() => _pick('pickMedia');

  /// Android: opens the system file picker (any type).
  Future<List<AndroidPickedFile>> pickDocuments() => _pick('pickDocuments');

  /// Android: files shared with us by another app since the last call,
  /// already opened. Empty elsewhere.
  Future<List<AndroidPickedFile>> takeSharedFiles() async =>
      Platform.isAndroid ? _pick('takeSharedFiles') : const [];

  Future<List<AndroidPickedFile>> _pick(String method) async {
    final list = await _channel.invokeListMethod<Object?>(method) ?? const [];
    return [
      for (final item in list)
        AndroidPickedFile.fromMap(item! as Map<Object?, Object?>),
    ];
  }

  /// Android 13+: asks once for permission to show the sharing
  /// notification (with its Stop button). Sharing works without it.
  Future<void> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    }
  }

  /// Android: deletes private copies made by the pickers.
  Future<void> clearPickerCopies() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('clearCopies');
  }

  /// Android: starts the foreground service that keeps the server alive
  /// while the user switches apps, with a notification offering "Stop".
  Future<void> startSessionService(
      {required String title, required String text, required String stop}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>(
        'startSession', {'title': title, 'text': text, 'stop': stop});
  }

  Future<void> stopSessionService() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopSession');
  }

  /// Free bytes on the volume holding [path], or null where unknown
  /// (Windows, or if the platform cannot tell).
  Future<int?> freeBytes(String path) async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return null;
    }
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } catch (_) {
      // Unknown is acceptable: the upload limit still applies.
      return null;
    }
  }

  /// Android, iOS, macOS: lets the user choose a folder for received files.
  /// Null if cancelled.
  Future<SaveFolder?> pickFolder() async {
    final m = await _channel.invokeMapMethod<Object?, Object?>('pickFolder');
    if (m == null) return null;
    return SaveFolder(id: m['id'] as String, name: m['name'] as String);
  }

  /// Moves the received file at [source] to its final place: the default
  /// place on Android (Pictures, Movies or Download › GeniusTransfer), or
  /// the chosen [folderId] (Android, iOS, macOS). Throws
  /// [FolderUnavailableException] if that folder cannot be used.
  Future<NativeDelivery> deliverFile({
    required String source,
    required String name,
    required String mime,
    String? folderId,
  }) async {
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>('deliverFile', {
        'source': source,
        'name': name,
        'mime': mime,
        'folder': folderId,
      });
      return NativeDelivery.fromMap(m!);
    } on PlatformException catch (e) {
      if (e.code == 'folder_unavailable') {
        throw FolderUnavailableException(e.message ?? e.code);
      }
      rethrow;
    }
  }

  /// Android 8 and 9: asks for permission to write to shared storage, so
  /// received files can go to Pictures, Movies and Download.
  Future<void> requestStoragePermission() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('requestStoragePermission');
    }
  }

  /// iOS: adds a received photo or video to the Photos library, unchanged.
  /// Returns false if the user refused access.
  Future<bool> saveToPhotos(String path, {required bool video}) async {
    try {
      return await _channel.invokeMethod<bool>(
              'saveToPhotos', {'path': path, 'video': video}) ??
          false;
    } on PlatformException catch (e) {
      if (e.code == 'denied') return false;
      rethrow;
    }
  }

  /// macOS: shows [path] selected in a Finder window.
  Future<void> revealInFinder(String path) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('revealInFinder', {'path': path});
    }
  }

  /// Android: whether this phone can create a hotspot for the guest
  /// (Android 8 and later can; other platforms cannot).
  bool get canStartHotspot => Platform.isAndroid;

  /// Android: creates a local-only hotspot (no internet sharing) and returns
  /// its name and password. Asks for the permission it needs first. Throws
  /// [HotspotException].
  Future<HotspotInfo> startHotspot() async {
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>('startHotspot');
      return HotspotInfo(
          ssid: m!['ssid'] as String, password: m['password'] as String?);
    } on PlatformException catch (e) {
      throw HotspotException(
        switch (e.code) {
          'permission' => HotspotFailure.permission,
          'location_off' => HotspotFailure.locationOff,
          'tethering_on' => HotspotFailure.tetheringOn,
          _ => HotspotFailure.failed,
        },
        e.message,
      );
    }
  }

  /// Android: turns the hotspot off again.
  Future<void> stopHotspot() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopHotspot');
  }

  /// Android: opens the system Location settings.
  Future<void> openLocationSettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openLocationSettings');
    }
  }

  /// iOS: asks for extra time after the app leaves the foreground, so a
  /// download in progress can finish.
  Future<void> beginBackgroundTask() async {
    if (Platform.isIOS) await _channel.invokeMethod<void>('beginBackgroundTask');
  }

  Future<void> endBackgroundTask() async {
    if (Platform.isIOS) await _channel.invokeMethod<void>('endBackgroundTask');
  }
}
