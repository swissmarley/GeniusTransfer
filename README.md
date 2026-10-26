# GeniusTransfer

Move files between an iPhone, an Android phone, and a computer on the local
network. Only one device needs the app. The other scans a QR code with its
camera, or types a short address, and uses its web browser.

Files go directly from one device to the other. A transfer works with no
internet connection, and nothing is sent to a server.

Release **0.1.0** is tested and working on iPhone, Android, macOS, Windows,
and Debian Linux (AMD64 and ARM64). The app’s interface is in English.

## Download

Builds are on the [0.1.0 release](https://github.com/swissmarley/GeniusTransfer/releases/tag/0.1.0).

| Device | File |
|---|---|
| Android phone or tablet | [GeniusTransfer-0.1.0-android.apk](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-android.apk) |
| iPhone or iPad | [GeniusTransfer-0.1.0-ios-unsigned.ipa](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-ios-unsigned.ipa) |
| Mac | [GeniusTransfer-0.1.0-macos-universal.dmg](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-macos-universal.dmg) |
| Windows | [GeniusTransfer-0.1.0-windows-x64.exe](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-windows-x64.exe) |
| Debian, 64-bit PC | [GeniusTransfer-0.1.0-linux-amd64.deb](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-linux-amd64.deb) |
| Debian, ARM64 | [GeniusTransfer-0.1.0-linux-arm64.deb](https://github.com/swissmarley/GeniusTransfer/releases/download/0.1.0/GeniusTransfer-0.1.0-linux-arm64.deb) |

### Android

Android 8.0 or later. Copy the APK to the phone or tablet and open it.
Allow “Install unknown apps” once. The APK is signed for sideloading
(arm64, 32-bit ARM, and x86_64).

On Android you can also start a send from another app: select the files,
Share, then GeniusTransfer.

### iPhone and iPad

iOS 15 or later. The IPA is unsigned, so a sideloader has to sign it with
your Apple ID before it can be installed. After the first install, open
Settings › General › VPN & Device Management, tap your Apple ID, and choose
Trust. Turn on Developer Mode if iOS asks for it.

An install signed with a free Apple ID expires after 7 days. Install the
app again to keep using it.

### macOS

macOS 12 or later, Apple silicon and Intel. Open the disk image and drag
GeniusTransfer to Applications, then launch it from there.

The app is signed for local use and is not notarized. If macOS blocks the
first launch, allow it in System Settings › Privacy & Security › Open
Anyway. The first time another device connects, allow incoming connections
when macOS asks.

### Windows

Windows 10 or 11, 64-bit. Run the installer. It installs for the current
user, into `%LOCALAPPDATA%\GeniusTransfer`, and adds a Start menu shortcut.

The installer is not code-signed. If SmartScreen warns that the app is
unrecognized, choose More info › Run anyway. When Windows Defender Firewall
asks, allow GeniusTransfer on private networks. If that Wi-Fi is set to
Public, switch it to Private in Settings › Network, or allow public
networks as well. Guests cannot connect until the firewall allows the app.

### Debian Linux

Debian 12, with a graphical desktop. Install the package that matches
`dpkg --print-architecture`:

```bash
sudo apt install ./GeniusTransfer-0.1.0-linux-amd64.deb
# On ARM64, use GeniusTransfer-0.1.0-linux-arm64.deb instead.
```

Launch GeniusTransfer from the applications menu, or run `geniustransfer`.
If a firewall is enabled, allow the port shown in the app from your local
network.

## How a transfer works

On the device that has the app:

1. **Send files.** Pick photos, videos, or other files, then choose
   **Show the code**.
2. **Receive files.** The other device picks the files in its browser.
   GeniusTransfer asks you to accept or decline before anything is saved.

On the other device, open the camera and point it at the code, then open
the link. On a computer, type the address shown under the code. Capital
letters and dashes are optional.

Keep GeniusTransfer open until the transfer finishes. On an iPhone, leaving
the app pauses transfers until you come back. A session also stops after
30 minutes with no activity.

Chrome on Android may ask you to keep a download of some file types, such
as HEIC, PDF, and ZIP. Photos and common video and audio types usually
download directly. Next to a HEIC photo, **Download as JPG** saves a JPEG
copy that opens in Gallery.

### Where received files go

| Host | Default folder |
|---|---|
| Android | Pictures, Movies, or Download › GeniusTransfer, by file type |
| iPhone | Files › On My iPhone › GeniusTransfer › Received |
| Mac, Windows, Linux | Downloads › GeniusTransfer |

Settings can point received files at another folder. On an iPhone, photos
and videos in the app’s Received folder can also be saved to Photos.

Sending the same name twice saves the second file as `name (1).ext`.

### No shared Wi-Fi

Both devices have to be on the same network. Guest, hotel, and café Wi-Fi
often keep devices from seeing each other.

On Android, when there is no usable network, the app can start its own
hotspot. The other phone scans a Wi-Fi code (or joins that network by name
and password), then scans a second code to open the page. That hotspot has
no internet. If the other phone asks whether to stay connected, stay
connected.

On an iPhone or a computer, join the other phone’s hotspot, then come back
to GeniusTransfer. The code updates on its own. An iPhone hotspot is
Settings › Personal Hotspot › Allow Others to Join. An Android hotspot is
under Settings › Connections or Network › Hotspot.

### Optional PIN

Settings › Privacy › **Ask for a PIN**. Each session shows a 4-digit PIN
next to the code. The browser asks for it before showing the page. After
5 wrong attempts the session locks.

## What stays on the devices

Each session serves a page and the chosen files from the host, on local
addresses only (private, link-local, and similar LAN ranges). The address
contains a fresh 128-bit token. A request without that token is refused.
The page does not load anything from the internet.

Uploads wait for Accept on the host. With the PIN turned on, the page stays
hidden until the PIN is entered. The host approves every batch, and a batch
nobody answers is dropped.

## Build from source

The release above was built with Flutter 3.47.7 (Dart 3.13). Install
[Flutter](https://docs.flutter.dev/get-started/install) and the platform
tools for the target you want, then build from `app/`.

### Android

```bash
tool/android_apk.sh release
```

This writes `app/build/app/outputs/flutter-apk/app-release.apk`. If a
device is connected with USB debugging, the script installs it. Otherwise
copy the APK to the phone and open it. `tool/android_apk.sh` with no
argument builds a debug APK.

### iPhone

A device install has to be signed with your own Apple ID. Open
`app/ios/Runner.xcodeproj` in Xcode, select the Runner target, and under
Signing & Capabilities choose your team. The project file currently names
one Personal Team; replace it with yours.

On the iPhone, turn on Settings › Privacy & Security › Developer Mode.
Then, with the phone plugged in or on the same Wi-Fi:

```bash
tool/ios_install.sh              # lists connected iPhones
tool/ios_install.sh "<device name or id>"
```

Release mode is required: a Flutter debug build on iOS only starts when
launched from Xcode or `flutter run`. After the first install, trust your
Apple ID under Settings › General › VPN & Device Management. A free
Personal Team profile expires after 7 days; run the script again.

### macOS

```bash
tool/macos_build.sh
```

The app is `app/build/macos/Build/Products/Release/GeniusTransfer.app`.
On another Mac, Gatekeeper blocks an ad-hoc signed app the first time:
open it, then allow it under System Settings › Privacy & Security.

### Windows

On a Windows 10 or 11 PC, install Flutter and Visual Studio 2022 with the
**Desktop development with C++** workload. In `app\`:

```
flutter build windows --release
```

The app is the folder `app\build\windows\x64\runner\Release\`
(`GeniusTransfer.exe`, its DLLs, and `data\`). Zip that folder to move it.
The `.exe` on the release page is a per-user installer of that same build.

### Debian Linux

On Debian 12, install Flutter 3.47.7 and the packages listed in
`tool/linux.Dockerfile`, then run `tool/linux_deb.sh`. The script builds a
`.deb` for the machine’s architecture under `app/build/releases/`.

`tool/linux.Dockerfile` is the same build environment. Build AMD64 and
ARM64 separately; each architecture needs its own build directory and
Flutter SDK.

## Tests

```bash
cd packages/transfer_server && dart test   # token gate, paths, Range, streaming, uploads
cd app && flutter test                     # network choice, approval sheet
```

A build made with `--dart-define=GT_SELFTEST=true` shares three generated
files on launch and logs `GT_SELFTEST_URL=…`. From another machine on the
same network:

```bash
python3 -I tool/selftest_check.py <GT_SELFTEST_URL>
```

The script downloads every file the way a guest browser would, and checks
sizes, checksums, Range requests, the token gate, and the response headers.

To check receiving, add `--dart-define=GT_SELFTEST_MODE=receive`. The app
opens a session that accepts every offer. Then:

```bash
python3 -I tool/selftest_upload.py <GT_SELFTEST_URL>
```

It uploads five files, three the way the page’s script does and two through
the plain form used when JavaScript is unavailable. The app checks each
file and logs `GT_SELFTEST_RECEIVED=<name>|<size>|ok` and
`GT_SELFTEST_SAVED=<name>|<size>|<folder>|<path>`.

## Repository layout

```
app/                       Flutter app (iOS, Android, macOS, Windows, Linux)
  lib/                     UI, session logic, network detection
  android/…/kotlin/        File pickers, saving, sharing, hotspot
  ios/Runner/AppDelegate.swift   Background time to finish downloads
packages/transfer_server/  HTTP server and guest page (pure Dart)
tool/                      Build scripts and the end-to-end checkers
```

Platform research and the design decisions behind the app are in
[PLAN.md](PLAN.md).

## License

[MIT](LICENSE) © swissmarley
