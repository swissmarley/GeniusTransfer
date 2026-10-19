import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:transfer_server/transfer_server.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import '../receive/delivery.dart';
import 'selection.dart';

/// True in builds made with `--dart-define=GT_SELFTEST=true`: the app shares
/// generated test files on launch and logs the session URL, so a device can
/// be checked end to end from the Mac without touching it.
const kSelfTest = bool.fromEnvironment('GT_SELFTEST');

/// With [kSelfTest]: `send` (default) shares test files; `receive` starts a
/// receiving session that accepts every offer and checks what arrives.
const kSelfTestMode = String.fromEnvironment('GT_SELFTEST_MODE');

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

/// One group of files a guest is sending, after the host accepted it.
class IncomingBatch {
  IncomingBatch(this.offer)
      : received = List.filled(offer.files.length, 0),
        done = List.filled(offer.files.length, false);

  final UploadOffered offer;

  /// Bytes received so far, per file.
  final List<int> received;
  final List<bool> done;
  bool finished = false;
}

/// Runs one session: the server, its address, the screen wake lock, the
/// Android foreground service and the iOS background handling. Sends the
/// given files, or receives files the guest chooses.
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  /// Shares [files]: the guest downloads them.
  SessionController.send({
    required List<SharedFile> files,
    String? pin,
    required this.platform,
    required this.notificationTitle,
    required this.notificationText,
    required this.notificationStop,
  })  : mode = SessionMode.send,
        server = TransferServer(
          files: files,
          pin: pin,
          // Apple hosts can turn HEIC photos into JPEG for other guests.
          jpegCopy: Platform.isIOS || Platform.isMacOS
              ? (heic) => makeJpegCopy(platform, heic)
              : null,
        ),
        progress = [for (final f in files) FileProgress(f.length)],
        delivery = null,
        stagingDir = null;

  /// Receives files: the guest uploads them into [stagingDir], and the host
  /// accepts each batch. [delivery] moves them to their final place.
  SessionController.receive({
    required Directory this.stagingDir,
    String? pin,
    required Delivery this.delivery,
    required this.platform,
    required this.notificationTitle,
    required this.notificationText,
    required this.notificationStop,
  })  : mode = SessionMode.receive,
        server = TransferServer(
          mode: SessionMode.receive,
          pin: pin,
          receiveOptions: ReceiveOptions(
            stagingDir: stagingDir,
            freeBytes: () => platform.freeBytes(stagingDir.path),
          ),
        ),
        progress = const [];

  final SessionMode mode;
  final TransferServer server;
  final Delivery? delivery;
  final Directory? stagingDir;
  final HostPlatform platform;
  final String notificationTitle;
  final String notificationText;
  final String notificationStop;

  /// One entry per shared file, same order as [files].
  final List<FileProgress> progress;

  /// Receive mode: the offer waiting for the host to accept or decline.
  UploadOffered? pendingOffer;

  /// Receive mode: an offer expired before anyone answered it (shown once).
  bool offerExpired = false;

  /// Receive mode: accepted batches, by id.
  final batches = <String, IncomingBatch>{};

  /// Receive mode: files in their final place, newest first.
  final received = <ReceivedFile>[];

  /// Receive mode: files that arrived but could not be saved, with why.
  final deliveryErrors = <String>[];

  /// Receive mode: the latest batch that finished, for a short message.
  IncomingBatch? lastFinished;

  /// The PIN guests must type, if the user asked for one.
  String? get pin => server.pin;

  /// Wrong PINs typed by guests so far, and whether that locked the session.
  int wrongPins = 0;
  bool pinLockedOut = false;

  /// Android: the Wi-Fi network this phone created, while it is on.
  HotspotInfo? hotspot;

  /// Which code to show while the hotspot is on: 1 = join the Wi-Fi,
  /// 2 = open the page.
  int hotspotStep = 1;
  bool startingHotspot = false;

  /// Why the last attempt to start the hotspot failed.
  HotspotFailure? hotspotFailure;

  /// The system turned the hotspot off (shown once).
  bool hotspotLost = false;

  /// The hotspot's own address on this phone, once its interface is up.
  LanAddress? _hotspotAddress;

  Future<void> _deliveries = Future.value();
  int _pendingDeliveries = 0;
  String? _uploadBatch;
  int? _uploadIndex;

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

  /// Receive mode: the upload shown in the status line.
  ({String name, double fraction})? get currentUpload {
    final batch = batches[_uploadBatch];
    final i = _uploadIndex;
    if (batch == null || i == null || batch.done[i]) return null;
    final file = batch.offer.files[i];
    return (
      name: file.name,
      fraction:
          file.size == 0 ? 1.0 : (batch.received[i] / file.size).clamp(0.0, 1.0),
    );
  }

  /// Receive mode: accepts [pendingOffer]; the guest starts sending.
  Future<void> acceptOffer() async {
    final offer = pendingOffer;
    if (offer == null) return;
    pendingOffer = null;
    // Quarantined files are moved in during approval, with events, so the
    // batch must exist first.
    batches[offer.id] = IncomingBatch(offer);
    notifyListeners();
    if (!await server.approveUpload(offer.id)) {
      batches.remove(offer.id);
      offerExpired = true;
    }
    notifyListeners();
  }

  /// Receive mode: refuses [pendingOffer].
  Future<void> declineOffer() async {
    final offer = pendingOffer;
    if (offer == null) return;
    pendingOffer = null;
    notifyListeners();
    await server.declineUpload(offer.id);
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final staging = stagingDir;
    if (staging != null) {
      // Leftovers from a session that did not end cleanly.
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      await platform.requestStoragePermission();
    }
    platform
      ..onStopRequested = (() => stop(StopReason.notification))
      ..onBackgroundTimeExpired = _onBackgroundTimeExpired
      ..onHotspotStopped = _onHotspotStopped;
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
    if (hotspot != null && _hotspotAddress == null) {
      _hotspotAddress =
          found.where((a) => a.kind == LanKind.hotspot).firstOrNull;
    }
    final hotspotAddress = _hotspotAddress;
    if (hotspotAddress != null && found.contains(hotspotAddress)) {
      // The guest is joining our hotspot: that is the address it can reach.
      shown = hotspotAddress;
    } else if (shown == null || !found.contains(shown)) {
      shown = found.first;
    }
    phase = SessionPhase.active;
    activeSince ??= DateTime.now();
    if (kSelfTest) debugPrint('GT_SELFTEST_URL=$url');
  }

  /// Android: creates a Wi-Fi network for the guest to join, for when the
  /// two devices share none. The code then shows in two steps: join the
  /// Wi-Fi, then open the page.
  Future<void> startHotspot() async {
    if (hotspot != null || startingHotspot || phase == SessionPhase.stopped) {
      return;
    }
    startingHotspot = true;
    hotspotFailure = null;
    hotspotLost = false;
    notifyListeners();
    try {
      final before = (await findLanAddresses()).toSet();
      try {
        hotspot = await platform.startHotspot();
      } on HotspotException catch (e) {
        debugPrint('Hotspot failed: $e');
        hotspotFailure = e.failure;
        return;
      }
      hotspotStep = 1;
      // Its interface takes a moment to get an address; the regular
      // address check would find it too, but only after a few seconds.
      for (var i = 0; i < 40; i++) {
        if (phase == SessionPhase.stopped || hotspot == null) return;
        final found = await findLanAddresses();
        final fresh = found.where((a) => !before.contains(a)).toList();
        if (fresh.isNotEmpty) {
          _hotspotAddress = fresh.firstWhere(
              (a) => a.kind == LanKind.hotspot,
              orElse: () => fresh.first);
          await _listenOn(found);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      debugPrint('Hotspot address not found: $e');
    } finally {
      startingHotspot = false;
      notifyListeners();
    }
  }

  /// Switches between the two codes shown while the hotspot is on.
  void showHotspotStep(int step) {
    hotspotStep = step;
    notifyListeners();
  }

  void _onHotspotStopped() {
    if (hotspot == null) return;
    hotspot = null;
    _hotspotAddress = null;
    hotspotLost = true;
    notifyListeners();
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
    if (server.activeDownloads == 0 &&
        server.activeUploads == 0 &&
        _pendingDeliveries == 0) {
      await platform.endBackgroundTask();
    }
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
        _endBackgroundTaskIfIdle();
      case SessionIdle():
        unawaited(stop(StopReason.idle));
        return;
      case UploadOffered():
        pendingOffer = event;
        offerExpired = false;
        if (kSelfTest) unawaited(acceptOffer());
      case UploadOfferExpired(:final id):
        if (pendingOffer?.id == id) {
          pendingOffer = null;
          offerExpired = true;
        }
      case UploadProgress(:final batchId, :final fileIndex, :final received):
        final batch = batches[batchId];
        if (batch == null) return;
        batch.received[fileIndex] = received;
        _uploadBatch = batchId;
        _uploadIndex = fileIndex;
      case UploadFileReceived(:final batchId, :final fileIndex):
        final batch = batches[batchId];
        if (batch != null) {
          batch.done[fileIndex] = true;
          batch.received[fileIndex] = event.size;
        }
        _queueDelivery(event);
        _endBackgroundTaskIfIdle();
      case UploadFileFailed(:final batchId, :final fileIndex):
        batches[batchId]?.received[fileIndex] = 0;
        _endBackgroundTaskIfIdle();
      case PinRejected(:final attemptsLeft):
        wrongPins = maxPinAttempts - attemptsLeft;
      case PinLockedOut():
        pinLockedOut = true;
      case UploadBatchFinished(:final batchId):
        final batch = batches[batchId];
        if (batch != null) {
          batch.finished = true;
          lastFinished = batch;
        }
    }
    notifyListeners();
  }

  void _endBackgroundTaskIfIdle() {
    if (_inBackground &&
        server.activeDownloads == 0 &&
        server.activeUploads == 0 &&
        _pendingDeliveries == 0) {
      unawaited(platform.endBackgroundTask());
    }
  }

  /// Moves arrived files to their final place one at a time, so names are
  /// chosen without races.
  void _queueDelivery(UploadFileReceived event) {
    final delivery = this.delivery;
    if (delivery == null) return;
    _pendingDeliveries++;
    _deliveries = _deliveries.then((_) async {
      try {
        if (kSelfTest) await _selfTestCheck(event);
        final file = await delivery.deliver(event.file, event.name);
        received.insert(0, file);
        if (kSelfTest) {
          debugPrint('GT_SELFTEST_SAVED=${file.name}|${file.size}|'
              '${file.location}|${file.path ?? file.uri}');
        }
      } catch (e) {
        debugPrint('Could not save ${event.name}: $e');
        deliveryErrors.add('${event.name}: $e');
      } finally {
        _pendingDeliveries--;
        _endBackgroundTaskIfIdle();
        notifyListeners();
      }
    });
  }

  /// Self-test only: the checker uploads files whose byte i is
  /// `(i * 31 + 7) & 0xff`; check that they arrived intact.
  Future<void> _selfTestCheck(UploadFileReceived event) async {
    var offset = 0;
    var ok = true;
    await for (final chunk in event.file.openRead()) {
      for (var i = 0; i < chunk.length && ok; i++) {
        if (chunk[i] != ((offset + i) * 31 + 7) & 0xff) ok = false;
      }
      offset += chunk.length;
    }
    debugPrint('GT_SELFTEST_RECEIVED=${event.name}|$offset|'
        '${ok && offset == event.size ? 'ok' : 'BAD'}');
  }

  void _advance(int id, int sent, {required bool completed}) {
    final d = _downloads[id];
    if (d == null) return;
    final p = progress[d.fileIndex];
    if (d.converted) {
      // A JPEG copy: its size differs from the original's.
      if (completed && d.start == 0) {
        p.done = true;
        p.bytes = p.length;
      }
      return;
    }
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
      ..onBackgroundTimeExpired = null
      ..onHotspotStopped = null;
    await _events?.cancel();
    await server.stop();
    if (hotspot != null) {
      hotspot = null;
      await platform.stopHotspot();
    }
    // Finish saving what arrived, then forget the staging folder.
    await _deliveries;
    final staging = stagingDir;
    if (staging != null) {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (e) {
        debugPrint('Could not delete the staging folder: $e');
      }
    }
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
