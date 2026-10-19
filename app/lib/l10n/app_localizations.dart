import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'GeniusTransfer'**
  String get appTitle;

  /// No description provided for @homeSend.
  ///
  /// In en, this message translates to:
  /// **'Send files'**
  String get homeSend;

  /// No description provided for @homeSendHint.
  ///
  /// In en, this message translates to:
  /// **'The other device downloads them in its browser. It doesn\'t need this app.'**
  String get homeSendHint;

  /// No description provided for @homeReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive files'**
  String get homeReceive;

  /// No description provided for @homeReceiveSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming in the next version.'**
  String get homeReceiveSoon;

  /// No description provided for @homeNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a network. Connect both devices to the same Wi-Fi.'**
  String get homeNoNetwork;

  /// No description provided for @homeNetwork.
  ///
  /// In en, this message translates to:
  /// **'{kind} ready · {address}'**
  String homeNetwork(String kind, String address);

  /// No description provided for @homeOffline.
  ///
  /// In en, this message translates to:
  /// **'Works without internet. Nothing goes through the cloud.'**
  String get homeOffline;

  /// No description provided for @networkWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get networkWifi;

  /// No description provided for @networkWired.
  ///
  /// In en, this message translates to:
  /// **'Network cable'**
  String get networkWired;

  /// No description provided for @networkHotspot.
  ///
  /// In en, this message translates to:
  /// **'Hotspot'**
  String get networkHotspot;

  /// No description provided for @networkOther.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkOther;

  /// No description provided for @sendTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what to send'**
  String get sendTitle;

  /// No description provided for @sendPickMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos & videos'**
  String get sendPickMedia;

  /// No description provided for @sendPickFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get sendPickFiles;

  /// No description provided for @sendEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing chosen yet. Add photos, videos or files.'**
  String get sendEmpty;

  /// No description provided for @sendSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}} · {size}'**
  String sendSummary(int count, String size);

  /// No description provided for @sendStart.
  ///
  /// In en, this message translates to:
  /// **'Show the code'**
  String get sendStart;

  /// No description provided for @sendPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get sendPreparing;

  /// No description provided for @sendRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String sendRemove(String name);

  /// No description provided for @sendPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add those files: {error}'**
  String sendPickFailed(String error);

  /// No description provided for @sendNeedsWifi.
  ///
  /// In en, this message translates to:
  /// **'Connect to Wi-Fi first. Both phones must be on the same network.'**
  String get sendNeedsWifi;

  /// No description provided for @sessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan this with the other phone'**
  String get sessionTitle;

  /// No description provided for @sessionScanHint.
  ///
  /// In en, this message translates to:
  /// **'Open the camera on the other phone and point it at the code. Then tap Download there.'**
  String get sessionScanHint;

  /// No description provided for @sessionTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Computer or no camera? Type this in its browser:'**
  String get sessionTypeHint;

  /// No description provided for @sessionShownNetwork.
  ///
  /// In en, this message translates to:
  /// **'Code for: {network}'**
  String sessionShownNetwork(String network);

  /// No description provided for @sessionWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the other phone…'**
  String get sessionWaiting;

  /// No description provided for @sessionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected: {device}'**
  String sessionConnected(String device);

  /// No description provided for @sessionSending.
  ///
  /// In en, this message translates to:
  /// **'Sending {name} · {percent}%'**
  String sessionSending(String name, int percent);

  /// No description provided for @sessionDoneCount.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {done} of {total}'**
  String sessionDoneCount(int done, int total);

  /// No description provided for @sessionFileDone.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get sessionFileDone;

  /// No description provided for @sessionFileWaiting.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded yet'**
  String get sessionFileWaiting;

  /// No description provided for @sessionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get sessionStop;

  /// No description provided for @sessionKeepOpenIos.
  ///
  /// In en, this message translates to:
  /// **'Keep this screen open. If you leave the app, transfers pause until you come back.'**
  String get sessionKeepOpenIos;

  /// No description provided for @sessionKeepOpenAndroid.
  ///
  /// In en, this message translates to:
  /// **'Keep GeniusTransfer open until the other phone is done.'**
  String get sessionKeepOpenAndroid;

  /// No description provided for @sessionKeepOpenDesktop.
  ///
  /// In en, this message translates to:
  /// **'Keep this window open until the other device is done.'**
  String get sessionKeepOpenDesktop;

  /// No description provided for @sessionPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused while the app was in the background. Ready again.'**
  String get sessionPaused;

  /// No description provided for @sessionNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi was lost. Reconnect to the same Wi-Fi to keep sharing.'**
  String get sessionNoNetwork;

  /// No description provided for @sessionIdleStopped.
  ///
  /// In en, this message translates to:
  /// **'Sharing stopped after 30 minutes without activity.'**
  String get sessionIdleStopped;

  /// No description provided for @sessionStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start sharing: {error}'**
  String sessionStartFailed(String error);

  /// No description provided for @sessionFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get sessionFiles;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Not opening on the other phone?'**
  String get helpTitle;

  /// No description provided for @helpSameWifi.
  ///
  /// In en, this message translates to:
  /// **'Both phones must be on the same Wi-Fi network.'**
  String get helpSameWifi;

  /// No description provided for @helpIsolation.
  ///
  /// In en, this message translates to:
  /// **'Guest, hotel and café Wi-Fi often stop phones from seeing each other. Try another network or a phone\'s hotspot. A built-in hotspot mode is coming in a later version.'**
  String get helpIsolation;

  /// No description provided for @helpStayConnected.
  ///
  /// In en, this message translates to:
  /// **'If the other phone says the Wi-Fi has no internet and asks to stay connected, tap Yes, or turn off its mobile data.'**
  String get helpStayConnected;

  /// No description provided for @helpTypeAddress.
  ///
  /// In en, this message translates to:
  /// **'No QR scanner? Type the address shown under the code into the browser. Capital letters and dashes are optional.'**
  String get helpTypeAddress;

  /// No description provided for @helpFirewall.
  ///
  /// In en, this message translates to:
  /// **'If this computer asks whether GeniusTransfer may accept incoming connections or use the network, choose Allow. On Windows, allow it for private networks.'**
  String get helpFirewall;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing files'**
  String get notificationTitle;

  /// No description provided for @notificationText.
  ///
  /// In en, this message translates to:
  /// **'Keep GeniusTransfer open until the other phone is done.'**
  String get notificationText;

  /// No description provided for @notificationStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get notificationStop;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
