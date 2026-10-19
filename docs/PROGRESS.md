# Progress log

Running log of the overnight build (started 2026-10-19), newest first.
Design and decisions: [PLAN.md](../PLAN.md). Device checks still to do:
[M1-checklist.md](M1-checklist.md) and, when it exists, [TESTING.md](../TESTING.md).

Conventions for this run:

- Milestones in order: M2 upload → M3 no shared network → M4 polish → M5
  TESTING.md. Each ends with tests and builds, a commit, and a push to
  `origin/main` (private repo `swissmarley/GeniusTransfer`).
- Nothing is called "working on <platform>" unless it ran there. Each entry
  says what was verified, and where: unit tests, iOS Simulator, macOS app,
  real iPhone, real Android device.
- Decisions taken without you are listed under each milestone so you can
  overrule them in the morning.

## Morning summary (2026-10-20)

All milestones are built, committed and pushed to `origin/main`:

- **M2:** receiving, with approval, progress and a default or chosen save
  folder.
- **M3:** no shared network: an Android hotspot with a Wi-Fi QR code, and
  guides for iPhone and computers.
- **M4:** Android share sheet, optional PIN, saving to Photos on iPhone
  guests, HEIC→JPG copies, actions on received files.
- **M5:** TESTING.md.

**Verified on this Mac:** the server tests (128); the end-to-end
self-tests for sending and receiving on the iOS Simulator and the macOS
app; the APK, iOS (Simulator and device) and macOS builds.

**Not verified:** nothing has run on a real phone or tablet tonight. The
iPhone was locked, so the install failed (the build is fine). The Samsung
tablet was not connected.

Start here:

1. Unlock the iPhone and run `tool/ios_install.sh "iPhone Marley"`.
2. Connect the tablet and run `tool/android_apk.sh`.
3. TESTING.md › part 1, then rows F1–F5 and G1–G3.

Decisions waiting for you: drag and drop on computers (needs the
third-party package `desktop_drop`), plus the "Decisions taken without
you" listed under each milestone below.

## M5: TESTING.md

[TESTING.md](../TESTING.md) has three parts:

1. Quick self-tests per host, run from the Mac.
2. Device checklists for receiving, the hotspot, PIN, share sheet and
   HEIC; the download checks stay in [M1-checklist.md](M1-checklist.md).
3. The 5-person field test: the exact sentence to say, stopwatch points,
   failure-step codes and a recording sheet. It passes if 4 of 5 people
   manage both directions.

## M4: polish

What exists:

- **Android share sheet:** "Share › GeniusTransfer" from Photos, Files or
  any app opens Send with those files already chosen, without copies. If a
  session is running, the shared files wait until you are back on the Home
  screen.
- **Optional PIN** (Settings › Privacy › Ask for a PIN, off by default).
  Each session gets a random 4-digit PIN, shown big under the code. The
  guest's browser asks for it before showing anything; the form works
  without JavaScript. Wrong attempts show on the host. After 5 wrong PINs
  nobody new can join; guests already in can continue.
- **iPhone guests and Photos:** next to Download, photos and videos get an
  **Open** link, which shows them in Safari, plus a one-line hint on saving
  to Photos from there. (Safari downloads always go to Files.)
- **HEIC → JPG:** when an iPhone or Mac sends HEIC photos, Android and
  Windows guests also get **Download as JPG**. The copy is made on first
  use, keeps date, orientation and location, and is deleted when the
  session ends.
- **Received files:** Open (Android), share sheet (iPhone), Show in
  Finder/folder (computers), next to Save to Photos on iPhone.

Verified:

- Server: 128 tests pass, including the PIN (cookie scope, countdown,
  lock-out, constant-time check, receive mode), the inline route and the
  JPG route (made once, cached, failures, released on stop).
- HEIC→JPG: the Swift conversion code, run on a real 6016×6016 HEIC from
  macOS, produced a valid JPEG of the same size with its EXIF data.
- macOS download self-test still passes; with an Android browser
  identity, the page shows the JPG link.
- APK, iOS Simulator and macOS builds pass; 16 app tests pass.
- **Not checked on devices:** the share sheet intake, opening received
  files, the iOS share sheet, typing a PIN on a real phone.

Waiting for you:

- **Drag and drop onto the window (Mac/Windows)** needs a package that is
  not from the Flutter team (`desktop_drop`). Per your rule I did not add
  it. Say yes and I will add it.
- **iPhone install:** the release build succeeds, but installing failed
  because the phone was locked overnight. With the phone unlocked, run
  `tool/ios_install.sh "iPhone Marley"`.

## M3: no shared network

What exists:

- **Android host, no Wi-Fi:** Send or Receive asks "No Wi-Fi here" and
  offers **Start a hotspot on this phone**. It creates a local-only
  hotspot: a Wi-Fi network just for this transfer, without sharing mobile
  data. The code then comes in two steps:
  1. A "join this Wi-Fi" QR code, with the network name and password
     written underneath. The stock camera on iPhone and Android joins it
     with one tap.
  2. "Joined? Show the second code": the usual page code, now with this
     phone's hotspot address.
  The hotspot also appears in the "Not opening?" help after 30 seconds,
  for Wi-Fi networks that keep devices apart (hotels, guest Wi-Fi). It is
  turned off with the session.
- Android asks once for the permission it needs: Nearby Wi-Fi devices on
  Android 13+, Location on Android 8–12. On 8–12 Location must also be on;
  the app says so and opens the setting.
- **iPhone and computers** (they cannot create a hotspot from an app):
  "Other ways to connect" explains, step by step, how to use the other
  phone's hotspot. On an iPhone it also explains this iPhone's Personal
  Hotspot. You can save its name and password once, and the guide then
  shows a QR code the other phone scans to join. The session screen
  notices the new network by itself, and the code updates.

Verified:

- Unit tests for the Wi-Fi QR text, including escaping of `\ ; , " :` and
  non-ASCII names. Widget tests for step 1 (code content, name, password,
  Next) and for the computer guide.
- The APK, iOS Simulator and macOS builds pass.
- **Not run on an Android device**: the hotspot itself (permission
  prompts, the network name and password, its address) needs the Samsung
  tablet. It is the first thing to try in the morning (see TESTING.md).

Decisions taken without you:

- The hotspot is "local-only": it never shares this phone's mobile data,
  and Android chooses its name and password. Android does not let apps
  set them.
- The guest's phone may say the Wi-Fi has no internet. The page text and
  step 1 say to stay connected.

## M2b: receiving in the app

What exists:

- Home › **Receive files** opens a receiving session with the same QR code
  and address as sending. The guest page becomes "Send files to the other
  device".
- **Approval:** each batch shows a sheet with the device ("iPhone ·
  Safari"), the files and the total size, and Decline / Accept. Nothing is
  kept unless you accept. An unanswered offer expires after 10 minutes and
  the sheet closes by itself.
- **Progress** shows in the status line. Received files are listed with
  where they went.
- **Where files go by default:**
  - iPhone: Files › On My iPhone › GeniusTransfer › Received. Photos and
    videos also get a **Save to Photos** button, which keeps the original
    (HEIC stays HEIC).
  - Android: Pictures, Movies or Download › GeniusTransfer, depending on
    the file type, so photos show up in the gallery.
  - Mac: ~/Downloads/GeniusTransfer (with Show in Finder).
  - Windows: Downloads\GeniusTransfer (with Show in folder).
- **Settings** (gear on the Home screen): choose another folder for
  received files, or go back to the default. If the chosen folder
  disappears or access is revoked, files go to the default folder and the
  session says so.
- Same-name files are never overwritten: "a.jpg", "a (1).jpg"…

Verified:

- iOS Simulator (iPhone 17, iOS 27), receive self-test build +
  `tool/selftest_upload.py`: 5 files (1 kB to 50 MB, via the page's script
  and via the no-script form) arrived with correct content in
  `Documents/Received`; a duplicate became "selftest-small (1).txt".
- macOS app (release, sandboxed) with the merged entitlements: the same
  5 files arrived intact in the real ~/Downloads/GeniusTransfer, shown as
  "~/Downloads/GeniusTransfer". The test files were deleted afterwards.
- `flutter analyze` clean; app tests include the approval sheet (Accept,
  Decline, long lists, closing when the offer expires).
- Android: the debug APK builds with the new Kotlin (MediaStore, folder
  picker). **Not run on a device yet**; the Samsung tablet was not
  connected.
- Not verified anywhere yet: the folder pickers (iOS, Android, macOS) and
  Save to Photos, which need a person to tap through system screens. They
  are on the device checklist.

Decisions taken without you:

- Photos and videos on Android go to Pictures/Movies › GeniusTransfer, not
  Download, so they appear in the gallery like camera photos.
- On iPhone, received photos are not added to Photos automatically (that
  needs a permission prompt). They stay in Files, with a one-tap Save to
  Photos button.
- Files arrive in a private staging folder first and are moved after they
  are complete, so a cut-off upload never leaves half a file in your
  folders.

## M2a: server side of uploads (guest → host)

What exists (`packages/transfer_server`):

- Receive mode: `TransferServer(mode: SessionMode.receive, receiveOptions:
  ReceiveOptions(stagingDir: …))`. The guest page becomes "Send files to the
  other device".
- With JavaScript: the page sends an offer (names and sizes), waits for the
  host to accept (long poll), then uploads file by file with a progress bar.
  The host gets `UploadOffered` and calls `approveUpload` / `declineUpload`.
- Without JavaScript: the plain form posts everything at once. The files
  wait in quarantine until the host accepts (moved into place) or declines
  (deleted). The guest sees a self-refreshing "waiting" page.
- Limits: one undecided offer at a time; at most 500 files and 20 GB per
  batch; refused if it would leave less than 1 GB free; unanswered offers
  expire after 10 minutes.
- File names are sanitized (last path segment only; no control, bidi or
  Windows-forbidden characters; no hidden files or reserved names; at most
  200 bytes) and numbered on collision: "a.jpg", "a (1).jpg". Every write
  path is checked to stay inside the batch folder.
- Stopping the session deletes partial files and quarantine; finished files
  stay.

Verified:

- `dart analyze` clean; 113 server tests pass (33 new: sanitizer, approval
  flow, long poll, limits, malformed offers, cross-site Origin, size
  mismatch, chunked bodies, cut-off uploads and retry, cleanup on stop,
  multipart quarantine).
- Headless Chrome 155 on the Mac at phone size, against a real server: the
  JavaScript flow and the no-JavaScript form both delivered a 3 MB file
  byte-identical, and the UTF-8 name "notes é.txt" survived.
- Not yet on a real phone browser (that comes with the app side, M2b).

Decisions taken without you:

- A refused upload says why: too many files, too large, not enough space,
  or the other device is still deciding about an earlier offer.
- Cross-site POSTs are refused (Origin check). `Origin: null` is allowed,
  because our `no-referrer` policy makes browsers send it for same-page
  forms.

## 2026-10-19 evening

- Private repo created and pushed: https://github.com/swissmarley/GeniusTransfer
- Tracked files checked: no build output, local paths, personal data or
  tokens. The template `app/README.md` was replaced by a pointer.
- Samsung tablet not connected yet (adb shows no device); will install and
  self-test it when it appears.
- Windows: built on your Windows PC later (README › Windows).
