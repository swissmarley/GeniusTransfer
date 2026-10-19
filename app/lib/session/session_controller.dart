import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:transfer_server/transfer_server.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import 'selection.dart';

/// True in builds made with `--dart-define=GT_SELFTEST=true`: the app shares
/// generated test files on launch and logs the session URL, so a device can
/// be checked end to end from the Mac without touching it.
const kSelfTest = bool.fromEnvironment('GT_SELFTEST');

enum SessionPhase { starting, active, noNetwork, stopped }

enum StopReason { user, idle, notification, failed }

/// Download progress of one shared file, as the guest sees it.
class FileProgress {
  FileProgress(this.length);

  final int length;

  /// Bytes delivered from the start of the file without gaps (so a video
  /// player probing the end of a file does not count as "downloaded").
  int bytes = 0;
  bool done = false;
  int activeDownloads = 0;

  double get fraction =>
      length == 0 ? (done ? 1 : 0) : (bytes / length).clamp(0.0, 1.0);
}

/// Runs one sharing session: the server, its address, the screen wake lock,
/// the Android foreground service and the iOS background handling.
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController({
    required List<SharedFile> files,
    required this.platform,
    required this.notificationTitle,
    required this.notificationText,
    required this.notificationStop,
  })  : server = TransferServer(files: files),
        progress = [for (final f in files) FileProgress(f.length)];

  final TransferServer server;
  final HostPlatform platform;
  final String notificationTitle;
  final String notificationText;
  final String notificationStop;

  /// One entry per shared file, same order as [files].
  final List<FileProgress> progress;

  /// Guests seen so far, by IP address.
  final guests = <String, GuestDevice>{};

  SessionPhase phase = SessionPhase.starting;
  StopReason? stopReason;
  String? error;

  /// Every LAN address the server listens on, best first.
  List<LanAddress> addresses = const [];

  /// The address in the QR code. The user can switch when the device is on
  /// several networks (e.g. Wi-Fi and a cable, or Wi-Fi and a hotspot).
  LanAddress? shown;

  /// The guest URL for [shown], as put in the QR code.
  Uri? get url => shown == null || server.port == null
      ? null
      : server.urlFor(shown!.address);

  /// The same URL in a form that is easier to type on a computer:
  /// `http://192.168.1.23:8080/K7QX-ABCD-…-YZ/`.
  String? get typeableUrl => shown == null || server.port == null
      ? null
      : 'http://${shown!.address.address}:${server.port}/'
          '${groupToken(server.token)}/';

  /// When the code was first shown (for the "not opening?" help).
  DateTime? activeSince;

  /// The server was suspended in the background and is listening again.
  bool resumedAfterBackground = false;

  final _downloads = <int, DownloadStarted>{};
  final _sent = <int, int>{};
  int? _lastDownloadId;
  Timer? _addressTimer;
  StreamSubscription<ServerEvent>? _events;
  bool _inBackground = false;
  bool _checkingAddress = false;

  List<SharedFile> get files => server.files;

  /// The download shown in the status line: the most recent active one.
  ({String name, double fraction})? get currentDownload {
    final id = _lastDownloadId;
    final d = id == null ? null : _downloads[id];
    if (d == null) return null;
    final file = files[d.fileIndex];
    final at = d.start + (_sent[id] ?? 0);
    return (
      name: file.name,
      fraction: file.length == 0 ? 1.0 : (at / file.length).clamp(0.0, 1.0),
    );
  }

  int get doneCount => progress.where((p) => p.done).length;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    platform
      ..onStopRequested = (() => stop(StopReason.notification))
      ..onBackgroundTimeExpired = _onBackgroundTimeExpired;
    _events = server.events.listen(_onEvent);
    try {
      await WakelockPlus.enable();
      await platform.startSessionService(
          title: notificationTitle,
          text: notificationText,
          stop: notificationStop);
      final found = await findLanAddresses();
      if (found.isEmpty) {
        phase = SessionPhase.noNetwork;
      } else {
        await _listenOn(found);
      }
      _addressTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _checkAddress());
    } catch (e) {
      error = '$e';
      await stop(StopReason.failed);
      return;
    }
    notifyListeners();
  }

  Future<void> _listenOn(List<LanAddress> found) async {
    await server.start([for (final a in found) a.address]);
    addresses = found;
    if (shown == null || !found.contains(shown)) shown = found.first;
    phase = SessionPhase.active;
    activeSince ??= DateTime.now();
    if (kSelfTest) debugPrint('GT_SELFTEST_URL=$url');
  }

  /// Puts [address] in the QR code instead.
  void show(LanAddress address) {
    if (!addresses.contains(address)) return;
    shown = address;
    notifyListeners();
  }

  /// Follows Wi-Fi changes: a new address means a new QR code (same token,
  /// same port when possible); no address means "reconnect to Wi-Fi".
  Future<void> _checkAddress() async {
    if (phase == SessionPhase.stopped || _inBackground || _checkingAddress) {
      return;
    }
    _checkingAddress = true;
    try {
      final found = await findLanAddresses();
      if (phase == SessionPhase.stopped || _inBackground) return;
      if (found.isEmpty) {
        if (phase == SessionPhase.active) {
          await server.suspend();
          phase = SessionPhase.noNetwork;
          notifyListeners();
        }
      } else if (phase == SessionPhase.noNetwork ||
          !listEquals(found, addresses)) {
        await _listenOn(found);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Address check failed: $e');
    } finally {
      _checkingAddress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android keeps serving thanks to the foreground service.
    if (!Platform.isIOS || phase == SessionPhase.stopped) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_enterBackground());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_enterForeground());
    }
  }

  /// iOS suspends apps in the background, and with them the listening
  /// socket. Stop accepting now, and use the extra background time (about
  /// 30 seconds) to let downloads in progress finish.
  Future<void> _enterBackground() async {
    if (_inBackground) return;
    _inBackground = true;
    await platform.beginBackgroundTask();
    await server.suspend();
    if (server.activeDownloads == 0) await platform.endBackgroundTask();
  }

  void _onBackgroundTimeExpired() {
    unawaited(server.dropConnections());
  }

  Future<void> _enterForeground() async {
    if (!_inBackground) return;
    _inBackground = false;
    await platform.endBackgroundTask();
    if (phase == SessionPhase.stopped) return;
    try {
      final found = await findLanAddresses();
      if (found.isEmpty) {
        phase = SessionPhase.noNetwork;
      } else {
        await _listenOn(found);
        resumedAfterBackground = true;
      }
    } catch (e) {
      debugPrint('Resume failed: $e');
    }
    notifyListeners();
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case GuestConnected(:final address, :final device):
        guests[address] = device;
      case DownloadStarted():
        _downloads[event.id] = event;
        _sent[event.id] = 0;
        _lastDownloadId = event.id;
        progress[event.fileIndex].activeDownloads++;
      case DownloadProgress():
        _sent[event.id] = event.sent;
        _advance(event.id, event.sent, completed: false);
      case DownloadEnded():
        _advance(event.id, event.sent, completed: event.completed);
        _downloads.remove(event.id);
        _sent.remove(event.id);
        final p = progress[event.fileIndex];
        p.activeDownloads = max(0, p.activeDownloads - 1);
        if (_lastDownloadId == event.id) {
          _lastDownloadId = _downloads.keys.isEmpty ? null : _downloads.keys.last;
        }
        if (_inBackground && server.activeDownloads == 0) {
          unawaited(platform.endBackgroundTask());
        }
      case SessionIdle():
        unawaited(stop(StopReason.idle));
        return;
      // Receiving is not wired up in the app yet (M2b).
      case UploadOffered() ||
            UploadOfferExpired() ||
            UploadProgress() ||
            UploadFileReceived() ||
            UploadFileFailed() ||
            UploadBatchFinished():
        return;
    }
    notifyListeners();
  }

  void _advance(int id, int sent, {required bool completed}) {
    final d = _downloads[id];
    if (d == null) return;
    final p = progress[d.fileIndex];
    if (d.start <= p.bytes) p.bytes = max(p.bytes, d.start + sent);
    if (completed && p.bytes >= p.length) p.done = true;
  }

  /// Ends the session: closes the server and every connection, releases the
  /// files and the wake lock, stops the foreground service.
  Future<void> stop(StopReason reason) async {
    if (phase == SessionPhase.stopped) return;
    phase = SessionPhase.stopped;
    stopReason = reason;
    notifyListeners();
    _addressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    platform
      ..onStopRequested = null
      ..onBackgroundTimeExpired = null;
    await _events?.cancel();
    await server.stop();
    await platform.stopSessionService();
    await platform.endBackgroundTask();
    await WakelockPlus.disable();
    await cleanUpTemporaryFiles(platform);
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    // Clean-up in stop() and late lifecycle callbacks can outlive the screen.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop(StopReason.user));
    _disposed = true;
    super.dispose();
  }
}
