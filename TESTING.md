# Testing GeniusTransfer

There are three parts, best done in this order:

1. **Quick self-tests** (10 minutes). Each host app checks itself against
   this Mac, without anyone tapping through screens.
2. **Device checklists**, one row per check, for the things only a person
   with real devices can see. Downloads (Milestone 1) are in
   [docs/M1-checklist.md](docs/M1-checklist.md); receiving, the hotspot
   and the rest are below.
3. **The field test with 5 people.** It answers the real question: can
   someone who has never seen the app move a file in both directions?

Write results straight into the tables (✅, or ❌ with what happened) and
send them to me. I fold them into the app, the guest page text and PLAN.md.

---

## 1. Quick self-tests

Run these on the Mac, with the device on the same Wi-Fi.

| Host | Build and start | Then, on the Mac |
|---|---|---|
| Mac, sending | `cd app && flutter build macos --release --dart-define=GT_SELFTEST=true`, then start `app/build/macos/Build/Products/Release/GeniusTransfer.app` from the Terminal so you can see `GT_SELFTEST_URL=…` | `python3 -I tool/selftest_check.py <url>` |
| Mac, receiving | same, adding `--dart-define=GT_SELFTEST_MODE=receive` | `python3 -I tool/selftest_upload.py <url>`. Files land in ~/Downloads/GeniusTransfer; delete the `selftest-*` files afterwards |
| iPhone | `flutter run --release -d "iPhone Marley" --dart-define=GT_SELFTEST=true` (add `--dart-define=GT_SELFTEST_MODE=receive` for receiving). The URL appears in the `flutter run` output | the matching script, as above |
| Android tablet | connect with USB debugging, then `flutter run --release --dart-define=GT_SELFTEST=true` (add `--dart-define=GT_SELFTEST_MODE=receive` for receiving) | the matching script, as above |

Each script prints PASS/FAIL per check and ends with "All checks passed".
For receiving, the app also logs one `GT_SELFTEST_RECEIVED=<name>|<size>|ok`
line per file, and the place it saved it (`GT_SELFTEST_SAVED=…`). After a
self-test, install the normal build again (`tool/ios_install.sh`,
`tool/android_apk.sh`).

---

## 2. Device checklists

Devices: iPhone (iOS 26), Samsung tablet, the old Android phone if you
like, this Mac, a Windows PC if you have one. Unless a row says otherwise:
one Wi-Fi network, mobile data as usual.

### F. Receiving (guest → host)

On the host: Home › **Receive files**. On the guest: scan the code, then
**Choose files** › **Send**.

| # | Check | Result |
|---|---|---|
| F1 | iPhone guest → tablet host: in Safari, "Choose files" offers Photo Library, Take Photo, Choose Files. Pick 2 photos and a video | |
| F2 | The tablet shows "iPhone · Safari wants to send you 3 files" with sizes; **Accept** starts the upload; each file shows a progress bar and "Sent" on the iPhone | |
| F3 | Where did they go? Gallery › GeniusTransfer (photos and video)? Check that the photo is **HEIC or JPG** (Safari may convert), and its size and date. Write both down | |
| F4 | **Decline** on the host: the iPhone says "The other device declined these files", and nothing was saved | |
| F5 | Tablet guest → iPhone host: Chrome's file chooser, 2 photos + a PDF. iPhone shows the sheet; after Accept the files are in Files › On My iPhone › GeniusTransfer › Received | |
| F6 | iPhone host: **Save to Photos** on a received photo and a video asks for permission once, then the original is in Photos (HEIC stays HEIC) | |
| F7 | iPhone host: the share icon on a received PDF opens the share sheet (open in Books, AirDrop…) | |
| F8 | Tablet host: **Open** on a received photo and PDF opens Gallery / a PDF viewer | |
| F9 | Phone → Mac: received files are in ~/Downloads/GeniusTransfer; Show in Finder works | |
| F10 | A 1 GB+ video, phone → Mac, and phone → phone. Duration (min:s); the host's progress line follows | |
| F11 | Send the same photo twice: the second is saved as "name (1).ext", nothing overwritten | |
| F12 | Settings › **Choose a folder…** on each host (tablet: a folder on the SD card or Download; iPhone: a folder in Files; Mac: any folder). Received files go there. Then delete or rename that folder: the next files go to the default folder and the session says so | |
| F13 | Don't answer an offer for 10 minutes: the sheet closes, the guest page says nobody answered | |
| F14 | Old browser (the old Android phone): the page works; if its browser has no JavaScript upload support, the plain form still sends and shows "Waiting for the other device to accept…" | |

### G. No shared network (hotspot)

Mobile data **off** on both phones, Wi-Fi on but not connected to any network.

| # | Check | Result |
|---|---|---|
| G1 | Tablet host, Send: "No Wi-Fi here" dialog › **Start a hotspot on this phone**. Which permission prompt appears (Nearby devices, or Location)? | |
| G2 | Step 1 shows a Wi-Fi code with name and password. The **iPhone camera** joins it with one tap ("Join network"). Any "no internet" warning? | |
| G3 | **Joined? Show the second code** › the iPhone scans the page code and downloads a photo. Time for the whole thing, from the dialog to the photo saved (min:s) | |
| G4 | Same with Receive: iPhone sends 2 photos to the tablet over the hotspot | |
| G5 | Old Android phone as guest: does its camera (or Google Lens) join the Wi-Fi from the code? | |
| G6 | Android 8–12 with Location off: the app says to turn Location on, and **Open Location settings** works | |
| G7 | Stop the session: the hotspot disappears from the iPhone's Wi-Fi list | |
| G8 | iPhone host without Wi-Fi: "Other ways to connect" › use the tablet's hotspot (tablet: Settings › Connections › Mobile Hotspot). After joining it in iPhone Settings, the code appears by itself | |
| G9 | iPhone host › Personal Hotspot route: save the hotspot name and password in the guide. The tablet scans that code, joins, then scans the page code | |
| G10 | Mac host, no Wi-Fi: join the tablet's hotspot, then the code appears; the tablet downloads | |

### H. PIN, share sheet, HEIC

| # | Check | Result |
|---|---|---|
| H1 | Settings › Privacy › **Ask for a PIN** on. A session shows a 4-digit PIN under the code. The guest's browser asks for it first; the right PIN shows the page | |
| H2 | 5 wrong PINs: the host shows "Locked after 5 wrong PINs"; another phone can't get in even with the right PIN; the first guest keeps going | |
| H3 | Tablet: in Gallery, select 3 photos › Share › **GeniusTransfer**: Send opens with them; Show the code works | |
| H4 | iPhone host sends HEIC photos to the tablet: next to Download there is **Download as JPG**. The JPG opens in Gallery, right way up, with the original date | |
| H5 | iPhone guest: next to Download, photos and videos have **Open**. Open › touch and hold the photo › Save to Photos works; for a video: Share › Save Video | |
| H6 | Windows PC browser downloading a HEIC from the iPhone: the JPG link is there and the JPG opens | |

---

## 3. Field test with 5 people

**Goal:** people who have never seen the app manage both directions, with
no help beyond one sentence.

**Pass:** at least **4 of 5** people succeed **in both directions**.
There is no "Google Drive" comparison; the point is whether it works at
all without the internet, not whether it beats the cloud.

### Setup (once)

- Host: the iPhone for 2–3 people, the Samsung tablet for the others.
- Each person uses **their own phone** as the guest, with **mobile data
  off** (Control Center / quick settings) and Wi-Fi on. Mix iPhones and
  Androids if you can.
- Host and guests on the same Wi-Fi network (your home Wi-Fi), except
  person 5: no shared Wi-Fi, so the tablet makes a hotspot (the G rows).
- On the host: 3 photos and 1 short video (200–500 MB) ready to send.
- A stopwatch (the host's Clock app works) and this sheet.

### Script (say exactly this, nothing more)

1. Host: tap **Send files**, choose 1 photo and the video, **Show the
   code**. Then say: **"Scan this with your camera."**
   Start the stopwatch. Stop it when both files are saved on their phone.
   If they ask a question, answer only with what is on their screen ("What
   does it say?").
2. Host: **Receive files**. Say: **"Now send me two photos. Scan this
   with your camera."** Start the stopwatch; stop it when both files are
   saved on the host.
3. Ask: **"Where are the files now?"** Can they find them (Photos, Files,
   Downloads)?

Stop a direction after 5 minutes, or when the person gives up. Write down
**the step where it went wrong**, using these codes:

| Code | Step |
|---|---|
| S1 | Camera did not recognize the code / no link banner |
| S2 | Banner tapped, page did not load (spinning, "can't reach") |
| S3 | Page loaded, did not understand what to tap |
| S4 | Download/upload started, stopped or failed |
| S5 | Files arrived, but they could not find them |
| S6 | Host side problem (approval missed, app left, screen locked) |
| S7 | Hotspot: did not manage to join the Wi-Fi code |

### Recording sheet

| Person | Guest phone (model, OS) | Host | Network | Send to them: time / ✅❌ / step | Receive from them: time / ✅❌ / step | Found the files? | Their words, verbatim |
|---|---|---|---|---|---|---|---|
| 1 | | | Wi-Fi | | | | |
| 2 | | | Wi-Fi | | | | |
| 3 | | | Wi-Fi | | | | |
| 4 | | | Wi-Fi | | | | |
| 5 | | Tablet | Hotspot | | | | |

**Result:** ___ of 5 succeeded in both directions. **Pass if 4 or more.**

Afterwards, also note anything people said out loud while doing it ("where
is it?", "is this safe?"). Those quotes are the most useful input for the
next version of the page text.
