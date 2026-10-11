# Release process

This repository owns the Mac app only. Chrome and the website release separately. The renderer CLI is kept here solely as a development tool for a consumer pinned to an exact Git revision.

## Local checks and packaging

```sh
make check
make dev-app
make release
```

`VERSION` is the only marketing-version source. The bundle's build number is `git rev-list --count HEAD`; About reads both values from the bundle. The extracted repository starts with two commits, so these build numbers restart from that history when the marketing version advances from 0.1.5 to 0.1.6. Version comparisons must use the marketing version before the build number. Local previews record a dirty-tree bit; release refuses a dirty tree.

`make release` cleans generated build products, runs the same quality gate, bundles only the app executable and compiled icon, ad-hoc signs with the hardened runtime and no entitlements, creates a compressed DMG with an Applications link, verifies the DMG and emits a SHA-256 checksum and JSON build manifest. The beta currently ships Apple Silicon: Intel/Rosetta is unavailable locally, so universal support is not claimed.

A source change requires a new commit and a new candidate. Never regenerate fixtures or goldens as part of packaging. `SUPPORT_URL=https://...` may be supplied only after the real support destination is approved and working; otherwise the menu item remains disabled.

## GitHub Actions

CI uses macOS 26 / Xcode 26.6 for tests and packaging. Pull requests and pushes to main run `make check`. A matching `v*` tag runs `make release` and attaches the DMG, checksum and manifest to a **draft** GitHub release. It never publishes it. The owner downloads, opens and judges that exact package before publishing.

No signing certificates or updater keys are needed for this ad-hoc phase. The read-only build job has no deployment credentials; write permission is granted only to the tag job for the draft release.

## Evidence still required

A clean account and another Mac must establish: first-run welcome, actual TCC allow/deny and selected-folder recovery, launch-at-login over a restart, fresh downloaded DMG behavior, ad-hoc update permission continuity, full-screen/Spaces hotkey, physical thumbnail drag, real destinations, display changes, VoiceOver and Reduce Motion. Unit tests and hosted views do not establish these.

Developer ID, notarization/stapling and Sparkle remain deferred until beta feedback and the membership decision. No public release or automated appcast is authorized by completing the local preparation.

## Development CLI

```sh
make cli
.build/release/pshot layout --in fixtures/wide-dashboard.png --look dawn --shape fit --json
```

Consumers must pin a commit, build `pshot` from that checkout and retain their own parity suite. `make check` verifies the JSON contract and the removed-frame error. The CLI is excluded from both release and debug app bundles.
