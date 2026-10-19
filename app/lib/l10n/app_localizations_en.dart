// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GeniusTransfer';

  @override
  String get homeSend => 'Send files';

  @override
  String get homeSendHint =>
      'The other device downloads them in its browser. It doesn\'t need this app.';

  @override
  String get homeReceive => 'Receive files';

  @override
  String get homeReceiveSoon => 'Coming in the next version.';

  @override
  String get homeNoNetwork =>
      'Not connected to a network. Connect both devices to the same Wi-Fi.';

  @override
  String homeNetwork(String kind, String address) {
    return '$kind ready · $address';
  }

  @override
  String get homeOffline =>
      'Works without internet. Nothing goes through the cloud.';

  @override
  String get networkWifi => 'Wi-Fi';

  @override
  String get networkWired => 'Network cable';

  @override
  String get networkHotspot => 'Hotspot';

  @override
  String get networkOther => 'Network';

  @override
  String get sendTitle => 'Choose what to send';

  @override
  String get sendPickMedia => 'Photos & videos';

  @override
  String get sendPickFiles => 'Files';

  @override
  String get sendEmpty => 'Nothing chosen yet. Add photos, videos or files.';

  @override
  String sendSummary(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0 · $size';
  }

  @override
  String get sendStart => 'Show the code';

  @override
  String get sendPreparing => 'Preparing…';

  @override
  String sendRemove(String name) {
    return 'Remove $name';
  }

  @override
  String sendPickFailed(String error) {
    return 'Couldn\'t add those files: $error';
  }

  @override
  String get sendNeedsWifi =>
      'Connect to Wi-Fi first. Both phones must be on the same network.';

  @override
  String get sessionTitle => 'Scan this with the other phone';

  @override
  String get sessionScanHint =>
      'Open the camera on the other phone and point it at the code. Then tap Download there.';

  @override
  String get sessionTypeHint =>
      'Computer or no camera? Type this in its browser:';

  @override
  String sessionShownNetwork(String network) {
    return 'Code for: $network';
  }

  @override
  String get sessionWaiting => 'Waiting for the other phone…';

  @override
  String sessionConnected(String device) {
    return 'Connected: $device';
  }

  @override
  String sessionSending(String name, int percent) {
    return 'Sending $name · $percent%';
  }

  @override
  String sessionDoneCount(int done, int total) {
    return 'Downloaded $done of $total';
  }

  @override
  String get sessionFileDone => 'Downloaded';

  @override
  String get sessionFileWaiting => 'Not downloaded yet';

  @override
  String get sessionStop => 'Stop sharing';

  @override
  String get sessionKeepOpenIos =>
      'Keep this screen open. If you leave the app, transfers pause until you come back.';

  @override
  String get sessionKeepOpenAndroid =>
      'Keep GeniusTransfer open until the other phone is done.';

  @override
  String get sessionKeepOpenDesktop =>
      'Keep this window open until the other device is done.';

  @override
  String get sessionPaused =>
      'Paused while the app was in the background. Ready again.';

  @override
  String get sessionNoNetwork =>
      'Wi-Fi was lost. Reconnect to the same Wi-Fi to keep sharing.';

  @override
  String get sessionIdleStopped =>
      'Sharing stopped after 30 minutes without activity.';

  @override
  String sessionStartFailed(String error) {
    return 'Couldn\'t start sharing: $error';
  }

  @override
  String get sessionFiles => 'Files';

  @override
  String get helpTitle => 'Not opening on the other phone?';

  @override
  String get helpSameWifi => 'Both phones must be on the same Wi-Fi network.';

  @override
  String get helpIsolation =>
      'Guest, hotel and café Wi-Fi often stop phones from seeing each other. Try another network or a phone\'s hotspot. A built-in hotspot mode is coming in a later version.';

  @override
  String get helpStayConnected =>
      'If the other phone says the Wi-Fi has no internet and asks to stay connected, tap Yes, or turn off its mobile data.';

  @override
  String get helpTypeAddress =>
      'No QR scanner? Type the address shown under the code into the browser. Capital letters and dashes are optional.';

  @override
  String get helpFirewall =>
      'If this computer asks whether GeniusTransfer may accept incoming connections or use the network, choose Allow. On Windows, allow it for private networks.';

  @override
  String get notificationTitle => 'Sharing files';

  @override
  String get notificationText =>
      'Keep GeniusTransfer open until the other phone is done.';

  @override
  String get notificationStop => 'Stop';
}
