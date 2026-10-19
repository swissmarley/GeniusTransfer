import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:transfer_server/transfer_server.dart';

import '../l10n/app_localizations.dart';
import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import '../session/selection.dart';
import '../session/session_controller.dart';
import 'format.dart';
import 'session_screen.dart';

/// Pick the files to share, then show the code.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.platform});

  final HostPlatform platform;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  late final Selection _selection = Selection(widget.platform)
    ..addListener(_changed);
  bool _handedOver = false;

  @override
  void initState() {
    super.initState();
    // Ask for the notification permission now, at a calm moment, rather
    // than in front of the other person. Android only shows it once or
    // twice; the sharing service works without it.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(widget.platform.requestNotificationPermission()));
    }
  }

  void _changed() => setState(() {});

  Future<void> _pick(Future<void> Function() pick) async {
    final l = AppLocalizations.of(context);
    try {
      await pick();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.sendPickFailed('$e'))));
    }
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if ((await findLanAddresses()).isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.sendNeedsWifi)));
      return;
    }
    _handedOver = true;
    final files = _selection.takeAll();
    final reason = await navigator.push<StopReason>(MaterialPageRoute(
      builder: (_) => SessionScreen(files: files, platform: widget.platform),
    ));
    // The session is over: back to the start, with the reason.
    if (mounted) navigator.pop(reason);
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    if (!_handedOver) unawaited(_selection.discard());
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final files = _selection.files;
    return Scaffold(
      appBar: AppBar(title: Text(l.sendTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selection.busy
                              ? null
                              : () => _pick(_selection.pickMedia),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(l.sendPickMedia),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selection.busy
                              ? null
                              : () => _pick(_selection.pickFiles),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(l.sendPickFiles),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selection.busy) ...[
                  const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(l.sendPreparing),
                  ),
                ],
                Expanded(
                  child: files.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(l.sendEmpty,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: files.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _FileRow(
                            file: files[i],
                            onRemove: () => _selection.removeAt(i),
                            removeLabel: l.sendRemove(files[i].name),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            l.sendSummary(
                                files.length, formatBytes(_selection.totalBytes)),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: files.isEmpty || _selection.busy ? null : _start,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: Text(l.sendStart),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow(
      {required this.file, required this.onRemove, required this.removeLabel});

  final SharedFile file;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        leading: FileBadge(name: file.name),
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatBytes(file.length),
            style: theme.textTheme.bodyMedium),
        trailing: IconButton(
          tooltip: removeLabel,
          icon: const Icon(Icons.close_rounded),
          onPressed: onRemove,
        ),
      ),
    );
  }
}

/// A square badge with the file extension, like on the guest page.
class FileBadge extends StatelessWidget {
  const FileBadge({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dot = name.lastIndexOf('.');
    var ext = dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : 'FILE';
    if (ext.length > 4) ext = ext.substring(0, 4);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(ext,
          style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer)),
    );
  }
}
