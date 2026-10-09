# PremiumShot for Mac

A native Mac utility that turns a screenshot into a polished image. SwiftUI and AppKit provide the editor; Core Graphics and ImageIO render and export the result. No third-party dependencies or network services are required.

## Build and run

Requires macOS 26 and Swift 6.2 or later, with the macOS SDK and command-line developer tools installed.

```sh
make test
make app
open build/PremiumShot.app
```

`make app` creates an ad-hoc signed bundle for local use and verifies its signature. It does not notarize the app for distribution. `CONFIG=debug make app` builds a debug bundle; release is the default. Build products are ignored by Git.

Current version: **0.1.5 (7)**.

## Use

Launch the app, then summon its panel with **⌘⌥⇧Space** or the menu-bar item. It imports the image on the clipboard. You can also paste, drop an image, or choose **Open latest screenshot** from the empty state.

- Choose Dawn, Tide, Paper, Graphite, Clear, or Custom.
- Open **Adjust** with **E** to change Shape, Space, Corners and Shadow. Custom provides two hue handles and Randomize.
- Click the preview and press **Space** to enter Inspect. Fit, actual size, zoom and pan are available there.
- Use **Return** or **⌘C** to copy, **Save** to write a PNG to Desktop, or drag the preview into another app.
- Use **⌘Z** and **⇧⌘Z** to undo and redo style changes.
- Use the trash button, or focus the preview and press **Delete**, to remove the screenshot from the session.
- **Esc** closes Inspect first, then dismisses the panel.

Removing a screenshot leaves its file and the clipboard untouched. The panel uses a fixed position on the pointer's display. Look, custom hue and Shadow edits preserve the composition; Space controls its margins.

## Source layout

- `Sources/PremiumShotApp`: application lifecycle, menu-bar item and global shortcut.
- `Sources/PremiumShotMac`: native editor, presentation, image import, history, clipboard and file output.
- `Sources/PremiumShotCore`: layout, colour, rendering, image decoding and PNG encoding.
- `Tests`: rendering and native integration regressions.
- `fixtures`: synthetic input images and reference renders required by the tests.
- `scripts/bundle-app.sh`: app packaging and local signing.

The package exposes only the Mac app executable. Tests use private pasteboards and isolated preferences. Reference images can be updated with `make goldens` after an intentional rendering change; do not update them to conceal a regression.

## Native QA support

Existing developer flags remain available for maintaining the app:

```sh
build/PremiumShot.app/Contents/MacOS/PremiumShotApp --qa --image fixtures/wide-dashboard.png
build/PremiumShot.app/Contents/MacOS/PremiumShotApp --image fixtures/wide-dashboard.png --snapshot /tmp/premiumshot.png
```

`--qa` uses private preferences and clipboard state. `--snapshot` writes the card content and a companion JSON of runtime bounds, then exits; it does not capture the desktop or establish live interaction or motion quality. Add `--expanded`, `--inspect`, `--dark`, `--look <id>` or `--shape <id>` for a particular state. `--self-test` checks hotkey registration; actual hotkey delivery still needs a native check. `--bench-workflow --image <path>` supports workflow measurement, and `--spike-tools` exposes the existing drag and gesture diagnostics.

## Project status

Extraction verification on 2026-10-09: **124/124 release tests pass**, with no skips; the release bundle builds and passes signature verification. App sources, tests, fixtures and the packaging script match the source project byte for byte. Local verification logs and the copy manifest are in Git-ignored `reports/extraction-2026-10-09/`.

Fabien accepted the appearance, behaviour and perceived motion of 0.1.4. Version 0.1.5 fixes the subsequent E and Space transition interruptions. Automated checks and static captures do not establish all native integration: full-screen Spaces, multiple displays, physical drag-and-drop, real trackpad input and all destination apps still need their remaining manual checks. Numerical motion-recording criteria have not been measured.

Future ideas are recorded only: screenshot cropping in Inspect and Preview-style annotation. Neither is part of this release.

This source project was extracted on 2026-10-09 from `../premiumscreenshot`, which retains the historical specs, review evidence, mockup, CLI, fixture generator, website and browser extension. Git history is preserved here; no build or test depends on that directory.
