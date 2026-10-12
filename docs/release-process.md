# Release process

This repository owns the Mac app only. Chrome and the website release separately. The renderer CLI is kept here solely as a development tool for a consumer pinned to an exact Git revision.

## Local checks and packaging

```sh
make check
make dev-app
make release
```

`VERSION` is the only marketing-version source. `BUILD_NUMBER` records the build as `YYYYMMDDNN`, with a valid calendar date and a sequence from `01` to `99`. Increment it for every distributed candidate, even if the marketing version stays the same. The first recorded value is `2026101201`, above both legacy build 7 and the earlier review's build 4. About reads both values from the bundle.

The recorded number is stable when the same source is rebuilt locally or in CI; neither the build clock nor the Git commit count changes it. Packaging rejects an older number than any release tag, and rejects reusing a tagged number for different source. Fetch all tags before release; CI already does so. Local previews record a dirty-tree bit; release refuses a dirty tree.

The permanent bundle identifier is `app.premiumshot.mac`; the separate development app uses `app.premiumshot.mac.dev`. This deliberately changes identity from the unpublished `com.fabien.premiumshot` app. Preferences, login registration and privacy grants are not copied automatically. Before replacing that app, disable its login item; re-enable login and grant folder access in the new app as needed.

The HFS+ DMG layout is generated while its writable volume is mounted, using that volume's real background alias and a complete Finder icon-view dictionary. Hash-pinned packaging libraries are installed in `build/installer-tools` for this step and never enter the app or image. The alias must resolve to the packaged artwork after conversion and remounting. A native Finder capture is a separate appearance check; a valid alias alone does not prove the background is displayed.

`make release` cleans generated build products, runs the same quality gate, bundles only the app executable and compiled icon, ad-hoc signs with the hardened runtime and no entitlements, creates a compressed DMG with a designed 1×/2× background, custom volume icon and Applications link, verifies the DMG and emits a SHA-256 checksum and JSON build manifest. The beta currently ships Apple Silicon: Intel/Rosetta is unavailable locally, so universal support is not claimed. Fabien can test an Intel or universal candidate later if needed.

A source change requires a new commit and a new candidate. Never regenerate fixtures or goldens as part of packaging. `SUPPORT_URL=https://...` may be supplied only after the real support destination is approved and working; otherwise the menu item remains disabled.

Beta feedback uses the owner-selected `support@premiumshot.app`, linked from About and the installation notes. Email forwarding and a receive/reply check must pass before sending a beta to testers. The contact link does not establish mail delivery. Tips remain a separate, unset destination.

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
