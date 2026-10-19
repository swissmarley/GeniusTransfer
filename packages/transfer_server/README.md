# transfer_server

The local plain-HTTP server behind GeniusTransfer. Pure Dart (`dart:io`), no
Flutter imports, so it runs and is tested on the Mac:

```bash
dart test
```

One `TransferServer` is one sharing session. It serves the shared files and
a self-contained guest page under `/<TOKEN>/`, on LAN addresses only. See
`PLAN.md` §4 at the repository root for the design.
