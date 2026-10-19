import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:transfer_server/transfer_server.dart';

import '../l10n/app_localizations.dart';
import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import '../receive/delivery.dart';
import '../settings.dart';
import '../session/session_controller.dart';
import '../net/wifi_qr.dart';
import 'format.dart';
import 'no_network_screen.dart';
import 'qr_code_view.dart';
import 'receive_panel.dart';
import 'send_screen.dart' show FileBadge;

/// The code to scan, live status, and Stop.
class SessionScreen extends StatefulWidget {
  /// Shares [files].
  const SessionScreen(
      {super.key,
      required this.files,
      required this.platform,
      this.requirePin = false,
      this.startHotspot = false})
      : settings = null,
        stagingDir = null;

  /// Receives files into [stagingDir], then saves them as [settings] say.
  const SessionScreen.receive({
    super.key,
    required this.platform,
    required AppSettings this.settings,
    required Directory this.stagingDir,
    this.requirePin = false,
    this.startHotspot = false,
  }) : files = const [];

  /// The files to share. The session owns and releases them.
  final List<SharedFile> files;
  final HostPlatform platform;
  final AppSettings? settings;
  final Directory? stagingDir;

  /// Android: start a hotspot right away (there is no network to share).
  final bool startHotspot;

  /// Guests must type a PIN, made up for this session and shown here.
  final bool requirePin;

  bool get receiving => settings != null;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionController? _controller;
  Timer? _helpTimer;
  bool _popped = false;
  String? _sheetOfferId;
  int _errorsShown = 0;

  /// Show the "not opening?" help if nobody has connected after this long.
  static const _helpDelay = Duration(seconds: 30);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final l = AppLocalizations.of(context);
    final settings = widget.settings;
    final pin = widget.requirePin
        ? Random.secure().nextInt(10000).toString().padLeft(4, '0')
        : null;
    final controller = (settings == null
        ? SessionController.send(
            files: widget.files,
            pin: pin,
            platform: widget.platform,
            notificationTitle: l.notificationTitle,
            notificationText: l.notificationText,
            notificationStop: l.notificationStop,
          )
        : SessionController.receive(
            stagingDir: widget.stagingDir!,
            pin: pin,
            delivery: Delivery(platform: widget.platform, settings: settings),
            platform: widget.platform,
            notificationTitle: l.notificationReceiveTitle,
            notificationText: l.notificationText,
            notificationStop: l.notificationStop,
          ))
      ..addListener(_changed);
    _controller = controller;
    unawaited(_start(controller));
    _helpTimer = Timer(_helpDelay, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _start(SessionController c) async {
    await c.start();
    if (widget.startHotspot && mounted) await _startHotspot();
  }

  Future<void> _startHotspot() async {
    final c = _controller!;
    await c.startHotspot();
    final failure = c.hotspotFailure;
    if (!mounted || failure == null) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hotspotFailureText(l, failure)),
      action: failure == HotspotFailure.locationOff
          ? SnackBarAction(
              label: l.hotspotOpenLocation,
              onPressed: () => unawaited(widget.platform.openLocationSettings()))
          : null,
    ));
  }

  void _otherWays() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NoNetworkScreen(platform: widget.platform)));
  }

  void _changed() {
    final c = _controller!;
    if (c.phase == SessionPhase.stopped && !_popped && mounted) {
      _popped = true;
      if (c.stopReason == StopReason.failed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context).sessionStartFailed(c.error ?? ''))));
      }
      Navigator.of(context).pop(c.stopReason);
      return;
    }
    if (!mounted) return;
    if (c.hotspotLost) {
      c.hotspotLost = false;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).hotspotLost)));
    }
    if (widget.receiving) _receiveNotices(c);
    setState(() {});
  }

  /// Receive mode: the approval sheet and one-off messages.
  void _receiveNotices(SessionController c) {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final offer = c.pendingOffer;
    if (offer != null && offer.id != _sheetOfferId) {
      _sheetOfferId = offer.id;
      unawaited(_askAboutOffer(c, offer));
    }
    if (c.offerExpired) {
      c.offerExpired = false;
      messenger.showSnackBar(SnackBar(content: Text(l.offerExpired)));
    }
    final finished = c.lastFinished;
    if (finished != null) {
      c.lastFinished = null;
      messenger.showSnackBar(SnackBar(
          content: Text(l.receiveDoneCount(finished.offer.files.length))));
    }
    if (c.deliveryErrors.length > _errorsShown) {
      _errorsShown = c.deliveryErrors.length;
      messenger.showSnackBar(SnackBar(
          content: Text(l.receiveSaveFailed(c.deliveryErrors.last))));
    }
  }

  Future<void> _askAboutOffer(SessionController c, UploadOffered offer) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OfferSheet(controller: c, offer: offer),
    );
    if (!mounted || c.pendingOffer?.id != offer.id) return;
    if (accepted == true) {
      await c.acceptOffer();
    } else if (accepted == false) {
      await c.declineOffer();
    }
  }

  Future<void> _stop() async {
    await _controller!.stop(StopReason.user);
  }

  @override
  void dispose() {
    _helpTimer?.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  bool get _showHelp {
    final c = _controller!;
    final since = c.activeSince;
    return c.guests.isEmpty &&
        since != null &&
        DateTime.now().difference(since) >= _helpDelay;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = _controller!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_stop());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.appTitle),
          automaticallyImplyLeading: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(widget.receiving
                    ? l.sessionStopReceiving
                    : l.sessionStop),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final hotspot =
                widget.platform.canStartHotspot ? _startHotspot : null;
            final help = _showHelp
                ? _Help(
                    desktop: _desktop,
                    onStartHotspot: c.hotspot == null ? hotspot : null,
                    onOtherWays: _otherWays)
                : null;
            final code = _CodePanel(
                controller: c,
                receiving: widget.receiving,
                onStartHotspot: hotspot,
                onOtherWays: _otherWays,
                maxSize: wide
                    ? min(constraints.maxHeight - 220, constraints.maxWidth / 2 - 80)
                    : constraints.maxWidth - 64);
            final Widget details = widget.receiving
                ? ReceivePanel(
                    controller: c,
                    settings: widget.settings!,
                    platform: widget.platform,
                    help: help,
                    onStop: _stop)
                : _DetailsPanel(controller: c, help: help, onStop: _stop);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24), child: code),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24), child: details),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [code, const SizedBox(height: 20), details],
            );
          }),
        ),
      ),
    );
  }
}

/// The QR code and the typeable address (or why there is none).
class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.controller,
    required this.receiving,
    required this.maxSize,
    required this.onStartHotspot,
    required this.onOtherWays,
  });

  final SessionController controller;
  final bool receiving;
  final double maxSize;

  /// Null where this device cannot make a hotspot.
  final VoidCallback? onStartHotspot;
  final VoidCallback onOtherWays;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final size = maxSize.clamp(180.0, 380.0);

    final hotspot = c.hotspot;
    if (hotspot != null && c.hotspotStep == 1) {
      return HotspotStepView(
          controller: c, hotspot: hotspot, size: size, onOtherWays: onOtherWays);
    }

    if (c.phase == SessionPhase.noNetwork) {
      final failure = c.hotspotFailure;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l.sessionNoNetwork,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (c.startingHotspot) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Text(l.hotspotStarting, textAlign: TextAlign.center),
            ] else if (onStartHotspot != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onStartHotspot,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: Text(l.hotspotStart),
              ),
            ],
            if (failure != null) ...[
              const SizedBox(height: 12),
              Text(hotspotFailureText(l, failure),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: onOtherWays, child: Text(l.noNetworkOtherWays)),
          ]),
        ),
      );
    }
    final url = c.url;
    if (url == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(hotspot != null ? l.hotspotStep2Title : l.sessionTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: QrCodeView(
            data: url.toString(),
            size: size,
            semanticLabel: url.toString(),
          ),
        ),
        const SizedBox(height: 12),
        Text(receiving ? l.receiveScanHint : l.sessionScanHint,
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        if (c.pin != null) ...[
          const SizedBox(height: 16),
          _PinCard(controller: c),
        ],
        const SizedBox(height: 20),
        Text(l.sessionTypeHint,
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        _TypeableUrl(text: c.typeableUrl ?? url.toString()),
        if (c.addresses.length > 1 && hotspot == null) ...[
          const SizedBox(height: 8),
          _NetworkChooser(controller: c),
        ],
        if (hotspot != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => c.showHotspotStep(1),
            icon: const Icon(Icons.wifi_rounded),
            label: Text(l.hotspotBack),
          ),
        ],
      ],
    );
  }
}

/// The session PIN, big, with wrong attempts and the lock-out if any.
class _PinCard extends StatelessWidget {
  const _PinCard({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final pin = c.pin!;
    return Card(
      color: c.pinLockedOut ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(children: [
          Text(l.sessionPinLabel, style: theme.textTheme.labelLarge),
          Text(pin.split('').join(' '),
              semanticsLabel: pin,
              style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text(
            c.pinLockedOut
                ? l.sessionPinLocked
                : c.wrongPins > 0
                    ? l.sessionWrongPins(c.wrongPins)
                    : l.sessionPinHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: c.pinLockedOut || c.wrongPins > 0
                    ? theme.colorScheme.error
                    : null),
          ),
        ]),
      ),
    );
  }
}

/// Hotspot step 1: the Wi-Fi code that joins this phone's network.
class HotspotStepView extends StatelessWidget {
  const HotspotStepView({
    super.key,
    required this.controller,
    required this.hotspot,
    required this.size,
    required this.onOtherWays,
  });

  final SessionController controller;
  final HotspotInfo hotspot;
  final double size;
  final VoidCallback onOtherWays;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final password = hotspot.password;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.hotspotStep1Title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: QrCodeView(
              data: wifiQrPayload(ssid: hotspot.ssid, password: password),
              size: size,
              semanticLabel: l.hotspotNetwork(hotspot.ssid),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(l.hotspotStep1Hint,
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SelectableText(
              [
                l.hotspotNetwork(hotspot.ssid),
                if (password != null) l.hotspotPassword(password),
              ].join('\n'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Note(icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            text: l.hotspotNoInternet),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => controller.showHotspotStep(2),
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(l.hotspotNext),
        ),
      ],
    );
  }
}

/// What to tell the user when the hotspot could not be started.
String hotspotFailureText(AppLocalizations l, HotspotFailure failure) =>
    switch (failure) {
      HotspotFailure.permission => l.hotspotFailedPermission,
      HotspotFailure.locationOff => l.hotspotFailedLocation,
      HotspotFailure.tetheringOn => l.hotspotFailedTethering,
      HotspotFailure.failed => l.hotspotFailed,
    };

class _TypeableUrl extends StatelessWidget {
  const _TypeableUrl({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: () => Clipboard.setData(ClipboardData(text: text)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SelectableText(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: Platform.isIOS || Platform.isMacOS ? 'Menlo' : 'monospace',
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkChooser extends StatelessWidget {
  const _NetworkChooser({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = controller.shown!;
    return PopupMenuButton<LanAddress>(
      initialValue: shown,
      onSelected: controller.show,
      itemBuilder: (context) => [
        for (final a in controller.addresses)
          PopupMenuItem(value: a, child: Text(describeAddress(context, a))),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(l.sessionShownNetwork(describeAddress(context, shown))),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

/// Status, notes, help, per-file progress and Stop.
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel(
      {required this.controller, required this.help, required this.onStop});

  final SessionController controller;
  final Widget? help;
  final VoidCallback onStop;

  String _status(AppLocalizations l) {
    final c = controller;
    if (c.phase == SessionPhase.noNetwork) return l.sessionNoNetwork;
    final current = c.currentDownload;
    if (current != null) {
      return l.sessionSending(current.name, (current.fraction * 100).floor());
    }
    if (c.doneCount > 0) return l.sessionDoneCount(c.doneCount, c.files.length);
    if (c.guests.isNotEmpty) return l.sessionConnected(c.guests.values.last.label);
    return l.sessionWaiting;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final current = c.currentDownload;
    final keepOpen = Platform.isIOS
        ? l.sessionKeepOpenIos
        : Platform.isAndroid
            ? l.sessionKeepOpenAndroid
            : l.sessionKeepOpenDesktop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(
                    c.guests.isEmpty
                        ? Icons.hourglass_empty_rounded
                        : Icons.phonelink_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_status(l),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ]),
                if (current != null) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: current.fraction,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Note(icon: Icons.info_outline_rounded, text: keepOpen),
        if (c.resumedAfterBackground) ...[
          const SizedBox(height: 8),
          _Note(icon: Icons.play_circle_outline, text: l.sessionPaused),
        ],
        if (help != null) ...[
          const SizedBox(height: 12),
          help!,
        ],
        const SizedBox(height: 20),
        Text(l.sessionFiles, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < c.files.length; i++) ...[
          _FileProgressRow(file: c.files[i], progress: c.progress[i]),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onStop,
          style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error),
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(l.sessionStop),
        ),
      ],
    );
  }
}

final _desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// A tinted line of advice with an icon.
class SessionNote extends StatelessWidget {
  const SessionNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => _Note(icon: icon, text: text);
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer)),
        ),
      ]),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help(
      {required this.desktop,
      required this.onStartHotspot,
      required this.onOtherWays});

  final bool desktop;
  final VoidCallback? onStartHotspot;
  final VoidCallback onOtherWays;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = [
      l.helpSameWifi,
      l.helpIsolation,
      l.helpStayConnected,
      l.helpTypeAddress,
      if (desktop) l.helpFirewall,
    ];
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.helpTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onTertiaryContainer)),
            const SizedBox(height: 8),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('•  $p',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer)),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (onStartHotspot != null)
                FilledButton.tonalIcon(
                  onPressed: onStartHotspot,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: Text(l.helpStartHotspot),
                ),
              TextButton(
                  onPressed: onOtherWays, child: Text(l.noNetworkOtherWays)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _FileProgressRow extends StatelessWidget {
  const _FileProgressRow({required this.file, required this.progress});

  final SharedFile file;
  final FileProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = progress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          FileBadge(name: file.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if (p.activeDownloads > 0 || (p.bytes > 0 && !p.done))
                  LinearProgressIndicator(
                      value: p.fraction,
                      borderRadius: BorderRadius.circular(3))
                else
                  Text(
                    p.done
                        ? '${l.sessionFileDone} · ${formatBytes(file.length)}'
                        : '${formatBytes(file.length)} · ${l.sessionFileWaiting}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (p.done) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
          ],
        ]),
      ),
    );
  }
}
