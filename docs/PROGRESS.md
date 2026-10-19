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

## 2026-10-19 evening

- Private repo created and pushed: https://github.com/swissmarley/GeniusTransfer
- Tracked files checked: no build output, local paths, personal data or
  tokens. The template `app/README.md` was replaced by a pointer.
- Samsung tablet not connected yet (adb shows no device); will install and
  self-test it when it appears.
- Windows: built on your Windows PC later (README › Windows).
