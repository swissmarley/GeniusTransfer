import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../net/wifi_qr.dart';
import '../platform/host_platform.dart';
import 'qr_code_view.dart';

/// Android, when there is no network: offers to start a hotspot. Returns
/// true if the user wants one, false if not, null if they want the other
/// ways (the guide has been shown then).
Future<bool?> askToStartHotspot(
    BuildContext context, HostPlatform platform) async {
  final l = AppLocalizations.of(context);
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.wifi_tethering_rounded),
      title: Text(l.noNetworkTitle),
      content: Text(l.noNetworkHotspotBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'guide'),
          child: Text(l.noNetworkOtherWays),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l.noNetworkCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'hotspot'),
          child: Text(l.hotspotStart),
        ),
      ],
    ),
  );
  if (choice == 'hotspot') return true;
  if (choice == 'guide' && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NoNetworkScreen(platform: platform)));
    return null;
  }
  return false;
}

/// iPhone and computers, when there is no network: says so, with a way to
/// the guide.
void showNoNetworkSnackBar(BuildContext context, HostPlatform platform) {
  final l = AppLocalizations.of(context);
  final navigator = Navigator.of(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(l.sendNeedsWifi),
    action: SnackBarAction(
      label: l.noNetworkOtherWays,
      onPressed: () => navigator.push(MaterialPageRoute<void>(
          builder: (_) => NoNetworkScreen(platform: platform))),
    ),
  ));
}

/// How to connect two devices that share no Wi-Fi network, for each kind
/// of host.
class NoNetworkScreen extends StatelessWidget {
  const NoNetworkScreen({super.key, required this.platform});

  final HostPlatform platform;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final join = Platform.isIOS
        ? l.guideOtherHotspotStep2Iphone
        : Platform.isAndroid
            ? l.guideOtherHotspotStep2Android
            : l.guideOtherHotspotStep2Computer;
    return Scaffold(
      appBar: AppBar(title: Text(l.guideTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(l.guideIntro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                if (platform.canStartHotspot) ...[
                  _Section(
                    title: l.guideAndroidTitle,
                    children: [Text(l.guideAndroidBody)],
                  ),
                  const SizedBox(height: 12),
                ],
                if (Platform.isIOS) ...[
                  const _OwnHotspotSection(),
                  const SizedBox(height: 12),
                ],
                _Section(
                  title: l.guideOtherHotspotTitle,
                  children: [
                    _Step(n: 1, text: l.guideOtherHotspotStep1),
                    _Step(n: 2, text: join),
                    _Step(n: 3, text: l.guideOtherHotspotStep3),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text('$n',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}

/// iPhone: Personal Hotspot steps, with an optional saved name and password
/// so the other phone can join by scanning a code.
class _OwnHotspotSection extends StatefulWidget {
  const _OwnHotspotSection();

  @override
  State<_OwnHotspotSection> createState() => _OwnHotspotSectionState();
}

class _OwnHotspotSectionState extends State<_OwnHotspotSection> {
  static const _ssidKey = 'personalHotspot.ssid';
  static const _passwordKey = 'personalHotspot.password';

  final _prefs = SharedPreferencesAsync();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  String? _savedSsid;
  String? _savedPassword;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ssid = await _prefs.getString(_ssidKey);
      final password = await _prefs.getString(_passwordKey);
      if (!mounted) return;
      setState(() {
        _savedSsid = ssid;
        _savedPassword = password;
        _ssid.text = ssid ?? '';
        _password.text = password ?? '';
      });
    } catch (e) {
      debugPrint('Could not read the saved hotspot: $e');
    }
  }

  Future<void> _save() async {
    final ssid = _ssid.text.trim();
    final password = _password.text;
    setState(() {
      _savedSsid = ssid.isEmpty ? null : ssid;
      _savedPassword = password.isEmpty ? null : password;
    });
    FocusScope.of(context).unfocus();
    if (ssid.isEmpty) {
      await _prefs.remove(_ssidKey);
      await _prefs.remove(_passwordKey);
    } else {
      await _prefs.setString(_ssidKey, ssid);
      await _prefs.setString(_passwordKey, password);
    }
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ssid = _savedSsid;
    return _Section(
      title: l.guideOwnHotspotTitle,
      children: [
        _Step(n: 1, text: l.guideOwnHotspotStep1),
        _Step(n: 2, text: l.guideOwnHotspotStep2),
        _Step(n: 3, text: l.guideOwnHotspotStep3),
        const SizedBox(height: 16),
        if (ssid != null) ...[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: QrCodeView(
                data: wifiQrPayload(ssid: ssid, password: _savedPassword),
                size: 220,
                semanticLabel: l.hotspotNetwork(ssid),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(l.guideHotspotScan,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _ssid,
          decoration: InputDecoration(
              labelText: l.guideHotspotName,
              border: const OutlineInputBorder()),
          autocorrect: false,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          decoration: InputDecoration(
              labelText: l.guideHotspotPassword,
              border: const OutlineInputBorder()),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(l.guideHotspotSavedNote,
                style: theme.textTheme.bodySmall),
          ),
          FilledButton.tonal(onPressed: _save, child: Text(l.guideHotspotSave)),
        ]),
      ],
    );
  }
}
