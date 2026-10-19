import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/host_platform.dart';
import '../receive/save_settings.dart';
import 'receive_panel.dart' show describeSaveLocation;

/// Where received files are saved.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
      {super.key, required this.settings, required this.platform});

  final SaveSettings settings;
  final HostPlatform platform;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _choose() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.settings.chooseFolder(widget.platform);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.settingsFolderFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) {
                final custom = widget.settings.folder != null;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Text(l.settingsSaveFolder,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: Icon(custom
                            ? Icons.folder_special_outlined
                            : Icons.folder_outlined),
                        title: Text(
                            custom ? l.settingsCustom : l.settingsDefault),
                        subtitle: FutureBuilder<String>(
                          // Rebuilt with the settings, so it follows changes.
                          future: describeSaveLocation(l, widget.settings),
                          builder: (context, s) => Text(s.data ?? '…'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _choose,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: Text(l.settingsChooseFolder),
                    ),
                    if (custom) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed:
                            _busy ? null : () => widget.settings.useDefault(),
                        child: Text(l.settingsUseDefault),
                      ),
                    ],
                    if (Platform.isIOS) ...[
                      const SizedBox(height: 16),
                      Text(l.settingsPhotosNote,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
