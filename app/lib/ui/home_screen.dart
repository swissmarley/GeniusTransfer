import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../net/lan_address.dart';
import '../platform/host_platform.dart';
import '../receive/delivery.dart' show receiveStagingDir;
import '../settings.dart';
import '../session/session_controller.dart';
import 'format.dart';
import 'no_network_screen.dart';
import 'send_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.platform, required this.settings});

  final HostPlatform platform;
  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HostPlatform get platform => widget.platform;
  AppSettings get settings => widget.settings;
  bool _takingShared = false;

  @override
  void initState() {
    super.initState();
    platform.onSharedFilesAvailable = _openShared;
    // Started from another app's share sheet: the files are already waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShared());
  }

  @override
  void dispose() {
    if (platform.onSharedFilesAvailable == _openShared) {
      platform.onSharedFilesAvailable = null;
    }
    super.dispose();
  }

  /// Android: opens Send with the files another app shared with us. While
  /// another screen is open (a session, say), they wait for Home.
  Future<void> _openShared() async {
    if (!mounted || _takingShared) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _takingShared = true;
    try {
      final shared = await platform.takeSharedFiles();
      // Released before Send opens, so a share during that session is
      // picked up when it ends.
      _takingShared = false;
      if (shared.isNotEmpty && mounted) await _send(context, shared: shared);
    } catch (e) {
      debugPrint('Could not open shared files: $e');
    } finally {
      _takingShared = false;
    }
  }

  Future<void> _send(BuildContext context,
      {List<AndroidPickedFile> shared = const []}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await Navigator.of(context).push<StopReason>(
      MaterialPageRoute(
          builder: (_) => SendScreen(
              platform: platform,
              shared: shared,
              requirePin: settings.requirePin)),
    );
    if (reason == StopReason.idle) {
      messenger.showSnackBar(SnackBar(content: Text(l.sessionIdleStopped)));
    }
    unawaited(_openShared());
  }

  Future<void> _receive(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var hotspot = false;
    if ((await findLanAddresses()).isEmpty) {
      if (!context.mounted) return;
      if (!platform.canStartHotspot) {
        showNoNetworkSnackBar(context, platform);
        return;
      }
      if (await askToStartHotspot(context, platform) != true) return;
      hotspot = true;
    }
    if (Platform.isAndroid) {
      // Shown at a calm moment, before the code; see SendScreen.
      await platform.requestNotificationPermission();
    }
    final staging = await receiveStagingDir();
    final reason = await navigator.push<StopReason>(MaterialPageRoute(
      builder: (_) => SessionScreen.receive(
          platform: platform,
          settings: settings,
          stagingDir: staging,
          requirePin: settings.requirePin,
          startHotspot: hotspot),
    ));
    if (reason == StopReason.idle) {
      messenger.showSnackBar(SnackBar(content: Text(l.sessionIdleStopped)));
    }
    unawaited(_openShared());
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(settings: settings, platform: platform),
    ));
    unawaited(_openShared());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: l.homeSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(l.appTitle,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(l.homeOffline, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                const _NetworkStatus(),
                const SizedBox(height: 24),
                _BigAction(
                  icon: Icons.upload_rounded,
                  title: l.homeSend,
                  subtitle: l.homeSendHint,
                  onTap: () => _send(context),
                ),
                const SizedBox(height: 14),
                _BigAction(
                  icon: Icons.download_rounded,
                  title: l.homeReceive,
                  subtitle: l.homeReceiveHint,
                  onTap: () => _receive(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color =
        enabled ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: enabled ? null : theme.disabledColor)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (enabled) Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Wi-Fi ready · 192.168.1.23", refreshed every few seconds.
class _NetworkStatus extends StatefulWidget {
  const _NetworkStatus();

  @override
  State<_NetworkStatus> createState() => _NetworkStatusState();
}

class _NetworkStatusState extends State<_NetworkStatus> {
  List<LanAddress>? _addresses;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final found = await findLanAddresses();
    if (mounted) setState(() => _addresses = found);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final addresses = _addresses;
    if (addresses == null) return const SizedBox(height: 40);
    final ok = addresses.isNotEmpty;
    final color = ok ? Colors.green.shade700 : theme.colorScheme.error;
    final text = ok
        ? l.homeNetwork(networkKindLabel(context, addresses.first.kind),
            addresses.first.address.address)
        : l.homeNoNetwork;
    return Row(
      children: [
        Icon(ok ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodyLarge?.copyWith(color: color)),
        ),
      ],
    );
  }
}
