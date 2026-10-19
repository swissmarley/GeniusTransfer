import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:transfer_server/transfer_server.dart';

import '../l10n/app_localizations.dart';
import '../platform/host_platform.dart';
import '../receive/delivery.dart';
import '../receive/save_settings.dart';
import '../session/session_controller.dart';
import 'format.dart';
import 'send_screen.dart' show FileBadge;
import 'session_screen.dart' show SessionNote;

/// Receive mode: status, where files go, what arrived, and Stop.
class ReceivePanel extends StatelessWidget {
  const ReceivePanel({
    super.key,
    required this.controller,
    required this.settings,
    required this.platform,
    required this.help,
    required this.onStop,
  });

  final SessionController controller;
  final SaveSettings settings;
  final HostPlatform platform;
  final Widget? help;
  final VoidCallback onStop;

  String _status(AppLocalizations l) {
    final c = controller;
    if (c.phase == SessionPhase.noNetwork) return l.sessionNoNetwork;
    final current = c.currentUpload;
    if (current != null) {
      return l.receiveReceiving(current.name, (current.fraction * 100).floor());
    }
    if (c.received.isNotEmpty) return l.receiveDoneCount(c.received.length);
    if (c.guests.isNotEmpty) {
      return l.sessionConnected(c.guests.values.last.label);
    }
    return l.sessionWaiting;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    final current = c.currentUpload;
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
        _SaveLocationNote(settings: settings),
        if (c.delivery?.fellBack ?? false) ...[
          const SizedBox(height: 8),
          SessionNote(
              icon: Icons.warning_amber_rounded, text: l.receiveFolderFellBack),
        ],
        const SizedBox(height: 8),
        SessionNote(icon: Icons.info_outline_rounded, text: keepOpen),
        if (c.resumedAfterBackground) ...[
          const SizedBox(height: 8),
          SessionNote(icon: Icons.play_circle_outline, text: l.sessionPaused),
        ],
        if (help != null) ...[const SizedBox(height: 12), help!],
        const SizedBox(height: 20),
        Text(l.receiveListTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (c.received.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.receiveNothingYet, style: theme.textTheme.bodyMedium),
          ),
        for (final file in c.received) ...[
          _ReceivedRow(file: file, platform: platform),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onStop,
          style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error),
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(l.sessionStopReceiving),
        ),
      ],
    );
  }
}

/// "Received files are saved in …"
class _SaveLocationNote extends StatelessWidget {
  const _SaveLocationNote({required this.settings});

  final SaveSettings settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: describeSaveLocation(l, settings),
      builder: (context, snapshot) => SessionNote(
        icon: Icons.folder_outlined,
        text: l.receiveSavedIn(snapshot.data ?? '…'),
      ),
    );
  }
}

/// Where received files go, in words: the chosen folder, or the default.
Future<String> describeSaveLocation(
    AppLocalizations l, SaveSettings settings) async {
  final folder = settings.folder;
  if (folder != null) return folder.name;
  if (Platform.isAndroid) return l.saveDefaultAndroid;
  if (Platform.isIOS) return l.saveDefaultIos;
  return Delivery.describeDefaultFolder();
}

class _ReceivedRow extends StatefulWidget {
  const _ReceivedRow({required this.file, required this.platform});

  final ReceivedFile file;
  final HostPlatform platform;

  @override
  State<_ReceivedRow> createState() => _ReceivedRowState();
}

class _ReceivedRowState extends State<_ReceivedRow> {
  bool _saving = false;

  Future<void> _saveToPhotos() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final file = widget.file;
    setState(() => _saving = true);
    try {
      final ok = await widget.platform
          .saveToPhotos(file.path!, video: file.isVideo);
      if (ok) {
        file.savedToPhotos = true;
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l.photosDenied)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.receiveSaveFailed('${file.name}: $e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reveal() async {
    final path = widget.file.path!;
    if (Platform.isMacOS) {
      await widget.platform.revealInFinder(path);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = widget.file;
    final where = file.savedIn == SavedIn.iosReceived
        ? l.saveDefaultIos
        : file.location;

    Widget? action;
    if (Platform.isIOS && file.path != null && (file.isImage || file.isVideo)) {
      action = file.savedToPhotos
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l.savedToPhotos,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: Colors.green.shade700)),
            )
          : TextButton(
              onPressed: _saving ? null : _saveToPhotos,
              child: Text(l.saveToPhotos),
            );
    } else if ((Platform.isMacOS || Platform.isWindows) && file.path != null) {
      action = IconButton(
        tooltip: Platform.isMacOS ? l.showInFinder : l.showInFolder,
        icon: const Icon(Icons.folder_open_outlined),
        onPressed: _reveal,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(children: [
          FileBadge(name: file.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${formatBytes(file.size)} · $where',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          ?action,
        ]),
      ),
    );
  }
}

/// Asks the host to accept or decline what a guest wants to send. Closes
/// itself (with no answer) if the offer goes away, e.g. when it expires.
class OfferSheet extends StatefulWidget {
  const OfferSheet({super.key, required this.controller, required this.offer});

  final SessionController controller;
  final UploadOffered offer;

  @override
  State<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<OfferSheet> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final c = widget.controller;
    final gone = c.pendingOffer?.id != widget.offer.id ||
        c.phase == SessionPhase.stopped;
    if (gone) _close(null);
  }

  void _close(bool? accepted) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(accepted);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final offer = widget.offer;
    const shown = 6;
    final files = offer.files;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.offerTitle(offer.device.label, files.length),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l.offerTotal(formatBytes(offer.totalBytes)),
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in files.take(shown))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: FileBadge(name: f.name),
                    title: Text(f.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatBytes(f.size)),
                  ),
                if (files.length > shown)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l.offerMore(files.length - shown)),
                  ),
              ],
            ),
          ),
          if (offer.quarantined) ...[
            const SizedBox(height: 8),
            SessionNote(
                icon: Icons.inventory_2_outlined, text: l.offerAlreadyHere),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _close(false),
                child: Text(l.offerDecline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _close(true),
                child: Text(l.offerAccept),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
