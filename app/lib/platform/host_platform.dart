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

/// The native side of the app: our own small Kotlin and Swift code.
class HostPlatform {
  HostPlatform() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'stopRequested':
          onStopRequested?.call();
        case 'backgroundTimeExpired':
          onBackgroundTimeExpired?.call();
      }
    });
  }

  static const _channel = MethodChannel('geniustransfer/host');

  /// Android: the user tapped "Stop" in the sharing notification.
  void Function()? onStopRequested;

  /// iOS: the extra background time is about to run out.
  void Function()? onBackgroundTimeExpired;

  /// Android: opens the system photo picker (photos and videos).
  Future<List<AndroidPickedFile>> pickMedia() => _pick('pickMedia');

  /// Android: opens the system file picker (any type).
  Future<List<AndroidPickedFile>> pickDocuments() => _pick('pickDocuments');

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

  /// iOS: asks for extra time after the app leaves the foreground, so a
  /// download in progress can finish.
  Future<void> beginBackgroundTask() async {
    if (Platform.isIOS) await _channel.invokeMethod<void>('beginBackgroundTask');
  }

  Future<void> endBackgroundTask() async {
    if (Platform.isIOS) await _channel.invokeMethod<void>('endBackgroundTask');
  }
}
