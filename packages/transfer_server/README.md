# transfer_server

The local HTTP/HTTPS server behind GeniusTransfer. Pure Dart (`dart:io`), no
Flutter imports, so it runs and is tested on the Mac:

```bash
dart test
```

One `TransferServer` is one sharing session. It serves the shared files and
a self-contained guest page under `/<TOKEN>/`, on LAN addresses only. See
`PLAN.md` §4 at the repository root for the design.

With `secure: true` it serves HTTPS. Each session makes a new ECDSA P-256
key and a self-signed certificate for its own IP addresses (`TlsIdentity`,
in `lib/src/tls.dart`), valid for 30 days, and makes a new one only when the
addresses change.
