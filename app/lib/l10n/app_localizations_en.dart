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
  String get homeReceiveHint =>
      'The other device sends them from its browser. It doesn\'t need this app.';

  @override
  String get homeSettings => 'Settings';

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
  String get sessionStopReceiving => 'Stop receiving';

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

  @override
  String get receiveScanHint =>
      'Open the camera on the other phone and point it at the code. Then choose the files to send there.';

  @override
  String receiveReceiving(String name, int percent) {
    return 'Receiving $name · $percent%';
  }

  @override
  String receiveDoneCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files received',
      one: '1 file received',
    );
    return '$_temp0';
  }

  @override
  String receiveSavedIn(String location) {
    return 'Received files are saved in $location.';
  }

  @override
  String get receiveFolderFellBack =>
      'Your chosen folder can\'t be used right now, so files were saved in the default folder instead. Check it in Settings.';

  @override
  String get receiveListTitle => 'Received';

  @override
  String get receiveNothingYet => 'Nothing received yet.';

  @override
  String receiveSaveFailed(String detail) {
    return 'Couldn\'t save $detail';
  }

  @override
  String offerTitle(String device, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$device wants to send you $_temp0';
  }

  @override
  String offerTotal(String size) {
    return '$size in total';
  }

  @override
  String offerMore(int count) {
    return 'and $count more';
  }

  @override
  String get offerAlreadyHere =>
      'These files have already arrived. Accept to keep them, or decline to delete them.';

  @override
  String get offerAccept => 'Accept';

  @override
  String get offerDecline => 'Decline';

  @override
  String get offerExpired =>
      'Nobody answered in time, so the files were not accepted. The other device can send them again.';

  @override
  String get saveToPhotos => 'Save to Photos';

  @override
  String get savedToPhotos => 'In Photos';

  @override
  String get photosDenied =>
      'GeniusTransfer isn\'t allowed to add to Photos. You can allow it in Settings › Privacy & Security › Photos.';

  @override
  String get showInFinder => 'Show in Finder';

  @override
  String get showInFolder => 'Show in folder';

  @override
  String get saveDefaultAndroid =>
      'Pictures, Movies or Download › GeniusTransfer, by file type';

  @override
  String get saveDefaultIos =>
      'Files › On My iPhone › GeniusTransfer › Received';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSaveFolder => 'Save received files in';

  @override
  String get settingsDefault => 'Default';

  @override
  String get settingsCustom => 'Chosen folder';

  @override
  String get settingsChooseFolder => 'Choose a folder…';

  @override
  String get settingsUseDefault => 'Use the default';

  @override
  String settingsFolderFailed(String error) {
    return 'Couldn\'t use that folder: $error';
  }

  @override
  String get settingsPhotosNote =>
      'Photos and videos you receive can also be added to Photos from the list of received files.';

  @override
  String get notificationReceiveTitle => 'Receiving files';
}
