import 'package:flutter/material.dart';

import 'dev/self_test.dart';
import 'l10n/app_localizations.dart';
import 'platform/host_platform.dart';
import 'session/session_controller.dart' show kSelfTest;
import 'ui/home_screen.dart';
import 'ui/theme.dart';

class GeniusTransferApp extends StatelessWidget {
  const GeniusTransferApp({super.key, required this.platform});

  final HostPlatform platform;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: kSelfTest
          ? SelfTestScreen(platform: platform)
          : HomeScreen(platform: platform),
    );
  }
}
