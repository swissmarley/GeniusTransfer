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

  /// No description provided for @homeReceiveHint.
  ///
  /// In en, this message translates to:
  /// **'The other device sends them from its browser. It doesn\'t need this app.'**
  String get homeReceiveHint;

  /// No description provided for @homeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettings;

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

  /// No description provided for @sessionStopReceiving.
  ///
  /// In en, this message translates to:
  /// **'Stop receiving'**
  String get sessionStopReceiving;

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
  /// **'Guest, hotel and café Wi-Fi often stop phones from seeing each other. Try another network or a hotspot.'**
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

  /// No description provided for @receiveScanHint.
  ///
  /// In en, this message translates to:
  /// **'Open the camera on the other phone and point it at the code. Then choose the files to send there.'**
  String get receiveScanHint;

  /// No description provided for @receiveReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving {name} · {percent}%'**
  String receiveReceiving(String name, int percent);

  /// No description provided for @receiveDoneCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file received} other{{count} files received}}'**
  String receiveDoneCount(int count);

  /// No description provided for @receiveSavedIn.
  ///
  /// In en, this message translates to:
  /// **'Received files are saved in {location}.'**
  String receiveSavedIn(String location);

  /// No description provided for @receiveFolderFellBack.
  ///
  /// In en, this message translates to:
  /// **'Your chosen folder can\'t be used right now, so files were saved in the default folder instead. Check it in Settings.'**
  String get receiveFolderFellBack;

  /// No description provided for @receiveListTitle.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get receiveListTitle;

  /// No description provided for @receiveNothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing received yet.'**
  String get receiveNothingYet;

  /// No description provided for @receiveSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save {detail}'**
  String receiveSaveFailed(String detail);

  /// No description provided for @offerTitle.
  ///
  /// In en, this message translates to:
  /// **'{device} wants to send you {count, plural, =1{1 file} other{{count} files}}'**
  String offerTitle(String device, int count);

  /// No description provided for @offerTotal.
  ///
  /// In en, this message translates to:
  /// **'{size} in total'**
  String offerTotal(String size);

  /// No description provided for @offerMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String offerMore(int count);

  /// No description provided for @offerAlreadyHere.
  ///
  /// In en, this message translates to:
  /// **'These files have already arrived. Accept to keep them, or decline to delete them.'**
  String get offerAlreadyHere;

  /// No description provided for @offerAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get offerAccept;

  /// No description provided for @offerDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get offerDecline;

  /// No description provided for @offerExpired.
  ///
  /// In en, this message translates to:
  /// **'Nobody answered in time, so the files were not accepted. The other device can send them again.'**
  String get offerExpired;

  /// No description provided for @saveToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Save to Photos'**
  String get saveToPhotos;

  /// No description provided for @savedToPhotos.
  ///
  /// In en, this message translates to:
  /// **'In Photos'**
  String get savedToPhotos;

  /// No description provided for @photosDenied.
  ///
  /// In en, this message translates to:
  /// **'GeniusTransfer isn\'t allowed to add to Photos. You can allow it in Settings › Privacy & Security › Photos.'**
  String get photosDenied;

  /// No description provided for @showInFinder.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get showInFinder;

  /// No description provided for @showInFolder.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get showInFolder;

  /// No description provided for @saveDefaultAndroid.
  ///
  /// In en, this message translates to:
  /// **'Pictures, Movies or Download › GeniusTransfer, by file type'**
  String get saveDefaultAndroid;

  /// No description provided for @saveDefaultIos.
  ///
  /// In en, this message translates to:
  /// **'Files › On My iPhone › GeniusTransfer › Received'**
  String get saveDefaultIos;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSaveFolder.
  ///
  /// In en, this message translates to:
  /// **'Save received files in'**
  String get settingsSaveFolder;

  /// No description provided for @settingsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsDefault;

  /// No description provided for @settingsCustom.
  ///
  /// In en, this message translates to:
  /// **'Chosen folder'**
  String get settingsCustom;

  /// No description provided for @settingsChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder…'**
  String get settingsChooseFolder;

  /// No description provided for @settingsUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use the default'**
  String get settingsUseDefault;

  /// No description provided for @settingsFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t use that folder: {error}'**
  String settingsFolderFailed(String error);

  /// No description provided for @settingsPhotosNote.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos you receive can also be added to Photos from the list of received files.'**
  String get settingsPhotosNote;

  /// No description provided for @notificationReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receiving files'**
  String get notificationReceiveTitle;

  /// No description provided for @hotspotStart.
  ///
  /// In en, this message translates to:
  /// **'Start a hotspot on this phone'**
  String get hotspotStart;

  /// No description provided for @hotspotStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting the hotspot…'**
  String get hotspotStarting;

  /// No description provided for @hotspotStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Step 1 of 2: join this phone\'s Wi-Fi'**
  String get hotspotStep1Title;

  /// No description provided for @hotspotStep1Hint.
  ///
  /// In en, this message translates to:
  /// **'On the other phone, open the camera, scan this code and tap Join. Or join this network in its Wi-Fi settings.'**
  String get hotspotStep1Hint;

  /// No description provided for @hotspotNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network: {ssid}'**
  String hotspotNetwork(String ssid);

  /// No description provided for @hotspotPassword.
  ///
  /// In en, this message translates to:
  /// **'Password: {password}'**
  String hotspotPassword(String password);

  /// No description provided for @hotspotNext.
  ///
  /// In en, this message translates to:
  /// **'Joined? Show the second code'**
  String get hotspotNext;

  /// No description provided for @hotspotStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Step 2 of 2: scan to open the page'**
  String get hotspotStep2Title;

  /// No description provided for @hotspotBack.
  ///
  /// In en, this message translates to:
  /// **'Show the Wi-Fi code again'**
  String get hotspotBack;

  /// No description provided for @hotspotNoInternet.
  ///
  /// In en, this message translates to:
  /// **'The other phone may warn that this Wi-Fi has no internet. That\'s expected: if it asks, choose to stay connected.'**
  String get hotspotNoInternet;

  /// No description provided for @hotspotLost.
  ///
  /// In en, this message translates to:
  /// **'The hotspot was turned off. Start it again, or connect both devices to the same Wi-Fi.'**
  String get hotspotLost;

  /// No description provided for @hotspotFailedPermission.
  ///
  /// In en, this message translates to:
  /// **'GeniusTransfer needs the Nearby devices (or Location) permission to create a hotspot. Allow it and try again.'**
  String get hotspotFailedPermission;

  /// No description provided for @hotspotFailedLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on Location first: this version of Android requires it to create a hotspot.'**
  String get hotspotFailedLocation;

  /// No description provided for @hotspotOpenLocation.
  ///
  /// In en, this message translates to:
  /// **'Open Location settings'**
  String get hotspotOpenLocation;

  /// No description provided for @hotspotFailedTethering.
  ///
  /// In en, this message translates to:
  /// **'Turn off this phone\'s own hotspot or tethering first, then try again.'**
  String get hotspotFailedTethering;

  /// No description provided for @hotspotFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the hotspot. Make sure Wi-Fi is on and try again, or use the other phone\'s hotspot.'**
  String get hotspotFailed;

  /// No description provided for @noNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'No Wi-Fi here'**
  String get noNetworkTitle;

  /// No description provided for @noNetworkHotspotBody.
  ///
  /// In en, this message translates to:
  /// **'This phone can create its own Wi-Fi network for the other phone to join. Nothing goes through the internet.'**
  String get noNetworkHotspotBody;

  /// No description provided for @noNetworkOtherWays.
  ///
  /// In en, this message translates to:
  /// **'Other ways to connect'**
  String get noNetworkOtherWays;

  /// No description provided for @noNetworkCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get noNetworkCancel;

  /// No description provided for @helpStartHotspot.
  ///
  /// In en, this message translates to:
  /// **'Start a hotspot instead'**
  String get helpStartHotspot;

  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'No shared Wi-Fi?'**
  String get guideTitle;

  /// No description provided for @guideIntro.
  ///
  /// In en, this message translates to:
  /// **'Both devices need to be on the same network. Without a Wi-Fi network, one of the phones can make one with its hotspot. No internet is used.'**
  String get guideIntro;

  /// No description provided for @guideOtherHotspotTitle.
  ///
  /// In en, this message translates to:
  /// **'Use the other phone\'s hotspot'**
  String get guideOtherHotspotTitle;

  /// No description provided for @guideOtherHotspotStep1.
  ///
  /// In en, this message translates to:
  /// **'On the other phone, turn on its hotspot. iPhone: Settings › Personal Hotspot › Allow Others to Join. Android: Settings › Connections or Network › Hotspot.'**
  String get guideOtherHotspotStep1;

  /// No description provided for @guideOtherHotspotStep2Iphone.
  ///
  /// In en, this message translates to:
  /// **'On this iPhone, open Settings › Wi-Fi and join that network.'**
  String get guideOtherHotspotStep2Iphone;

  /// No description provided for @guideOtherHotspotStep2Android.
  ///
  /// In en, this message translates to:
  /// **'On this phone, open the Wi-Fi settings and join that network.'**
  String get guideOtherHotspotStep2Android;

  /// No description provided for @guideOtherHotspotStep2Computer.
  ///
  /// In en, this message translates to:
  /// **'On this computer, join that Wi-Fi network.'**
  String get guideOtherHotspotStep2Computer;

  /// No description provided for @guideOtherHotspotStep3.
  ///
  /// In en, this message translates to:
  /// **'Come back here. The code updates by itself; scan it with the other phone.'**
  String get guideOtherHotspotStep3;

  /// No description provided for @guideOwnHotspotTitle.
  ///
  /// In en, this message translates to:
  /// **'Use this iPhone\'s Personal Hotspot'**
  String get guideOwnHotspotTitle;

  /// No description provided for @guideOwnHotspotStep1.
  ///
  /// In en, this message translates to:
  /// **'Open Settings › Personal Hotspot and turn on Allow Others to Join. Your mobile plan must include it.'**
  String get guideOwnHotspotStep1;

  /// No description provided for @guideOwnHotspotStep2.
  ///
  /// In en, this message translates to:
  /// **'On the other phone, join this iPhone\'s Wi-Fi network. To let it scan a code instead of typing the password, save the name and password below.'**
  String get guideOwnHotspotStep2;

  /// No description provided for @guideOwnHotspotStep3.
  ///
  /// In en, this message translates to:
  /// **'When the other phone has joined, the code here updates. Scan it with the other phone.'**
  String get guideOwnHotspotStep3;

  /// No description provided for @guideHotspotName.
  ///
  /// In en, this message translates to:
  /// **'Hotspot name'**
  String get guideHotspotName;

  /// No description provided for @guideHotspotPassword.
  ///
  /// In en, this message translates to:
  /// **'Hotspot password'**
  String get guideHotspotPassword;

  /// No description provided for @guideHotspotSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get guideHotspotSave;

  /// No description provided for @guideHotspotSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Saved only on this iPhone.'**
  String get guideHotspotSavedNote;

  /// No description provided for @guideHotspotScan.
  ///
  /// In en, this message translates to:
  /// **'Scan this with the other phone\'s camera to join this iPhone\'s hotspot.'**
  String get guideHotspotScan;

  /// No description provided for @guideAndroidTitle.
  ///
  /// In en, this message translates to:
  /// **'Use this phone\'s hotspot'**
  String get guideAndroidTitle;

  /// No description provided for @guideAndroidBody.
  ///
  /// In en, this message translates to:
  /// **'This phone can create a Wi-Fi network just for this transfer. The other phone joins it by scanning a code.'**
  String get guideAndroidBody;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for a PIN'**
  String get settingsPinTitle;

  /// No description provided for @settingsPinBody.
  ///
  /// In en, this message translates to:
  /// **'The other device must type a 4-digit PIN shown next to the code. Useful in public places: someone who scans the code without the PIN sees nothing.'**
  String get settingsPinBody;

  /// No description provided for @sessionPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get sessionPinLabel;

  /// No description provided for @sessionPinHint.
  ///
  /// In en, this message translates to:
  /// **'The other device will ask for this PIN.'**
  String get sessionPinHint;

  /// No description provided for @sessionWrongPins.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 wrong PIN was entered.} other{{count} wrong PINs were entered.}}'**
  String sessionWrongPins(int count);

  /// No description provided for @sessionPinLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked after 5 wrong PINs: nobody else can join. Stop and start again to share with someone else.'**
  String get sessionPinLocked;
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
