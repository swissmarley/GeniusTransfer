import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/host_platform.dart';
import 'session/selection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = HostPlatform();
  // Copies left behind by an earlier run (e.g. after a crash).
  unawaited(cleanUpTemporaryFiles(platform));
  runApp(GeniusTransferApp(platform: platform));
}
