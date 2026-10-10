# GeniusTransfer: Plan (Milestone 0)

Status: **draft for your approval.** No app code has been written yet.
Date of research: 2026-10-11. Versions current at that date: iOS 27 (test iPhones on 26.5 and 26.6), Chrome 154, Flutter 3.47.7. Android 17's behavior changes are documented.

How sure each claim is:

- **[V]**: verified in primary sources: official docs, or the platform's or browser's own source code. I re-checked the most important ones myself.
- **[R]**: reported in forums or blogs, or Apple staff forum posts. Plausible but not authoritative.
- **[T]**: unknown until tested on a real device. Each [T] becomes an item in the milestone test checklists.

Source links are in [Appendix A](#appendix-a-sources).

---

## 1. Summary

1. **Build it standalone in Flutter. Don't fork LocalSend.** LocalSend's web server is written in Rust, and its browser-share security model doesn't match ours (details in §2). No blocker to Flutter was found.
2. **Six research findings change the design:**
   - **Chrome on Android warns on many plain-HTTP downloads, and private IPs are not exempt [V].** Chrome shows a "File can't be downloaded securely" dialog with *Keep* / *Discard* for every file type outside a safe list. **JPG, PNG, MP4, MOV and MP3 pass without a warning. HEIC, PDF, ZIP, DOCX and APK get the dialog.**
     - The guest page will say "tap *Keep*" where it applies.
     - We avoid ZIP for Android guests.
   - **An iPhone guest uploading from Photos in Safari sends converted copies, not originals [V].** WebKit forces the picker into *Compatible* mode, which turns HEIC into JPEG and HEVC into H.264, and it allows downscaling. Files picked through *Choose File* (the Files app) arrive byte for byte.
   - **The iOS Local Network permission isn't triggered by our server at all [V].** Apple's TN3179 says listening for and accepting incoming TCP needs no permission. We'll still add `NSLocalNetworkUsageDescription`, but expect no prompt (§3.5).
   - **iPhone Personal Hotspot needs mobile data turned on [V], and the field test turns mobile data off.**
     - Clients of iOS 18+ hotspots may also get only an IPv6 or CLAT address [R], so the hotspot iPhone's `172.20.10.1` may be unreachable [T].
     - So when the iPhone is the host and there's no shared network, the main route is: **the guest phone turns on its hotspot and the host iPhone joins it.**
   - **The iOS server dies in the background [V].** The listener is closed when the app leaves the foreground and reopened when it returns. The UI says so plainly.
   - **An Android host needs a foreground service [V].**
     - Without one, Android freezes the app about 70 seconds after the user switches away, and on Android 15+ it closes the connections that are still open.
     - Decision: a minimal native `connectedDevice` foreground service whenever a session is active, from M1 (§3.2).
     - Also, **Android 17 makes accepting incoming connections a runtime permission** for apps that target SDK 37 [V]. We target SDK 36 for now and plan for the permission (§3.2).
3. **Things you need to decide are in §10**, with a recommendation for each. The biggest ones:
   - where received files are saved;
   - whether to offer "Download all as ZIP";
   - whether I may install Flutter and the Android tools on this Mac with Homebrew.

---

## 2. LocalSend: fork, contribute, or build standalone?

I read LocalSend at commit `14f3a874` (2026-10-10). The latest release is v1.18.2.

| Question | Finding |
|---|---|
| License | **Apache-2.0** (root `LICENSE`). Cargokit is MIT or Apache-2.0. The logos are brand assets, so don't reuse them. [V] |
| Server technology | **Rust** (hyper + tokio + rustls), called from Dart through flutter_rust_bridge. The web code is `packages/core/src/http/server/web.rs`. [V] |
| HTTP or HTTPS | The share page uses plain HTTP by default. An "Encryption" checkbox switches to HTTPS with a self-signed certificate, which makes the browser show a certificate warning. [V] |
| Access control | **No secret in the URL.** The URL is `http://<ip>:53317/`. A browser's session ID is its IP address (`web.rs:342`). There's an optional PIN, carried in the QR code as `?pin=`, and the host approves each browser by hand. [V] |
| Downloads | Streamed from disk, and Android `content://` files are passed as file descriptors. **No HTTP Range support.** The header uses `filename=` only, without `filename*=`. [V] |
| Guest page | Static HTML with inline CSS and JS, and no external requests. **Downloads need JavaScript:** without it the page shows only a `<noscript>` message. Only about 11 strings are translated. [V] |
| Browser upload | Yes, since 1.18.0 (2026-08-10). It uses XHR to send the raw file body, so JS is required. **Download mode and upload mode are mutually exclusive** (`web.rs:99`). [V] |
| Hotspot | None. There are open requests (#2144, #2316, #2524). An unreviewed PR with about 5,800 added lines (#3369) adds an Android local-only hotspot plus an iOS App Clip. [V] |
| Codebase | About 42k lines of Dart, about 31k lines of Rust and 513 Rust crates. Flutter is pinned through fvm, and it needs Rust, the NDK and flutter_rust_bridge code generation. Desktop platforms are included. [V] |

**Recommendation: build standalone.** Reasons:

1. **Build weight.** A fork brings Rust toolchains, the Android NDK, FRB code generation and desktop-only dependencies. That's a lot to carry for a two-platform app that has to be rebuilt and reinstalled every week with a free Apple ID.
2. **The security model would have to change, not just the feature set.**
   - We need a 128-bit token in the path, so that a request without it is rejected.
   - LocalSend identifies browsers by IP address and serves its page at `/` to anyone on the network.
   - Our requirements also include no-JS downloads, Range support, and a single "scan this" flow. Each of those is a change across its server, its page and its UX.
3. **Contributing upstream would be slow and uncertain.** The project has 872 open issues and 131 open PRs, and the existing hotspot PR has no review. Our whole product would be a side mode in their app.
4. **What we take from LocalSend** is ideas, not code:
   - per-IP connection limits;
   - limited PIN attempts;
   - restarting the server when an iOS app resumes;
   - passing Android `content://` files as file descriptors.
   
   If we ever copy any of its HTML, Apache-2.0 allows it with attribution in a NOTICE file. I don't expect to, because our page has to work without JS first.
5. **Possible later contribution:** once the field test has proved the approach, we could post findings on LocalSend #3369 and #3449.

**Other prior art:**

- **Sharik** (MIT, Flutter, uses `dart:io` like our plan): unmaintained since 2022. No authentication, no upload, no Range, and a weak path check. Useful for reference only.
- **VLC "Sharing via Wi-Fi" / "Remote access"** (GPL): actively maintained, and both support browser upload. GPL code isn't something to copy into this app; they're useful only as behavioral references.

---

## 3. Platform constraints (verified)

### 3.1 Local HTTP server on iOS

- **The server only runs while the app is in the foreground. There is no supported way to keep it serving in the background** [V, Apple DTS].
- **What suspension does:**
  - A suspended app runs no code.
  - The kernel may take back the listening socket. After resuming, the listener can stay deaf without reporting any error.
  - Locking the screen while suspended is the known way to make this happen [V, TN2277].
- **Apple's guidance:** close the listener when the app goes to the background and reopen it when it comes back.
- **Finishing a transfer in the background:** `beginBackgroundTask` gives roughly 30 seconds, and that time isn't guaranteed [V].
  - iOS 26 added `BGContinuedProcessingTask`, which might let a large transfer that's already running finish in the background, with system progress UI [V that the API exists; T whether it works for us].
  - This is optional, for M4 or later.
- **Design:**
  - Keep the screen awake during a session.
  - When the app goes to the background: start a background task, stop accepting new connections, let current responses finish, then close the listener.
  - When the app resumes: look up the IP addresses again and reopen the listener on the same port. If the port is taken, use another and refresh the QR code. The token stays the same.
  - The session screen shows a permanent "Keep this screen open" banner.

### 3.2 Local HTTP server on Android

- **Permissions:**
  - `dart:io` `HttpServer` needs only `INTERNET`, a normal permission, **up to targetSdk 36**.
  - **Android 17 with targetSdk 37+:** "Accepting an incoming TCP connection" needs the runtime permission **`ACCESS_LOCAL_NETWORK`** (in the *Nearby devices* group). Without it, the local network is blocked by default [V, Android docs, checked myself]. On builds from Android 16 QPR2 onward, hotspot interfaces also count as local networks [V source; T].
  - **Decision:** target SDK 36 (the Flutter default; [T] confirm at M1). Declare `ACCESS_LOCAL_NETWORK` now, and request it at session start once we raise the target to 37.
  - We already ask for *Nearby devices* for the hotspot on Android 13+ (§3.3), so the user sees one prompt, not two.
- **What happens after the user switches away** [V, AOSP source + docs]:
  - The app stays the "previous app" for about 60 seconds, then becomes cached.
  - About 10 seconds later it is **frozen** (Android 14+): the Dart isolate stops, and the listening socket stays open but nobody answers.
  - On Android 15+, the live TCP connections of frozen apps are destroyed.
  - The process can be killed at any time.
  - The local-only hotspot also dies with the process.
- **→ Foreground service: yes, from M1.**
  - **Type:** `connectedDevice`. It needs `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE` + `CHANGE_WIFI_STATE` (all normal permissions) and has **no time limit**. `dataSync` would get only 6 hours per day on Android 15+.
  - **When it starts:** when the user starts a session. A foreground service can't be started from the background.
  - **What it is:** roughly 80 lines of native Kotlin that does nothing but keep the process at foreground priority and show a "Sharing: tap to return · Stop" notification. The Dart server keeps running in the main isolate.
  - **Notification permission:** `POST_NOTIFICATIONS` isn't needed to start it. If it's denied, the notice appears only in Task Manager. We ask once, on Android 13+.
- **Finding the address:** `NetworkInterface.list()` still returns IPv4 addresses on Android 11+ with targetSdk 30+, because bionic's `getifaddrs` falls back to `RTM_GETADDR` [V source]. MAC addresses are hidden, which we don't need.
- **Serving `content://` files without copying them:**
  - **The problem:**
    - `file_picker` **always copies** picked files into the cache on Android [V, plugin source].
    - `ContentResolver.openFileDescriptor("r")` may hand back a pipe, for example from cloud providers, and a pipe can't seek.
    - Reopening `/proc/self/fd/N` from Dart is unreliable [R].
  - **Plan:**
    1. Kotlin opens the file descriptor and calls `detachFd()`.
    2. Dart checks that `lseek(fd, 0, SEEK_END)` succeeds, meaning it's a seekable regular file, and reads it with `pread` through `dart:ffi`. That supports Range.
    3. For anything not seekable, fall back to copying into the cache with a progress bar.
  - **How long access lasts:** picker grants last until reboot; share-intent grants last while our activity is alive [V].
  - So on Android we use our own picker (the system Photo Picker for media, plus `ACTION_OPEN_DOCUMENT` for files) instead of `file_picker`. `file_picker` stays for iOS.
  - **[T]:** MediaProvider, Downloads and Google Drive providers.

### 3.3 Android local-only hotspot

`WifiManager.startLocalOnlyHotspot` has been available since **API 26 (Android 8.0)** [V]. That becomes our Android **minSdk 26**. Flutter's own minimum is 24.

| Host device | Permissions needed | Location switch |
|---|---|---|
| API 26–28 | `CHANGE_WIFI_STATE` + coarse or fine location | must be **on** |
| API 29–32 | `CHANGE_WIFI_STATE` + `ACCESS_FINE_LOCATION` | must be **on** |
| API 33+ (we target 36) | `CHANGE_WIFI_STATE` + `NEARBY_WIFI_DEVICES` with `usesPermissionFlags="neverForLocation"`; `ACCESS_FINE_LOCATION` declared with `maxSdkVersion="32"` | not needed |

Sources: [V] Android docs and AOSP `WifiPermissionsUtil` / `WifiServiceImpl`.

- **The app must be visible**, or already running a foreground service, when it asks for the hotspot. Otherwise the request fails with `ERROR_INCOMPATIBLE_MODE` [V source].
- **Network name and password are random.** A normal app can't choose them, not even on Android 16 or 17. API 36 made a configuration call public, but for normal apps the system copies only the channel settings [V source].
  - Read the credentials with `getSoftApConfiguration()` on API 30+ (`getWifiSsid`, `getPassphrase`, `getSecurityType`), and with `getWifiConfiguration()` on API 26–29.
  - The generated password may contain characters that need escaping in the QR code. We always escape.
- **Security:** WPA2-PSK, or WPA2/WPA3 *transition* mode if the manufacturer enabled it. Old phones can join either. QR code: `T:WPA` in both cases [V source].
- **Band:** the first supported band, which is normally **2.4 GHz** [V, AOSP]. That's good for old guests. [T] manufacturer differences, especially Samsung.
- **Host IP address:**
  - Android 10: `192.168.43.x`.
  - **Android 11+: a random /24 inside 192.168.0.0/16, with a random host address from .2 to .254. Never assume `.1`** [V source].
  - The interface name depends on the manufacturer (`wlan1`, `ap0`, `swlan0`…). We find the hotspot address by comparing the interface list before and after the hotspot starts.
- **The host's own Wi-Fi drops** on phones without STA+AP concurrency (checked with `isStaApConcurrencySupported()`, API 30) [V]. That's fine in Mode 2.
- **When it stops:** when we close the reservation, when our process dies, when the user turns it off, or when regular tethering starts. We get `onStopped`/`onFailed`, and the UI says "Hotspot stopped" with a Restart button.
  - If another app is already running a local-only hotspot, we receive its credentials.
- **Failure messages:**

| Failure | Message to the user |
|---|---|
| `ERROR_INCOMPATIBLE_MODE` | "Turn off your regular hotspot and try again" |
| `ERROR_TETHERING_DISALLOWED` | "Hotspots are blocked on this phone" |
| `ERROR_NO_CHANNEL` | "No free Wi-Fi channel. Try again" |
| `ERROR_GENERIC` | A generic message |
| Location off (API < 33) | Deep-link to the location settings |

### 3.4 Wi-Fi QR codes in stock camera apps

- **Format:** `WIFI:T:WPA;S:<ssid>;P:<password>;;` [V, ZXing].
  - The characters `\ ; , " :` must be escaped with a backslash.
  - Quoted values are a problem on iOS [R].
- **Security type:** Android's own hotspot QR codes use `T:WPA` for WPA2 and for WPA2/WPA3 transition mode, and `T:SAE` only for WPA3-only networks [V, AOSP source]. We'll use `T:WPA`. Whether iOS accepts `T:SAE` is undocumented [T].
- **Safe hotspot credentials:** if we ever choose the SSID or password ourselves, use only `[A-Za-z0-9]` and include at least one letter outside a–f, so the value can't be read as hex.

| Guest platform | Can the stock camera join a Wi-Fi QR? |
|---|---|
| iPhone, iOS 11+ | Yes. Camera shows a "Join network" banner [R, widely reported] [T on iOS 26 and 27] |
| Android 10+, any maker | Yes, through **Settings › Wi-Fi › QR scan icon** (AOSP Wi-Fi Easy Connect) [V]. Whether the *camera* itself handles it varies by maker. |
| Pixel | Camera scan suggestions or Google Lens [V/R] [T] |
| Samsung | Native camera QR scanning from One UI 2 (Android 10). Some Android 9 models got it in mid-2019. Before that it was Bixby Vision [R] [T] |
| Xiaomi / Redmi | Camera has a "Scan QR codes" setting [V]. The Scanner app can join Wi-Fi [R] |
| Oppo / OnePlus / Realme, Huawei, Motorola | QR scanning exists. Wi-Fi joining is undocumented or done through Google Lens [R] [T] |
| Android 8 / 9 era phones | Often **no QR scanning in the stock camera at all** [R] |

**Consequence:** every QR code is also shown as large text: the network name, the password and the URL. On Android guests that are too old to scan, the guest types them.

### 3.5 iOS Local Network permission

- **What needs permission** (iOS 14+): outgoing TCP and UDP, multicast and broadcast, Bonjour, and `.local` name resolution.
- **What doesn't:** listening for and accepting incoming TCP connections, and receiving UDP unicast [V, TN3179 table, which I checked myself].
- **Safari doesn't need it either** [V]. The guest never sees a prompt.
- **Our server uses no Bonjour and makes no outgoing local connections, so iOS should never show the prompt** [T: run a session with *Settings › Privacy › Local Network* turned off for the app, and confirm guests still connect].
- **"Handle the prompt properly" therefore means:**
  1. Add `NSLocalNetworkUsageDescription`, with text that explains why. Apple requires it if the app uses the local network directly or indirectly.
  2. Don't trigger the prompt for no reason.
  3. If a later feature needs outgoing local traffic, such as Bonjour discovery, trigger the prompt only after the user acts, and detect a denial with `NWBrowser` (`kDNSServiceErr_PolicyDenied`, -65570). There is no API to read the permission status [V].
  4. If M1 testing shows connections failing anyway, add an in-app check and a "How to allow" screen.
- **Simulator:** it doesn't implement Local Network privacy [V]. Only real devices count.

### 3.6 Free Apple ID ("Personal Team")

- **Limits** [V, Apple docs]:
  - provisioning profiles expire after **7 days**;
  - 3 devices;
  - 3 apps per device;
  - 10 App IDs per 7 days.
- **Capabilities that are available:** Background Modes, App Groups (for a future share extension, which would need its own App ID), Keychain Sharing, and others.
- **Not available:**
  - Hotspot Configuration (`NEHotspotConfiguration`), so the app can't join a Wi-Fi network for the user;
  - Access Wi-Fi Information, so the app can't read the network name (SSID);
  - Network Extensions;
  - the request-only entitlements, for example the user-assigned device name.
- **Consequences:**
  - The iPhone host can't read or set Wi-Fi and can't control Personal Hotspot.
  - It *can* list network interfaces and their IP addresses.
  - `UIDevice.name` returns "iPhone" on iOS 16+ [V], so the host can't learn its own hotspot name.

### 3.7 Guest browsers on plain HTTP

| Browser | What happens | Source |
|---|---|---|
| Chrome on Android, page navigation | No warning on private IPs. HTTPS-First "balanced" mode, which Chrome 154 is rolling out as the default, skips non-unique hosts, and those include RFC1918 addresses | [V] Chromium source + Google docs |
| Chrome on Android, users with **strict** HTTPS-First | An interstitial warning page, and the download warning on **every** file type | [V] source [T] |
| Chrome on Android, downloads | Every download from an http page is "insecure" unless it comes from localhost. Bypassable *Keep / Discard* dialog, **except** these extensions: txt css json csv tsv jpg jpeg png gif tif tiff ico webp avif aac midi ogg wav webm mp3 mp4 m4a flac mpeg mov wmv. On by default since Chrome 122. No per-site allow setting on Android | [V] `insecure_download_blocking.cc`, which I checked myself |
| Chrome Local Network Access (Chrome 142+) | Doesn't gate a top-level navigation to a private IP, or same-origin requests from that page. **Never reference `localhost` or `127.0.0.1` from the page** | [V] Chrome docs [T] |
| Oldest Chrome on an Android 8/9 guest | 138 if the phone was ever updated. Could be far older on a phone that never updated, in which case there's possibly no download warning at all | [V] |
| Samsung Internet | "Switch to secure connection" (HTTPS upgrade) is on by default. Behavior on private IPs is undocumented | [V]/[T] |
| Google app in-app browser (Lens) | Downloads may not work. Chrome Custom Tabs use Chrome's own download handling | [R]/[T] |
| Safari on iOS 17+ | Tries HTTPS first and falls back to HTTP. An optional "Not Secure Connection" warning setting exists since 18.2. No blocking specific to private IPs is documented | [V] Safari release notes [T] |

**Consequences for our server:**

- A browser trying HTTPS first will send a TLS handshake to our HTTP port. The server has to fail that fast so the browser falls back to HTTP quickly [T: measure the fallback delay in Safari and Samsung Internet].
- Downloads always send `Content-Disposition: attachment`.

---

## 4. Architecture

```
┌──────────────────────── Host app (Flutter, iOS + Android) ────────────────────────┐
│  UI: Home · Send · Receive · Session (QR) · Mode 2 wizard · Settings              │
│        │                                                                          │
│  SessionController ── files, token, PIN, upload batches, progress, guest list     │
│        │                                                                          │
│  transfer_server  (pure Dart package, dart:io only; no Flutter imports)           │
│    ├─ listener per chosen LAN IPv4, token gate, Host check, PIN, limits           │
│    ├─ downloads: streaming from disk, HEAD, single-range Range                    │
│    ├─ uploads: offer → host approval → streamed raw body to disk; no-JS multipart │
│    ├─ filename sanitizer + path containment                                       │
│    └─ guest page renderer (one HTML template, inline CSS/JS) + guest strings      │
│        │                                                                          │
│  NetworkInfo: list interfaces → classify → best private IPv4; re-check every 2 s  │
│        │                                                                          │
│  Platform channels (our own, small)                                               │
│    Android (Kotlin): local-only hotspot · foreground service · share intents ·    │
│                      content:// → file descriptor · MediaStore save · free space  │
│    iOS (Swift): background-task bracket · Save to Photos · free space             │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Repository layout

```
PLAN.md  TESTING.md (M5)  README.md (build steps)
app/                          Flutter host app
  lib/  ui/  session/  net/  platform/  l10n/ (ARB)
  android/app/src/main/kotlin/...   hotspot, foreground service, share intents, fd bridge
  ios/Runner/...                    Info.plist keys, Swift channel
packages/transfer_server/     pure Dart: server, guest page, guest strings
  lib/  test/                 `dart test` runs on the Mac in seconds
tool/                         build/install scripts (ios_install.sh, android_apk.sh)
```

Keeping the server in a pure-Dart package has three benefits:

- Its tests run fast with real sockets on the Mac.
- It can't depend on Flutter by accident.
- The guest page can be developed by running the server on the Mac and opening it from any browser.

### 4.2 Session, token and URLs

- **Token:** 130 random bits from `Random.secure()`, written as 26 base32 characters.
  - Compared in constant time.
  - Compared case-insensitively, so the QR code can use uppercase (see below).
- **QR content:** `HTTP://192.168.1.23:8742/K7Q…26 chars`.
  - The whole URL is uppercase, so it fits QR *alphanumeric* mode. That makes a smaller, easier-to-scan code for old cameras.
  - **[T]:** if any stock scanner mishandles an uppercase `HTTP://`, fall back to lowercase.
- **Port:** a fixed preferred port, so URLs look familiar, with a random fallback.
  - It must avoid ports below 1024 and the ports Chrome blocks (for example 6000, 6665–6669, 10080).

| Method & path | Purpose |
|---|---|
| `GET /<T>/` | Guest page: the file list in send mode, the upload form in receive mode, or the PIN form |
| `POST /<T>/pin` | PIN check. Sets a cookie scoped to `/<T>/`, then 303 back to the page |
| `GET, HEAD /<T>/f/<i>/<name>` | Download file *i*, streamed, with Range support. `name` is decoration only and never used as a path |
| `GET /<T>/v/<i>/<name>` | Same file with `inline` instead of `attachment`. Lets an iPhone guest long-press → *Save to Photos* (M4) |
| `POST /<T>/offer` → `GET /<T>/offer/<id>` | JS upload: the guest announces names and sizes, then long-polls until the host accepts or declines |
| `POST /<T>/u/<batch>/<i>` | JS upload of one file as a raw body (`xhr.send(file)`), with progress |
| `POST /<T>/u` | No-JS upload: a plain multipart form, quarantined until the host approves (§4.4) |
| `GET /<T>/status` | Small JSON for progress and "session ended" handling |
| Anything else | `404` with a neutral "This link has expired. Ask for a new code." page. Reveals nothing |

### 4.3 Downloads (host → guest)

- **Streaming:**
  - `File.openRead(start, end)` is piped into the response with `addStream`, so backpressure is handled and memory use stays flat.
  - Tested with files larger than 4 GiB and with offsets above 4 GiB.
- **Range:**
  - A single range (`bytes=a-b`, `a-`, `-n`) returns `206` with `Content-Range`.
  - A request outside the file returns `416 bytes */size`.
  - Multiple ranges get a `200` with the whole file, which the HTTP spec allows.
  - `If-Range` is checked against a weak ETag built from size and modification time.
- **Headers:**
  - `Content-Disposition: attachment; filename="<ascii fallback>"; filename*=UTF-8''<pct-encoded>`.
  - `Content-Type` looked up from the extension with package `mime`.
  - `Content-Length`, `Accept-Ranges: bytes`, `Cache-Control: no-store`.
- **Where the files come from on the host:**
  - **iOS:** `file_picker` with `assetRepresentationMode: .current` and `compressionQuality: 0`. It loads `UTType.item` file representations, which are the originals with no re-encoding [V, plugin source]. They are temp copies, deleted when the session ends.
  - **Not `image_picker`:** it re-encodes HEIC to JPEG on iOS [V, plugin source].
  - **Android:** our own picker plus the share sheet give `content://` URIs. They're served through a detached file descriptor and `pread`, with no copy, and copied only when the file isn't seekable (§3.2).
- **Several files:** one big *Download* button per file in M1.
  - "Download all" as a ZIP is an open question (§10): on Android it triggers Chrome's warning, and on iPhone it lands in Files as a ZIP that has to be opened.

### 4.4 Uploads (guest → host)

The host must approve every batch before any file is kept.

- **With JS (the normal path):**
  1. The guest picks files.
  2. The page sends `POST /offer` with the name, size and type of each file.
  3. The host sees "*iPhone (Safari) wants to send you 12 files, 48 MB* · list · **Decline / Accept**".
  4. Only after *Accept* does the page upload each file, one after another, as a raw XHR body with progress, to `/u/<batch>/<i>`.
  5. The server enforces that the body size matches the declared size and is within the limits. Nothing is transferred before approval.
- **Without JS (fallback):**
  1. A plain `<form method=post enctype=multipart/form-data>` posts to `/u`.
  2. The server streams the parts into a **quarantine** directory (private to the app, never visible) with the same limits.
  3. When the request completes, the host gets the same approval sheet.
  4. The guest gets a "Waiting for the other phone to accept…" page that refreshes itself with `<meta refresh>`, which needs no JS.
  5. *Accept* moves the files into place, which is a rename on the same volume. *Decline* deletes them.
- **Limits** (configurable): maximum size per batch (default in §10), maximum files per batch (500), maximum name length, and one pending offer at a time. Free space is checked before accepting.
- **Filename sanitizer:**
  - keep only the last segment after `/` and `\`;
  - drop control characters and `< > : " | ? *`;
  - trim dots and spaces at either end;
  - `.`, `..` or an empty name becomes `file`;
  - a leading dot becomes `_`;
  - Windows-reserved names get a prefix;
  - cap the name at 200 UTF-8 bytes, keeping the extension;
  - add ` (1)`, ` (2)` and so on when a name already exists.
  - Then **resolve the final path and check that it's inside the target directory.**
- **Where received files go:** see §10, question 4.
  - Files are written to a `.part` temp file and renamed when complete. Partial files are deleted on error or when the session stops.

### 4.5 Guest page

- **One server-rendered HTML document** with inline CSS and roughly 5 KB of inline ES5 JS. Target under 30 KB in total.
  - No external URL of any kind; a test enforces this.
  - No web fonts: the system font stack.
  - No icons that need files: file-type badges are CSS text such as "JPG" or "PDF".
- **Without JS:** every download is a plain `<a href>` link, the upload form posts normally, and "where did it go" text is rendered on the server from the User-Agent.
- **With JS:** progress, the approval wait, per-file upload status, "session ended" detection, and iPadOS detection (iPadOS presents itself as a Mac).
- **Old browsers:** ES5 only, using XHR rather than fetch, no Promises and no CSS variables, so even an un-updated Chrome on Android 8 works. Flexbox only.
  - Targets: iOS Safari 13+, Chrome on Android 8+, Samsung Internet.
- **Layout:**
  - mobile-first;
  - tap targets at least 56 px;
  - text at least 17 px;
  - dark mode through `prefers-color-scheme`;
  - one primary action per screen;
  - file names (shortened in the middle) and sizes always visible.
- **"Where did it go"** is a per-platform line under the buttons and after each download.
  - Draft wording, to be confirmed on devices in M1 [T]:
    - iPhone: "Files app › Downloads".
    - Android: "Files › Downloads", or *Chrome › ⋮ › Downloads*.
  - Where it applies, an Android Chrome hint: "If Chrome asks, tap **Keep**."
- **Strings:**
  - All guest strings live in one file, `packages/transfer_server/lib/src/guest/strings_en.dart`. Keys come with an English map, and other languages are added as sibling maps.
  - The language is picked from `Accept-Language`.
  - Host app strings use Flutter's standard ARB files (`app/lib/l10n/app_en.arb`).

### 4.6 Security

- **Token gate:** every route except the neutral 404 requires the token.
- **Optional 4-digit PIN:**
  - Shown on the host screen and never put in the QR code.
  - Five wrong attempts in a session lock it, and the host has to start a new session with a new token.
  - After a correct PIN the server sets a cookie: HttpOnly, SameSite=Strict, path-scoped.
- **Host header allowlist:** only our IP:port is accepted, which blocks DNS-rebinding attacks.
- **Only the chosen LAN addresses are served** (never `0.0.0.0`), and connections from non-private addresses are rejected.
- **Connection caps:** 32 connections in total and 8 per IP.
- **Headers on the page:**
  - `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-…'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'`;
  - `Referrer-Policy: no-referrer`;
  - `X-Content-Type-Options: nosniff`;
  - `Cache-Control: no-store`.
- **Uploaded files are never served back.** Files are addressed by index only, never by name or path.
- **Session end:**
  - Triggered by the *Stop* button, by leaving the session screen, or by 30 minutes of inactivity (configurable).
  - Closes the listeners (force-closing current connections), cancels any pending offer, deletes temp and quarantine files, and invalidates the token.
- **No network traffic beyond serving the LAN:** no analytics, no crash reporting, no update checks, no accounts. On Android the `INTERNET` permission is still required to open sockets.

### 4.7 Choosing the address, and the Mode 2 flows

- **Finding the address:**
  - `NetworkInterface.list(type: IPv4)` is classified by interface name:
    - iOS: `en0` is Wi-Fi, `bridge100` is Personal Hotspot; `pdp_ip*` (cellular) and `utun*`/`ipsec*` (VPN) are skipped.
    - Android: `wlan0` is Wi-Fi, and hotspot interfaces vary by device (§3.3); `rmnet*` and `ccmni*` (cellular) and `tun*` (VPN) are skipped.
  - Only private addresses are kept (RFC1918).
  - The list is checked again every 2 seconds while the session screen is open. If the address changes, the server rebinds and the QR code is redrawn with the same token.
  - **No usable address → "You're not on Wi-Fi" card → [Use hotspot mode].**
  - IPv6 is out of scope unless the iPhone hotspot tests in M3 force it.
- **Client isolation can't be detected from the host.** If no valid request arrives within 30 seconds of the QR code appearing, a card opens:
  - "Not opening on the other phone? Check that it's on the same Wi-Fi. Guest and café networks often block phones from seeing each other → **Use hotspot mode**."
  - The text fallback (the URL) stays on screen.
- **Mode 2, Android host:**
  1. Request permission (§3.3).
  2. Start the local-only hotspot.
  3. **Step 1 of 2:** the Wi-Fi QR code, plus the network name and password in large text, and a [Next] button.
  4. **Step 2 of 2:** the URL QR code and text. Going back reopens step 1.
  5. The hotspot reservation is released when the session ends.
- **Mode 2, iPhone host** (guided; the app can't create or join networks):
  - **A. Guest hotspot.** This works with mobile data off.
    - Since Android 11, the carrier check runs only when the hotspot's upstream is cellular, so a LAN-only hotspot starts fine [V source; T on real carriers].
    - The Android owner's browser can reach a server on a client whatever its default network is (netd local-route rule) [V source].
    1. The app shows instructions for the guest's platform, for example Android *Settings › Hotspot*, then the "share" QR code.
    2. The host joins with the iPhone Camera, which scans the guest's hotspot QR code (Android 10+ shows one), or by typing the password in Settings.
    3. The app notices the new `en0` address and moves on to the URL QR code.
  - **B. Personal Hotspot.** This needs mobile data on and a plan that allows it.
    1. Optionally, a one-time setting where the user types the hotspot name and password. With that, the app can show a Wi-Fi QR code for the guest.
    2. When `bridge100` gets an IPv4 address, the app shows the URL QR code.
    3. **Risk:** clients that only get IPv6 or CLAT [R/T].
  - The order of A and B will be decided after the M3 tests.

### 4.8 Lifecycle

- **Both platforms:**
  - The screen is kept awake with `wakelock_plus` while a session is open.
  - A visible "Session active" state, with a Stop button.
- **iOS:**
  - Background handling as in §3.1.
  - A permanent banner: "Keep this app open. Transfers pause if you leave it."
- **Android:**
  - The `connectedDevice` foreground service runs for the whole session (§3.2), so the server survives the user switching apps or locking the screen [T: Doze with the screen off].
  - The notification offers *Stop*.

### 4.9 Host app screens

1. **Home:**
   - **Send** / **Receive**, two big buttons.
   - A network status line, for example "Wi-Fi · 192.168.1.23" or "No Wi-Fi: use hotspot mode".
   - A settings gear.
2. **Send:**
   - Choose *Photos & videos* or *Files*, or arrive through the Android share sheet.
   - A list of the chosen files with remove buttons, then [Show code].
3. **Session** (send and receive):
   - a big QR code with "Scan with the other phone's camera", and the URL in large text (tap to enlarge);
   - a live status line: "Waiting…", then "iPhone connected", then "Downloading IMG_0412.HEIC 45%";
   - the help card from §4.7;
   - Stop.
4. **Receive:**
   - the session screen;
   - the approval sheet;
   - progress;
   - a received-files list with Open / Share / *Save to Photos* (iOS) / *Show in Files*.
5. **Mode 2 wizard:** §4.7.
6. **Settings:**
   - PIN on or off;
   - upload limit;
   - inactivity timeout;
   - iOS only: Personal Hotspot name and password, used for the guest QR code;
   - open-source licences.

---

## 5. Known risks: what the research says, and how we'll test

| # | Risk | What research says | Mitigation | Test in |
|---|---|---|---|---|
| 5.1 | Chrome on Android warns on HTTP downloads | [V] *Keep / Discard* dialog for types outside the safe list (§3.7). Private IPs aren't exempt. Strict HTTPS-First mode warns on everything | Page hint "tap **Keep**", shown only for Android and only for affected files. No ZIP for Android guests. Optional HEIC → JPEG copies for Android guests (§10) | M1: Chrome 154 + an old Chrome, Samsung Internet, every file type |
| 5.2 | Wi-Fi without internet | **iPhone guest** [R, Apple DTS]: stays on a network it joined by hand. Traffic to the local subnet uses the direct route, so it stays on Wi-Fi even with cellular on. **Android guest** [V, AOSP source]: with mobile data **on**, cellular stays the default network, and **Chrome's requests to 192.168.x.x go out over cellular and fail**. That changes only if the user answers "Stay connected?" (shown about 8 s after joining a network they picked) or mobile data is off. With mobile data off, Wi-Fi is the default and it works | The host's 30-second help card adds: "On the other phone: if it asks *Stay connected?*, tap **Yes**, or turn off mobile data." The cross-platform cases mostly avoid this: an iPhone guest on an Android hotspot is fine; on an iPhone host's Personal Hotspot (B) the network has internet; with a guest hotspot (A) the guest owns the network. It bites in Mode 1 on an offline router | M1 (offline router), M3. Field test runs with data off, so also test with data **on** |
| 5.3 | iPhone guest uploads: original format? | [V] Photos picker → JPEG/H.264, possibly downscaled. Picker "Options" (iOS 17+) has Current / Most Compatible and a Location switch, but whether that overrides WebKit is unknown. Files-app picks are byte-for-byte. GPS has been stripped in some versions [R] | Page tip under the button: "Need original quality? Tap **Options › Current**" (if testing shows it works). Record what arrives | M2: compare format, size, EXIF and GPS against the originals |
| 5.4 | Where downloads land on the guest | iPhone [V]: Files › Downloads, in iCloud Drive or On My iPhone depending on *Settings › Apps › Safari › Downloads*. Photos only via inline view → long-press, or Files › Share › Save. Android [V]: the public *Download* folder | Accurate per-platform text on the page. iPhone *Save to Photos* view link (M4) | M1: record the exact paths and the default setting on iOS 26 and 27, offline |
| 5.5 | Client isolation breaks Mode 1 | Can't be detected from the host | 30-second "not opening?" card → Mode 2 | M1: test on a guest network that has isolation turned on |
| 5.6 | Browsers trying HTTPS first | Safari 17+ and Samsung Internet try HTTPS, then fall back | Fail TLS handshakes fast. Measure the delay | M1 |
| 5.7 | Android host specifics | Without a foreground service the server freezes about 70 s after the user switches away (§3.2). Hotspot band, security and interface name vary by manufacturer. `content://` files may not be seekable | Foreground service from M1. Find the hotspot address by comparing interfaces before and after. Copy fallback for files that can't seek | M1, M3 |
| 5.7b | Android 17 guest phones | Once Chrome targets SDK 37, Chrome itself may need the local-network permission to reach 192.168.x.x. In-app browsers (WebViews) inherit their host app's permission [V docs; T] | Record what an Android 17 guest sees. Add a page and help-card hint if a prompt appears | M1 |
| 5.8 | Lens / Google app opens the URL in an in-app browser | Downloads may fail there [R] | Page shows "Open in Chrome" if it detects a WebView User-Agent | M1 |
| 5.9 | iOS hotspot clients get only IPv6/CLAT | [R] on iOS 18+ | Prefer option A (guest hotspot). Investigate IPv6 if needed | M3 |

---

## 6. Packages

All of these are widely used and actively maintained, unless flagged otherwise.

| Package | Used for | Status (pub.dev, 2026-10-11) |
|---|---|---|
| `mime` (tools.dart.dev) | MIME type lookup, multipart parsing for no-JS uploads | 2.1.0, published 2026-08 ✔ |
| `qr` (kevmoo.com) | QR encoding. We draw it with our own ~40-line `CustomPainter` | 4.0.0, published 2026-05, 0 open issues ✔ |
| `wakelock_plus` (fluttercommunity.dev) | Keep the screen awake | 1.8.1, published 2026-09 ✔ |
| `file_picker` (verified publisher) | **iOS only:** picking photos, videos and files, with originals. On Android it always copies into the cache, so we use our own picker there | 13.1.0, published 2026-09, 4.9k likes ✔ (new maintainer since 2026) |
| `ffi` (dart.dev) | Memory allocation for `pread`/`lseek` on Android file descriptors | Official Dart package ✔ |
| `path_provider` (flutter.dev) | Temp, documents and support directories | 2.1.6 ✔ |
| `permission_handler` (baseflow.com) | Android runtime permissions (§3.3), Photos add-only on iOS | 13.0.2 ✔ |
| `flutter_localizations` + `intl` (SDK / dart.dev) | Host app strings | ✔ |
| `test`, `flutter_test`, `flutter_lints` (Dart / Flutter teams) | Tests and lints | ✔ (flutter_lints was last published 2025-05, but it's official) |

Considered and **not** used:

| Package | Why not |
|---|---|
| `shelf`, `shelf_router`, `shelf_static` | Not needed. `dart:io` plus a 50-line router gives full control over streaming, Range and holding requests. Their latest releases are also more than a year old |
| `qr_flutter` | Unmaintained: last release 2023-05 |
| `image_picker` | Re-encodes HEIC on iOS |
| `receive_sharing_intent` | 257 open issues and PRs. About 60 lines of our own Kotlin covers `ACTION_SEND` and `ACTION_SEND_MULTIPLE` |
| `flutter_foreground_task` | It runs Dart in a separate service. We only need the process kept alive, which a tiny native service does (§3.2) |
| `network_info_plus` | Its Wi-Fi IP call may not return the hotspot interface. Listing the interfaces ourselves covers every case |
| `archive` | Only if we build "Download all as ZIP", and even then a streaming "stored" ZIP64 writer may be simpler to write ourselves |

Native code we write ourselves (small, and kept in one file per feature):

- **Android:** local-only hotspot, foreground service, share intents, `content://` → file descriptor, MediaStore save, free space.
- **iOS:** background-task bracket, Save to Photos, free space.

I'll ask before adding anything not listed here.

---

## 7. Testing strategy

### 7.1 Automated server tests

These run on the Mac with `dart test` in `packages/transfer_server`, using real sockets.

- **Token:**
  - missing, wrong, truncated, extra segments, wrong case, URL-encoded;
  - every route rejects without it;
  - the neutral 404 leaks nothing (no file names, no counts).
- **Host header** mismatch is rejected.
- **PIN:** required when set, the cookie flow, lockout after 5 wrong attempts, and the cookie path scope.
- **Path traversal in downloads:** out-of-range index, negative index, `..` and `%2e%2e%2f`, double encoding, and a trailing `name` part that tries traversal.
- **Path traversal in uploads:**
  - names like `../../x`, `..\x`, `/etc/passwd`, `C:\x`, `a/b`;
  - NUL and control characters, `∕` (the division slash lookalike);
  - a 300-byte name, `.hidden`, `CON`, a name of only dots, and duplicate names.
  - Assert that every file lands inside the batch directory with the expected sanitized name.
- **Streaming:**
  - A sparse 5 GiB file downloaded in full, checking the byte count and sampled hashes.
  - The process memory (RSS) stays under a fixed bound while 1 GiB+ is served to a deliberately slow client, which proves backpressure works.
- **Range:**
  - `0-0`, `100-`, `-500`, the last byte, beyond the end (416), multiple ranges (200), `If-Range` match and mismatch;
  - offsets above 4 GiB;
  - `HEAD` returns the headers and no body.
- **Upload limits:**
  - `Content-Length` over the limit → 413 with nothing written;
  - a chunked body that crosses the limit → aborted, partial file deleted;
  - a body that doesn't match the declared size → rejected and cleaned up;
  - the per-batch file-count limit;
  - an upload before approval → rejected;
  - decline → nothing written;
  - no-JS quarantine: accept moves the files, decline deletes them.
- **Session stop:** the listener is closed, connections in progress are aborted, temp and quarantine files are deleted, and the old token gets 404 on a new server.
- **Guest page:**
  - no external URLs (no `http(s)://` or `//` in `src`/`href`/`action`);
  - under the size budget;
  - every string key exists in English;
  - works without JS (plain `<a href>` links are present);
  - the CSP header is present.

### 7.2 What I can check myself vs. what needs you

- **I can:**
  - run all the server tests;
  - run the app in the iOS 27 Simulator and an Android emulator;
  - serve the guest page from the Mac and test it in Safari, Chrome, iOS Simulator Safari, and emulator Chrome, including old Chrome builds on Android 8/9 emulator images;
  - build and install onto iPhones plugged into this Mac, once you've signed in to Xcode with your Apple ID.
- **I can't:**
  - point one physical phone's camera at another phone;
  - toggle hotspots on real phones;
  - judge real-world speed.
  
  Each milestone ends with a short device checklist for you, and I report results as *verified on device*, *verified in simulator/emulator only*, or *not verified*.

### 7.3 Device matrix (minimum)

| Host | Guest | Network |
|---|---|---|
| iPhone (iOS 26/27) | Android 14–16 (Chrome) | Same Wi-Fi; Android guest hotspot |
| iPhone | Samsung (Samsung Internet) | Same Wi-Fi |
| iPhone | Old Android 8/9 (if available) | Same Wi-Fi |
| Android 14–16 | iPhone (Safari) | Same Wi-Fi; local-only hotspot |
| Android 8–10 (if available) | iPhone | Local-only hotspot |

---

## 8. Build and run

### 8.1 One-time toolchain setup (needs your OK; see §10)

Missing on this Mac:

- **Flutter 3.47.x:** Homebrew `flutter` cask, or a git clone of the stable branch.
- **JDK 17:** Homebrew `temurin@17`.
- **Android command-line tools:** Homebrew `android-commandlinetools`, then `sdkmanager` installs platform-tools, a platform and build-tools. The total is roughly 5–8 GB.

Already present: Xcode 27, CocoaPods. **[T]:** check that Flutter 3.47 supports Xcode 27 and the iOS 27 SDK.

### 8.2 iPhone with a free Apple ID: the weekly reinstall

- **One-time setup:**
  1. Xcode › Settings › Accounts: add your Apple ID.
  2. Open `app/ios/Runner.xcworkspace` › Signing: choose your *Personal Team*, with a unique bundle ID (§10).
  3. On the iPhone: turn on *Developer Mode* (*Settings › Privacy & Security*). After the first install, trust the developer in *Settings › General › VPN & Device Management*.
- **Each week:** plug in the iPhone, then run `tool/ios_install.sh`. It wraps `flutter run --release -d <device>`.
  - It uses **release** mode because Flutter debug builds on iOS 14+ can't be started from the home screen without a debugger attached. **[T]:** confirm this against Flutter's docs in M1.
- **Expiry:** when the 7-day profile runs out the app stops launching. Re-running the script fixes it.

### 8.3 Android debug APK

- **Build:** `tool/android_apk.sh` runs `flutter build apk --debug` and produces `app/build/app/outputs/flutter-apk/app-debug.apk`.
- **Install:** `adb install -r …`, or send the file to the phone and allow "install unknown apps".
- **For the field test**, consider `flutter build apk --release` too. It's smaller and faster. The Flutter template signs release builds with the debug key, so it's still sideloadable. **[T]:** confirm this at M1.

---

## 9. Milestones (refined)

Each milestone ends with a stop, a demo, a commit, and a device checklist.

| M | Scope | Done when |
|---|---|---|
| **1** | `transfer_server` with the token gate, guest send page, streaming + Range + HEAD, and tests. App: pick files (Android: own picker + file descriptor), session screen with QR and URL, IP detection, wake lock, iOS listener restart on resume, Android foreground service, 30-second help card, Stop. Both hosts | All of these download over the same Wi-Fi: a JPG, a HEIC, a ≥1 GB MP4 and a PDF, from Android host → iPhone guest and from iPhone host → Android guest. Real download locations and Chrome's warnings are recorded and put into the page text |
| **2** | Upload: offer → approval → raw upload with progress, no-JS multipart fallback, sanitizer, limits, saving to the chosen locations, tests | An iPhone guest (Photos picker *and* Files) and an Android guest upload. Format, metadata and size are recorded against the originals |
| **3** | Mode 2: Android local-only hotspot + Wi-Fi QR → URL QR. iPhone guided fallbacks A and B. Tests on Wi-Fi without internet | Both directions work with mobile data off on both phones |
| **4** | Android share sheet, progress polish on both sides, PIN, approval UX polish, clear errors, iPhone guest "Save to Photos" link, received-files actions | Error paths have been walked through on devices |
| **5** | `TESTING.md`: the field-test script with timing sheet and failure-step log, plus a manual checklist per platform | You can run the 5-person test from it |

Basic upload approval ships in M2, not M4, because uploads without approval would be unsafe even in testing. M4 polishes it.

---

## 10. Open questions for you

Each has my recommendation.

1. **Toolchain:** may I install Flutter, JDK 17 and the Android command-line tools with Homebrew (about 5–8 GB)? *Recommend: yes.*
2. **Name and iOS bundle ID:** "GeniusTransfer" and `com.<yourname>.geniustransfer`? A free team needs a bundle ID nobody else has used.
3. **Test devices:** which Android phones do you have (model and Android version)? Can one be plugged into this Mac for M1? Is there an old Android 8/9 phone or an older iPhone for guest testing?
4. **Where received files go.** *Recommend:*
   - **Android:** photos and videos to `Pictures/GeniusTransfer` and `Movies/GeniusTransfer`, so they show up in Gallery and Photos; everything else to `Download/GeniusTransfer`.
   - **iOS:** the app's folder in Files (*On My iPhone › GeniusTransfer*), plus a *Save to Photos* button for images and videos.
5. **"Download all as ZIP" for guests?** *Recommend: not in M1.* Per-file buttons first. Reconsider after M1 testing, since a ZIP triggers Chrome's warning and on iPhone it arrives as a ZIP that has to be opened.
6. **HEIC to Android guests:** offer an automatic JPEG copy when the guest is Android? JPEG avoids Chrome's warning, and old Android can't open HEIC. *Recommend: M4, iPhone host only, as an extra "Compatible (JPG)" button next to the original.*
7. **Foreground service on Android:** decided yes. It's a native `connectedDevice` service with no time limit, shipping in M1 (§3.2). Without it the server freezes about 70 seconds after the host switches apps. It shows an ongoing "Sharing" notification. OK?
8. **Defaults:**
   - PIN off;
   - approval always on, and not configurable;
   - upload limit 20 GB per batch, capped by free space minus 1 GB;
   - inactivity timeout 30 minutes.
   
   OK?
9. **Mode 2 on iPhone host:** keep both A (guest hotspot) and B (Personal Hotspot), and decide the order after M3 testing? *Recommend: yes.*
10. **Field-test baseline:** comparing against Google Drive needs internet. Should the Drive timing be measured separately with data on, using the same file and the same people?

---

## Appendix A: Sources

**LocalSend:** github.com/localsend/localsend @ `14f3a874`, files:
- `LICENSE`
- `packages/core/src/http/server/web.rs`
- `packages/core/assets/web/*.html`
- `app/lib/pages/web_share_page.dart`
- `app/assets/CHANGELOG.md`

Issues #2144, #2316, #2524, #3369, #3449.

**Sharik:** github.com/marchellodev/sharik.

**Chromium:**
- `chrome/browser/download/insecure_download_blocking.cc` (safe-extension list, localhost-only exemption, strict-mode check)
- `chrome/common/pref_names.h` (strict vs balanced HTTPS-First preferences)
- https://support.google.com/chrome/a/answer/10314655 (Chrome 154 HTTPS-First default; Android 8/9 last version 138)
- https://developer.chrome.com/blog/local-network-access
- https://blog.chromium.org/2023/08/towards-https-by-default.html

**Samsung Internet:** https://developer.samsung.com/internet/blog/en/2022/05/05/announcing-170-privacy-by-default

**Apple:**
- TN3179 https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- TN2277 https://developer.apple.com/library/archive/technotes/tn2277/_index.html
- DTS forum threads 685525 (no background servers), 85066 (background task time), 773086 and 127509 (Personal Hotspot), 734361 / 734293 (Wi-Fi without internet)
- Personal Hotspot support https://support.apple.com/en-us/111785
- Capabilities table https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Memberships https://developer.apple.com/support/compare-memberships/
- `UIDevice.name` https://developer.apple.com/documentation/uikit/uidevice/name
- Safari 17 / 18.2 / 27 release notes
- PHPicker `preferredAssetRepresentationMode`
- `BGContinuedProcessingTask` (performing long-running tasks)

**WebKit:** `Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm` (Compatible mode unless the delegate prefers originals; `_setAllowsDownscaling:YES`); bugs 257534, 263192.

**Flutter plugins:**
- `image_picker_ios` source (HEIC re-encode)
- `file_picker_darwin` `IOSFilePickerHandler.swift` (`loadFileRepresentation(UTType.item)`)

**Android:**
- `WifiManager`, `LocalOnlyHotspotReservation`, `SoftApConfiguration.Builder` reference
- https://developer.android.com/develop/connectivity/wifi/wifi-permissions
- https://developer.android.com/privacy-and-security/local-network-permission (Android 17, checked myself)
- FGS types, timeouts and background-start restrictions: https://developer.android.com/develop/background-work/services/fgs/service-types, `/fgs/timeout`, `/fgs/restrictions-bg-start`
- Cached apps freezer: https://source.android.com/docs/core/perf/cached-apps-freezer
- STA/AP concurrency: https://source.android.com/docs/core/connect/wifi-sta-ap-concurrency
- `ContentResolver.openFileDescriptor`

**AOSP source** (`android16-qpr2-release` / `android17-release`):
- Wi-Fi: `WifiServiceImpl`, `WifiPermissionsUtil`, `WifiApConfigStore`, `HalDeviceManager`, `LocalOnlyHotspotRequestInfo`
- Connectivity: `PrivateAddressCoordinator`, `ConnectivityService`, `NetworkRanker`, `EntitlementManager`, `IpServer`
- netd: `RouteController.cpp`
- framework: `OomAdjusterImpl` / `CachedAppOptimizer`
- bionic: `ifaddrs.cpp`
- Dart SDK: `runtime/bin/ifaddrs.cc`

**Android plugins:** `file_picker_android` `FileUtils.kt` (copies to cache); `receive_sharing_intent` `FileDirectory.kt`.

**Wi-Fi QR:**
- ZXing Barcode-Contents wiki
- AOSP Settings `WifiQrCode.java`, `WifiDppUtils.java`
- https://source.android.com/docs/core/connect/wifi-easy-connect

**Flutter:** https://docs.flutter.dev/reference/supported-platforms (minimums: Android API 24, iOS 15), plus pub.dev API data for every package listed.
