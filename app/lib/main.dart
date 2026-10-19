import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/host_platform.dart';
import 'receive/delivery.dart' show clearReceiveStaging;
import 'settings.dart';
import 'session/selection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = HostPlatform();
  // Copies left behind by an earlier run (e.g. after a crash).
  unawaited(cleanUpTemporaryFiles(platform));
  unawaited(clearReceiveStaging());
  final settings = await AppSettings.load();
  runApp(GeniusTransferApp(platform: platform, settings: settings));
}
