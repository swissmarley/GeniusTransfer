# GeniusTransfer

Move files between an iPhone, an Android phone or a computer **without the
internet and without the cloud**, when **only one of the devices has the
app**. The other device scans a QR code with its stock camera (or types a
short address) and uses its normal web browser.

- Design, research and decisions: [PLAN.md](PLAN.md)
- How to test, including the 5-person field test: [TESTING.md](TESTING.md)
- Overnight progress, with what was verified where: [docs/PROGRESS.md](docs/PROGRESS.md)
- What to test on real devices for Milestone 1: [docs/M1-checklist.md](docs/M1-checklist.md)

## Status

| Milestone | State |
|---|---|
| 0. Research and plan | Done |
| 1. Host → guest download, same network (iOS, Android, macOS, Windows hosts) | Built; checked on the iOS Simulator and on macOS. Real-device checks pending, see the checklist |
| 2. Guest → host upload (approval, progress, default or chosen save folder) | Built; checked on the iOS Simulator and macOS, Android built only. Real-device checks pending |
| 3. No shared network: Android hotspot with a Wi-Fi QR code; guides for iPhone and computers | Built; UI checked in tests. The Android hotspot has not run on a device yet |
| 4. Polish: Android share sheet, optional PIN, iPhone guests save to Photos, HEIC→JPG copies, actions on received files | Built; server parts tested, HEIC→JPG checked on a real HEIC, macOS self-test passes. Device checks pending |
| 5. Field-test script and device checklists | Done: [TESTING.md](TESTING.md) |

## Repository layout

```
app/                       Flutter app (iOS, Android, macOS, Windows hosts)
  lib/                     UI, session logic, network detection
  android/…/kotlin/        Pickers that hand over file descriptors, sharing service
  ios/Runner/AppDelegate.swift   Background time to finish downloads
packages/transfer_server/  The HTTP server and guest page (pure Dart, tested on the Mac)
tool/                      Build/install scripts and the end-to-end self-test checker
```

## Build and run

The toolchain on the development Mac is described in PLAN.md §8.1 (Flutter
3.47, JDK 17, Android SDK under `/opt/homebrew/share/android-commandlinetools`,
Xcode 27).

### iPhone (free Apple ID, reinstall weekly)

One-time setup:

1. Xcode › Settings › Accounts: your Apple ID is signed in (Personal Team
   `SD8W7DS5GY` is already set in the project).
2. On the iPhone: Settings › Privacy & Security › **Developer Mode** on.
3. After the first install: Settings › General › **VPN & Device Management**
   › your Apple ID › **Trust**.

Every week (the free profile expires after 7 days), with the iPhone plugged
in or on the same Wi-Fi:

```bash
tool/ios_install.sh "iPhone Marley"
```

### Android (sideloaded APK)

```bash
tool/android_apk.sh
```

This builds `app/build/app/outputs/flutter-apk/app-debug.apk` and installs it
on a device connected with USB debugging. To install by hand, copy the APK to
the phone or tablet and open it (allow "Install unknown apps" once). For
field tests, `tool/android_apk.sh release` gives a smaller, faster APK.

### macOS

```bash
tool/macos_build.sh
```

The first time a guest connects, macOS may ask whether GeniusTransfer may
accept incoming connections: choose **Allow**.

### Windows

Flutter cannot build Windows apps on a Mac. On a Windows 10/11 PC:

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop)
   and Visual Studio 2022 with the **Desktop development with C++** workload.
2. Copy this repository to the PC, then in `app\`:
   ```
   flutter build windows --release
   ```
3. The app is the whole folder `app\build\windows\x64\runner\Release\`
   (`GeniusTransfer.exe` plus its DLLs and `data\`); zip that folder to move it.
4. Windows SmartScreen may warn that the app is unrecognized (it is not
   code-signed): **More info › Run anyway**.
5. When Windows Defender Firewall asks, **allow GeniusTransfer on private
   networks**. Guests cannot connect otherwise. If your Wi-Fi is set to a
   *Public* network, either switch it to *Private* in Settings › Network or
   also allow public networks.

## Tests

```bash
cd packages/transfer_server && dart test   # server: token gate, traversal, Range, streaming, memory, uploads
cd app && flutter test                     # app: network interface ranking, approval sheet
```

### End-to-end self-test from the Mac

A build made with `--dart-define=GT_SELFTEST=true` shares three generated
files on launch and logs `GT_SELFTEST_URL=…`. Then, from the Mac on the same
network:

```bash
python3 -I tool/selftest_check.py <GT_SELFTEST_URL>
```

It downloads every file as a guest browser would and checks sizes,
checksums, Range requests, the token gate and the security headers.

To check receiving, build with
`--dart-define=GT_SELFTEST=true --dart-define=GT_SELFTEST_MODE=receive`.
The app opens a receiving session that accepts every offer. Then:

```bash
python3 -I tool/selftest_upload.py <GT_SELFTEST_URL>
```

It uploads five files as a guest browser would: three the way the page's
script does, and two through the plain form used without JavaScript. The
app checks each file's content and logs `GT_SELFTEST_RECEIVED=<name>|<size>|ok`
and `GT_SELFTEST_SAVED=<name>|<size>|<folder>|<path>`.
