# License change: MIT → Apache License 2.0

Chinese version: [LICENSE_CHANGE.md](LICENSE_CHANGE.md). This file is the English mirror.

| Item | Value |
|---|---|
| Effective date | 2026-09-28 (maintainer's decision) |
| Scope | Everything downloaded or redistributed from this commit onwards: the app, `server/`, `packages/fnthink_push/`, and the protocol files under `protocol/` |
| Files touched | `LICENSE`, `NOTICE` (new), `README.md`, `README-en.md`, `CONTRIBUTING.md`, `CONTRIBUTING-en.md`, `server/public/index.html`, `server/public/i18n.js`, `pubspec.yaml`, `packages/fnthink_push/pubspec.yaml`, `server/package.json` |

## Why

Apache-2.0 adds two things MIT does not have, and both matter for this project:

1. **An explicit patent grant with a termination clause** (§3). The device identity lives in
   AndroidKeyStore as Ed25519, with `net.i2p.crypto:eddsa` supplying the curve below API 33 — that is
   squarely inside the range where mobile-ecosystem patent activity happens, and MIT says nothing about it.
2. **The NOTICE chain** (§4(d)). Redistribution must preserve third-party attributions, which is
   checkable, unlike MIT's single "keep the copyright notice" sentence — and this product really does
   ship a large number of third-party components.

## What this change does **not** do

Anyone who obtained a copy **before** this commit keeps MIT terms for that copy. Relicensing does not
revoke those rights and does not stop them from shipping a closed-source or commercial derivative built
from an earlier download.

⇒ If the goal is "stop others from running a closed SaaS on today's code", this change has limited
value; it only governs future distributions. Stronger options are a separate dual license for
`server/` (AGPL + commercial) or licensing the protocol separately from the implementation.
**Neither was done here.**

## Deliberate non-changes (not oversights)

- **No license headers added to source files.** The repository never had them; adding them means a
  several-hundred-file diff, a full re-run of dart format / ktlint / prettier and a golden re-check.
  That is a separate task, not part of this one.
- **`update.md` history untouched.** Those entries describe released versions; retro-fitting a license
  note into them would falsify the timeline. Whether to mention the change in the *next* release
  notes is the maintainer's call.
- **Third-party dependency metadata left alone.** The `"license": "MIT"` entries in
  `server/package-lock.json` describe those packages, not this project.
- **Historical snapshots under `outputs/` and `.workbuddy/`** (including `outputs/_t22_pre/LICENSE`,
  a pre-change copy) stay as they are: editing evidence makes it stop being evidence.

## Compatibility check (what was actually measured)

Apache-2.0 absorbs MIT / BSD / ISC / Apache dependencies without directional problems; copyleft is what
needs checking. Measured locally, **not** a full audit:

- Dart/Flutter side: reading the first lines of every `LICENSE` in the local pub cache yields
  MIT / BSD-3-Clause / BSD-2-Clause / Apache; nothing matches "Mozilla Public",
  "GNU …General Public", "LGPL", "AGPL" or "Eclipse Public".
- npm side: every `"license"` value in `server/package-lock.json` contains no GPL/LGPL/AGPL/MPL/SSPL.

⇒ Switching to Apache-2.0 does not conflict with existing dependencies.

Two boundaries belong in writing so a spot check is not read as an audit:

1. This is engineering judgement, not legal advice. A formal compliance statement needs the **full
   transitive tree** — Kotlin/Android AARs, Flutter plugin native dependencies, bundled `.so` files —
   reviewed and signed off by someone qualified. **That has not been done.**
2. The scanning tool lied once and would lie again: `grep -i MPL` reports "almost every Dart package
   is MPL", because the letters `mpl` occur inside the word `e**xampl**e`. Match license **full names**.
