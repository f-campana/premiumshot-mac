# M0 hand-off: foundations and spike

Author: Claude. For: Codex (review and verification), Fabien (manual spike checks).
Spec: `build-spec.md` v0.3. Reference mock pinned in the spec by SHA-256.

**Where I stopped.** Fabien asked me to stop testing and leave verification to Codex. The last **full** run of `swift test` was 51 tests, 0 failures. After it I added one test (shadow clipping, section 4) and the `pshot bench` command, and ran only that test and `RendererTests` (10 tests, 0 failures). I then reverted one experiment (parallel grain, no measurable gain) and did **not** re-run anything. So the tree you receive is the code behind those runs plus a revert to the previously tested `Grain.swift`; please run `make test` first.

Nothing was committed before this hand-off; the commit that carries it is the baseline for review diffs.

---

## 1. What exists

| Path | What |
|---|---|
| `Sources/PremiumShotCore` | Recipe (strict and lenient decoding, validation), layout engine (the one resolved output spec), five looks, renderer (Core Graphics), deterministic grain, frames, image loading (orientation, 64 MP limit, format policy), PNG output, gesture direction math, error type with CLI exit codes. No UI. |
| `Sources/pshot` | CLI: `render`, `layout`, `validate`, `bench`. Hand-parsed arguments, no dependencies. |
| `Sources/PremiumShotMac` | AppKit layer: pasteboard read and write with the session marker, source sessions (last 3), summon resolution, Carbon global hotkey, latest-wins render queue, floating non-activating panel with a separate click-through shadow window, M0 panel model and SwiftUI view, drag temp files, last-recipe persistence, two spike harness windows. |
| `Sources/PremiumShotApp` | Menu bar app (no Dock icon): status item, hotkey, Spike Tools submenu. |
| `Sources/fixturegen` | Writes the synthetic fixtures. |
| `fixtures/` | Nine synthetic images (wide dark dashboard, tall article, small dialog, ultrawide editor, thin strip, Display P3 patches, exact-pixel pattern, EXIF-rotated JPEG, HEIC) and `golden/` (eight 200 px settled-preview goldens). All invented content. |
| `Tests/` | Core: layout, recipe, renderer, image input, goldens. Mac: pasteboard, sessions, model, platform. |
| `Makefile`, `scripts/bundle-app.sh` | `make test`, `make app`, `make run`, `make fixtures`, `make goldens`. |

### Running it

```
make test                        # unit and golden tests (about 30 s in debug)
make app && open build/PremiumShot.app

.build/release/pshot render --in fixtures/wide-dashboard.png --out out/x.png --look tide --shape 16:9 --frame window --json
.build/release/pshot layout --in fixtures/tall-article.png --json
.build/release/pshot bench  --in fixtures/tall-article.png --runs 5     # per-stage timings
```

App dev flags (run `build/PremiumShot.app/Contents/MacOS/PremiumShotApp`):
`--summon` shows the panel at launch, `--image <path>` uses a file instead of the clipboard, `--snapshot <png>` writes the panel content and quits, `--self-test` prints the hotkey registration status and quits. Behind-window blur is not captured by `--snapshot`.

## 2. What M0 deliberately does not have

No look swatches, Adjust drawer, Inspect, Save, drag-out from the panel, undo, or motion. The panel shows the preview, the caption, the look name and a working Copy. Those are M1.

## 3. Checks and their status

Statuses: **pass**, **fail**, **unverified** (with the reason), **not applicable**.

### Spike (spec section 10). B = blocking for the M1 gate

| # | | Status | Evidence and what is missing |
|---|---|---|---|
| S1 | B | **unverified** | After the panel is shown through the app's own code path, the frontmost app is unchanged (Finder before and after). Not tested: keys reaching the panel, and the previous app keeping its selection. Manual script below. |
| S2 | B | **unverified** | Needs a full-screen app. Collection behaviour is set to join all Spaces and full-screen auxiliary. |
| S3 | | **unverified** | One observation: with the pointer on an external display, the card opened there (x = −1118, 600 × 412, plus an 800 × 572 shadow window). The main-display case was not observed. |
| S4 | | **unverified** | The shadow lives in a separate window with `ignoresMouseEvents = true`, and the card window is exactly card-sized, so there is no padding to intercept clicks. Outside-click dismissal uses a global mouse monitor. Neither was exercised. |
| S5 | B | **unverified** (half pass) | `PremiumShotApp --self-test` registered ⌘⌥⇧Space with status 0 while Raycast (pid 34226) was running, and a unit test proves a second owner of the same combination gets `eventHotKeyExistsErr`. Pressing the keys could not be tested here: posting key events needs Accessibility permission, which I do not have. |
| S6 | B | **pass** | Tests read PNG, TIFF, HEIC, JPEG data and a copied image file from private pasteboards; a file wins over an accompanying Finder icon; empty, junk, text and missing-file pasteboards are recoverable. Caveat: synthetic pasteboards. Real-world check: copy a screenshot with ⌃⌘⇧4, then summon. |
| S7 | B | **unverified** | In-process: the PNG written to a pasteboard reads back at the resolved size, tagged sRGB, with the marker. Pasting into X, Slack, Keynote, Notion, Notes and Preview was not done. |
| S8 | B | **unverified** | Drag harness built (menu bar > Spike Tools > Drag-out test). Drops not tried. |
| S9 | | **unverified** | Needs a human eye. Samples: run the four `pshot render … --export-profile srgb\|p3` commands in section 5. The UI fixture is sRGB, so it should not change; the P3 patches clip by definition. |
| S10 | | **unverified** (half pass) | The four combinations of finger direction and scrolling setting are unit-tested. The logger harness is built (Spike Tools > Swipe direction logger). Real trackpad not tried. |

**Gate M0 → M1:** blocking items S1, S2, S5, S7, S8 are unverified. S6 passes. They need about ten minutes at the keyboard (script in section 6).

### Core criteria from section 11

| # | Status | Evidence |
|---|---|---|
| R1 | **pass**, re-verify in M1 | Preview is `Renderer.renderPreview`, which is the export render area-averaged down, so composition and grain cannot differ. The M1 fast interactive path does not exist yet; the tolerance test belongs with it. |
| R2 | **pass** for caption = render = clipboard | Tests: render size equals layout; `ModelTests` reads the clipboard back at the caption size. Saved file: not applicable until Save exists. |
| R3 | **pass** | Layout tests across sizes; `capped` is true exactly when the factor is below 1. |
| R4 | **pass** | Every look rendered twice, pixels identical. |
| R5 | **pass** | Exact-pattern fixture: zero mismatches in the interior for every frame and look; P3 source within ±1 of the colour-converted reference. |
| R6 | **pass** | Property test over shapes, frames, sizes and space values. |
| R7 | **pass** | Clear look: transparent corner, opaque interior, shadow colour stays on the tint (no darkening toward black). |
| R8 | **pass** | Exported PNGs decode to sRGB or Display P3 as requested. Look colours are read as sRGB. |
| R9 | **unverified** | See finding F1. Automated: all looks × shapes × frames render on the thin strip; shadow-at-edge bound. Visual review of the corpus is for Codex. |
| I2 | **pass** at model level, UI **unverified** | A forced pasteboard failure yields an error and no success state. |
| I6 | **pass** at model level, UI **unverified** | Session reopen and "already polished" paths tested. |
| I9 | **unverified** (partial pass) | Pass: unreadable and unsupported data, over 64 MP, failed pasteboard write, unwritable drag temp directory, corrupt saved recipe. Not testable here: render allocation failure. Not built: Save errors. |
| I1, I3, I4, I5, I7, I8 | **not applicable in M0** | Features arrive in M1. |
| X1 | this document | |
| X2 | **unverified** | Source search found no networking APIs (`URLSession`, `Network`, `WebKit`, sockets). The runtime check over the full loop was not done. |
| X3 | **unverified** | By reading: the only writers are `PNG.write` (CLI), `DragTempFiles.write` and the app's `--snapshot` dev flag. |
| X4, Q2, Q4 | **unverified / not applicable** | Panel UI is M1. |
| Q1 | **fail** (expected) | See finding F2. |
| Q3 | **unverified** | `make test` and `make app` passed in this checkout. Not run from a clean clone. |

## 4. Findings for review

**F1: shadow tail reaches the canvas edge.** At default settings in Fit, the faint ambient shadow has alpha up to 8/255 (about 3%) at the canvas border. Worst for thin strips (the 36 px minimum margin is smaller than the shadow), 4–5/255 for the wide, tall and ultrawide fixtures. It is inherent in the mock's margin formula and is below visibility on grained backgrounds, but it is a faint step on Clear. A test bounds it at 10/255 so it cannot get worse. Decision needed: leave it, or floor the Fit margin at the shadow extent, which changes the approved Fit sizes (for example wide 2789 × 1269 would grow).

**F2: speed.** Release timings from `pshot bench` (median of 5):

| Case | Output | Render | PNG encode |
|---|---|---|---|
| wide dashboard, Fit | 2789 × 1269 | 193 ms | 54 ms |
| tall article, Fit, capped | 1653 × 4096 | 467 ms | 116 ms |
| ultrawide, Fit | 3757 × 1757 | 398 ms | 95 ms |
| ultrawide, 16:9, Clear | 1920 × 1080 | 50 ms | 15 ms |

The Copy budget is 400 ms for a 4096 px export: tall is about 590 ms, so it fails; wide passes. Grain is not the main cost (I parallelised it, render time barely moved, and I reverted it). The cost is the background gradients and Overlay blend. Separately, today's preview renders the whole export and downsamples it (200 to 470 ms), so slider dragging at 50 fps needs the M1 fast path the spec allows. M1 plan: cache the background and grain layers per look and size, and render previews directly at preview size while a control is moving.

**F3: colour decision (deviation from the spec).** The spec said "render in Display P3, export sRGB". M0 renders **in the export colour space** (sRGB by default, P3 with `--export-profile p3`). Two 8-bit conversions cannot keep an sRGB screenshot bit-exact, and R5 requires exactness. A wide-gamut working space stays open pending S9.

## 5. Deviations from the spec and mock

1. Colour (F3).
2. **Clipboard order:** a copied image file is checked before raw image data, because Finder can also put the file's icon on the pasteboard as image data. The spec listed image data first.
3. **Shadow in a separate window** (child, click-through, mouse events ignored) instead of padding inside the card window, so clicks around the card cannot be intercepted. The shadow layers use the mock's Light and Standard values, with spread approximated by shrinking the shadow path.
4. **Caption numbers** use the system locale (a French locale shows `2 789`), the mock used en-US. One-line change if you prefer commas.
5. Source alpha: the screenshot is drawn over the background and shadow, so a source with transparency shows them through. Not tested.
6. Settled preview is a full render plus downsample (F2).
7. Window frame has no title text and the Browser frame has an empty address pill, as specified for M1.

### Concurrency exceptions

`SourceImage` and `RenderResult` are `@unchecked Sendable` (immutable values wrapping a `CGImage`). The hotkey callback uses `Unmanaged` and `MainActor.assumeIsolated`, because Carbon delivers application-target hotkey events on the main thread. No other exceptions. Rendering runs off the main actor (`RenderQueue`, latest wins; exports run detached).

## 6. Manual script for Codex or Fabien (about ten minutes)

Build and start: `make app && open build/PremiumShot.app`. A small icon appears in the menu bar. Quit it from there afterwards.

1. **S5, S1.** Copy a screenshot (⌃⌘⇧4). In another app, select some text. Press **⌘⌥⇧Space**. The panel should appear with your screenshot styled. Press **Esc**. The text selection in the other app should still be there and that app should still be frontmost. Press the hotkey again with Raycast open in the background.
2. **S3.** Repeat on each display, with the pointer on that display.
3. **S2.** Make a full-screen app (Safari, say), press the hotkey. The panel should appear over it without switching Space.
4. **S4.** With the panel open, click outside it. It should dismiss. Click just beside the card, in the faint shadow. The click should reach what is underneath.
5. **S7.** Press **Return** in the panel (or ⌘C). The caption should say "Copied W × H px". Dismiss and paste into the X composer in a browser, Slack, Keynote, Notion, Notes and Preview. Check size, colours and (with the Clear look, set through the recipe file for now) alpha.
6. **S8.** Menu bar icon > Spike Tools > Drag-out test. Drag the card into Finder, Slack and a browser upload zone. The window text reports whether each drop was accepted.
7. **S10.** Menu bar icon > Spike Tools > Swipe direction logger. Scroll with two fingers. Fingers up must always read ZOOM IN. Test with natural scrolling on and off (System Settings > Trackpad).
8. **S9.** Open `out/s9-*.png` after running the four commands below, or compare the P3 and sRGB versions side by side.

```
pshot render --in fixtures/p3-patches.png    --out out/s9-p3-patches-as-srgb.png --export-profile srgb
pshot render --in fixtures/p3-patches.png    --out out/s9-p3-patches-as-p3.png   --export-profile p3
pshot render --in fixtures/wide-dashboard.png --out out/s9-ui-srgb.png --look tide --export-profile srgb
pshot render --in fixtures/wide-dashboard.png --out out/s9-ui-p3.png   --look tide --export-profile p3
```

## 7. Where I would look hardest

1. `PanelWindow.swift`: non-activating panel plus a child shadow window; key routing through `performKeyEquivalent`/`keyDown`/`cancelOperation`; the global outside-click monitor.
2. `Hotkey.swift`: the Carbon callback and the `MainActor.assumeIsolated` call.
3. `Renderer.swift`: the shadow-only trick (casting shape drawn off canvas, shadow offset back), pixel-grid placement at 1:1, interpolation `.none` at scale 1.
4. `Pasteboard.swift`: read order, and `writePNG` confirming success by reading back.
5. The colour decision (F3) and the two findings (F1, F2), which need a decision from you.
