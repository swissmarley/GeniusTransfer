# Milestone 1: device checklist

Milestone 1 is **host → guest download over the same network**. These checks
need real devices and a second person's phone; I could not do them from the
Mac. Write the result next to each item (✅, ❌ + what happened, or the value
asked for). Tell me the results and I fold them into the app, the guest page
text and PLAN.md.

Devices: iPhone (iOS 26.x), new Samsung tablet, old Android phone, this Mac
(and a Windows PC if you have one). Everything below is on **one Wi-Fi
network**, mobile data as it normally is.

Prepare a few files on each host: a photo (HEIC on iPhone, JPG on Android),
a video of **at least 1 GB**, a PDF, and a ZIP or DOCX.

## A. Install

| # | Check | Result |
|---|---|---|
| A1 | iPhone: `tool/ios_install.sh "<iPhone name>"` installs; app opens from the home screen | |
| A2 | Samsung tablet: the APK installs and opens | |
| A3 | Old Android phone (as a host, optional): APK installs (needs Android 8+) | |
| A4 | Mac: `tool/macos_build.sh`, app opens | |

## B. iPhone host → Samsung tablet / old Android phone guest

| # | Check | Result |
|---|---|---|
| B1 | Home shows "Wi-Fi ready · <address>" | |
| B2 | Photos & videos: the picked HEIC keeps its `.heic` name; a JPG's size matches what Photos shows (Photos › ⓘ) | |
| B3 | Guest **stock camera** recognizes the QR code. Which app opens the page (Chrome, Samsung Internet, a Google/Lens in-app view)? | |
| B4 | Page loads. Time from scan to page visible (seconds) | |
| B5 | HEIC / PDF / ZIP: does Chrome show "File can't be downloaded securely"? Does **Keep** save it? | |
| B6 | JPG / MP4: no warning? | |
| B7 | Where did the files go? (Files app › Downloads? Gallery/Photos? Samsung "My Files"?) Is the page's text right? | |
| B8 | 1 GB video downloads completely and plays. Duration (min:s) | |
| B9 | Host screen shows the guest ("Connected: Android · Chrome"), progress, ✓ per file | |
| B10 | Old Android phone: can its camera scan QR codes at all? Chrome version (⋮ › Settings › About)? Page layout OK? | |

## C. Samsung tablet host → iPhone guest

| # | Check | Result |
|---|---|---|
| C1 | First "Send files" asks for notification permission (Android 13+); notification "Sharing files" with **Stop** appears during the session | |
| C2 | iPhone Camera shows the link banner; tapping it opens Safari | |
| C3 | Any delay or warning before the page shows (Safari trying HTTPS first)? | |
| C4 | Safari asks "Do you want to download …?" → Download. Where is the file? (Files › Downloads in **iCloud Drive** or **On My iPhone**?) Also with mobile data **off** | |
| C5 | A photo and a video can be saved to Photos from there (Files › Share › Save Image/Video) | |
| C6 | 1 GB video downloads completely. Duration | |
| C7 | Tablet: switch to another app for 2 minutes during a big download; does it keep going? | |
| C8 | Notification **Stop** ends the session; the guest page then shows the red "Can't reach" banner | |

## D. Mac host → phones; phone host → computer browser

| # | Check | Result |
|---|---|---|
| D1 | Mac: first guest connection: did macOS ask to allow incoming connections? | |
| D2 | iPhone and tablet scan the QR code from the Mac screen and download | |
| D3 | On the Mac (or a PC), type the address shown under a phone host's QR code into a browser. Lowercase, with or without dashes, works | |
| D4 | Windows PC host (if available): firewall prompt appeared? Allowed on private networks? Phones can download | |

## E. Edge cases

| # | Check | Result |
|---|---|---|
| E1 | iPhone host: start a big download, press Home. Does it finish if under ~30 s? Back in the app: "Paused… Ready again" note, guest's red banner disappears, download can be retried | |
| E2 | iOS Local Network: Settings › Privacy & Security › Local Network. Is GeniusTransfer listed? Was there ever a prompt? Guests still connect? | |
| E3 | Host switches Wi-Fi network: the QR code changes to the new address | |
| E4 | Guest Wi-Fi / café network (client isolation): page never loads; after 30 s the host shows "Not opening on the other phone?" | |
| E5 | Guest joins a Wi-Fi **without internet** with mobile data **on**: does the page load? (Android may route through mobile data) | |
| E6 | Leave a session idle 30 minutes: it stops by itself with a message | |
| E7 | Scan an **old** QR code after stopping: guest sees "This link has expired" | |
