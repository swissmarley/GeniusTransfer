import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transfer_server/transfer_server.dart';

import '../platform/host_platform.dart';
import '../receive/delivery.dart' show receiveStagingDir;
import '../receive/save_settings.dart';
import '../session/selection.dart';
import '../session/session_controller.dart';
import '../ui/home_screen.dart';
import '../ui/session_screen.dart';

/// Only in builds made with `--dart-define=GT_SELFTEST=true`.
///
/// Writes a few test files with known content, starts a session with them
/// and logs `GT_SELFTEST_URL=…`, so `tool/selftest_check.py` can download them
/// from the Mac and compare checksums. Byte i of each file is
/// `(i * 31 + 7) & 0xff`.
///
/// With `--dart-define=GT_SELFTEST_MODE=receive` it starts a receiving
/// session instead, which accepts every offer and logs
/// `GT_SELFTEST_RECEIVED=…` and `GT_SELFTEST_SAVED=…` for each file, for
/// `tool/selftest_upload.py`.
class SelfTestScreen extends StatefulWidget {
  const SelfTestScreen(
      {super.key, required this.platform, required this.settings});

  final HostPlatform platform;
  final SaveSettings settings;

  @override
  State<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends State<SelfTestScreen> {
  static const files = {
    'selftest-small.txt': 1000,
    'selftest-photo.heic': 3 * 1000 * 1000,
    'selftest-video.mp4': 50 * 1000 * 1000,
  };

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (kSelfTestMode == 'receive') return _receive();
    final dir = await Directory(
            '${(await getTemporaryDirectory()).path}/selftest')
        .create(recursive: true);
    final shared = <SharedFile>[];
    for (final MapEntry(key: name, value: size) in files.entries) {
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      const chunk = 1 << 20;
      for (var offset = 0; offset < size; offset += chunk) {
        final n = offset + chunk > size ? size - offset : chunk;
        sink.add(Uint8List.fromList(
            List<int>.generate(n, (i) => ((offset + i) * 31 + 7) & 0xff)));
      }
      await sink.close();
      shared.add(await TempSharedFile.fromPath(file.path));
    }
    debugPrint('GT_SELFTEST_FILES=${files.keys.join(',')}');
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => SessionScreen(files: shared, platform: widget.platform),
    ));
    _continueNormally(navigator);
  }

  Future<void> _receive() async {
    final staging = await receiveStagingDir();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => SessionScreen.receive(
          platform: widget.platform,
          settings: widget.settings,
          stagingDir: staging),
    ));
    _continueNormally(navigator);
  }

  /// After Stop, continue like a normal launch.
  void _continueNormally(NavigatorState navigator) {
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) =>
          HomeScreen(platform: widget.platform, settings: widget.settings),
    ));
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
