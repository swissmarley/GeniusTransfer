import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:transfer_server/transfer_server.dart';

import '../l10n/app_localizations.dart';
import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import '../session/session_controller.dart';
import 'format.dart';
import 'qr_code_view.dart';
import 'send_screen.dart' show FileBadge;

/// The code to scan, live status, and Stop.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.files, required this.platform});

  /// The files to share. The session owns and releases them.
  final List<SharedFile> files;
  final HostPlatform platform;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionController? _controller;
  Timer? _helpTimer;
  bool _popped = false;

  /// Show the "not opening?" help if nobody has connected after this long.
  static const _helpDelay = Duration(seconds: 30);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final l = AppLocalizations.of(context);
    final controller = SessionController(
      files: widget.files,
      platform: widget.platform,
      notificationTitle: l.notificationTitle,
      notificationText: l.notificationText,
      notificationStop: l.notificationStop,
    )..addListener(_changed);
    _controller = controller;
    unawaited(controller.start());
    _helpTimer = Timer(_helpDelay, () {
      if (mounted) setState(() {});
    });
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
    if (mounted) setState(() {});
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
                label: Text(l.sessionStop),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final code = _CodePanel(
                controller: c,
                maxSize: wide
                    ? min(constraints.maxHeight - 220, constraints.maxWidth / 2 - 80)
                    : constraints.maxWidth - 64);
            final details = _DetailsPanel(
                controller: c, showHelp: _showHelp, onStop: _stop);
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
  const _CodePanel({required this.controller, required this.maxSize});

  final SessionController controller;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;

    if (c.phase == SessionPhase.noNetwork) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l.sessionNoNetwork,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
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

    final size = maxSize.clamp(180.0, 380.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(l.sessionTitle,
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
        Text(l.sessionScanHint,
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        Text(l.sessionTypeHint,
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        _TypeableUrl(text: c.typeableUrl ?? url.toString()),
        if (c.addresses.length > 1) ...[
          const SizedBox(height: 8),
          _NetworkChooser(controller: c),
        ],
      ],
    );
  }
}

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
      {required this.controller, required this.showHelp, required this.onStop});

  final SessionController controller;
  final bool showHelp;
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
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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
        if (showHelp) ...[
          const SizedBox(height: 12),
          _Help(desktop: desktop),
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
  const _Help({required this.desktop});

  final bool desktop;

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
