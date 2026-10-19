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
