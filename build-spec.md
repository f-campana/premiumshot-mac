# Build spec: screenshot panel (working title "PremiumShot")

Version 0.3, 2026-10-07. Author: Claude. Reviewers: Codex (independent code and rendering review), Fabien (acceptance).
Status: **M0 built and handed off for review** (`docs/M0-handoff.md`). M1 waits for the spike gate in section 4.

**Reference pin.** Visual and interaction reference: the published mock, version `1791308516-09bd` (https://claude.ai/artifact/7f2bwHJPkSvLxidUSM3kqy). Local copy `mock/panel-mock.html`, SHA-256 `5904e9ad4a32102c919c86ba9dc8f560f6d865dbf9925f6575619b8bdeeee545`. If the file's hash changes, this spec is stale until updated. Every intentional deviation from the mock is listed in the milestone hand-off.

---

## 1. Goal

A personal Mac utility that turns the screenshot on your clipboard into a good-looking image in a few seconds.

**The loop:** press the hotkey → the clipboard image appears already styled with your last look → optionally change look, space or shape → Copy, Save or drag it out → dismiss, and focus is still in the app you were using.

**Governing principle:** fewer features, each finished exceptionally well. If something is not needed for that loop, it waits.

**Use:** Fabien's own social posts, documentation and presentations. No accounts, subscriptions, quotas or distribution plan.

**Non-goals for v1:** annotations, batch, device mockups, automatic redaction, iPhone, Chrome capture, screen capture itself, cloud anything, App Store.

## 2. Roles and workflow

| Who | Does |
|---|---|
| Claude | Writes this spec, then implements it in milestones. The only agent that edits the code. |
| Codex | Reviews each milestone independently, read-only: code quality, rendering correctness, Mac integration, fidelity to the mock. Reports concrete fixes. |
| Fabien | Accepts or rejects on feel: appearance, motion, everyday use. |

Rules:
1. One implementer at a time. Codex never edits the workspace; it reports.
2. **Version control.** `git init` in the project folder, one commit per milestone. Synthetic fixtures are committed. Private screenshots live only in `corpus/private/`, which is git-ignored, and no test may depend on them.
3. **Status vocabulary.** Every check in this spec and every hand-off uses exactly four statuses: **pass**, **fail**, **unverified** (not run, with the reason), **not applicable** (with the reason). "Needs manual check" is a method, never a status: the check is run by Codex or Fabien and recorded as pass or fail.
4. Every milestone ends with a hand-off note: what was built, each check's status with its evidence, deviations from the mock, and any narrow concurrency exception (section 6).

## 3. How to read the mock

The mock is the reference for **behaviour, proportions, copy and motion**. Its numbers are the starting point for rendering and layout (section 7), but they are hypotheses to be tuned on real screenshots. Where the mock simulates something (Save, drag-out, real clipboard, notch, colour, grain), this spec says what the app must really do.

## 4. Milestones and gates

| | Scope | Exit |
|---|---|---|
| **M0 Foundations and spike** | Repo and build scripts. `Core` module (recipe, validation, layout, looks, renderer) with the CLI, synthetic fixtures and tests. App skeleton: menu bar item, global hotkey, floating panel with a static preview and working Copy. **Two dev-only harnesses:** a drag source for S8 and a scroll/gesture logger for S10. The spike checklist (section 10). | Core passes its automated tests. Every spike item has a status with evidence. Codex reviews. |
| **M1 The loop** | Sections 5 to 9: import, five looks, Adjust drawer, Inspect with zoom, Copy, Save, drag-out, dismiss, undo and redo, light and dark, motion, persistence of the last recipe, recoverable errors. | **Every required check in section 11 is pass.** Then Fabien uses it for a few days (Q4). |
| **M2 Daily polish** | User-saved looks, manual solid redaction, frame title and URL text, "Open latest screenshot" hardening, launch at login. | Decided after M1 feedback. |
| **M3 Optional** | Notch anchoring, Raycast script command (via the CLI), annotations, batch. | Only what real use justifies. |

**Gate M0 → M1.** M1 starts only when every **blocking** spike item is pass, or Fabien has accepted a concrete fallback in writing. Blocking: S1, S2, S5, S6, S7, S8. Non-blocking, each with a default fallback: S3 (centre on the main screen), S4 (dismiss on outside click without pass-through), S9 (ship sRGB only), S10 (pinch and +/− only; swipe follows the system direction).

**Gate M1 complete.** No required check may be fail or unverified. A "not applicable" needs a written reason that Codex accepts.

The recipe model has a slot for redactions (empty in M1) so M2 does not change the format.

## 5. Experience requirements (from the approved mock)

**States.** Empty, Compact, Expanded, Inspect. The panel is a floating, non-activating window: it takes keyboard input without making this app frontmost, so dismissing it leaves the previous app exactly as it was.

**Summon.** Global hotkey **⌘⌥⇧Space** toggles the panel. (⌥Space collided with Raycast.) It appears on the screen that contains the pointer.

**Source on summon, in order:**
1. An image file copied in Finder (checked first: Finder can also put the file's icon on the pasteboard as image data, and the file is what was meant).
2. An image on the clipboard.
3. Otherwise the empty state with a drop target.

The latest screenshot is never chosen automatically. "Open latest screenshot…" is an explicit button.

**Re-summon after Copy.** Every Copy tags the pasteboard with a private type, `com.fabien.premiumshot.session`, whose payload is the UUID of an in-memory **source session** (original decoded source plus its recipe). The app retains the last 3 sessions until quit.
- Clipboard marker matches a retained session: reopen that session (original source, last recipe).
- Marker present but no matching session (after a restart): show the empty state with "The clipboard holds an image you already polished. Paste or drop the original." and a **Use it anyway** button.
- No marker: normal source rules.

**Compact layout.** 600 × 412 pt. Preview well on top, a caption line, then one bar: five look swatches with the look name, then Adjust, Save, Copy. The bar is identical in Expanded.

**Expanded.** Adjust opens a 244 pt drawer on the right: Shape (Fit, 16:9, 4:5, 1:1, 1.91:1, with a hint line naming each), Space, Corners, Shadow (sliders with values), Frame (None, Window, Browser), Reset look, "⌘Z undo". The preview stays where it is. If the wider panel would leave the screen, it shifts left just enough to stay 24 pt inside.

**Caption.** Left: the exact output pixels, with "· capped" when the long edge limit applies. Right: "Screenshot at N% of original size" (never above 100%). Tooltips explain both.

**Copy** is always explicit. Return (preview focused) or ⌘C copies. The panel stays open. The Copy button confirms ("Copied" with a drawn check, a one-time ring around the preview, caption "Copied W × H px") **only after the pasteboard write has succeeded.** On failure it shows an inline error and no success state.

**Save** (⌘S) writes a PNG named `Screenshot YYYY-MM-DD at HH.mm.ss polished.png` to the Desktop (D5).
- It never overwrites: on a name collision append " 2", " 3" and so on.
- If access is denied or the folder is missing, show "Couldn't save to Desktop" with a **Choose folder…** button that opens a save panel; remember that choice for next time.
- Confirms in place like Copy, only after the file is written.

**Drag-out.** The preview is draggable; the drop receives a PNG file. The temp file lives in the app's cache directory and is deleted at next launch. If the temp file cannot be written, the drag does not start and the caption shows the error.

**Inspect.** Space, the magnifier on the preview, or a double-click opens a larger view over the panel. Fit to window at the floor, 400% at the ceiling; 100% means one output pixel per screen pixel; above 100% pixels are shown unsmoothed.
- **Two-finger vertical swipe: fingers up zoom in, fingers down zoom out**, regardless of the system scrolling direction (use the event's inverted-direction flag). Zoom is anchored at the pointer.
- Pinch zooms. + and − zoom. Z jumps between fit and 100%.
- A sideways swipe, dragging, or arrow keys (when zoomed) move the image.
- The readout shows pixels and zoom. A hint line explains the gesture.
- Esc leaves Inspect first, then the panel. Checkerboard behind transparent output.

**Looks.** Five built in: Dawn, Tide, Paper, Graphite, Clear (transparent). ←/→ cycles them when the preview or a swatch has focus, with a short crossfade. Arrow keys inside a radio group or slider act on that control, never on the look.

**Undo and redo** (⌘Z, ⇧⌘Z) cover look, shape, space, corners, shadow, frame and reset. Slider drags coalesce into one step. History is per source session.

**Appearance.** The panel follows the system light or dark appearance, independent of the exported look.

**Motion.** Springs and durations from the mock's Light weight (spring stiffness 340, damping ratio about 0.88; transitions about 0.62 × the Standard durations). Interruptible. Never delays Copy. Reduce Motion replaces movement with a short fade. A hidden preference `panelWeight = standard` selects the heavier first version until Fabien picks (D3).

**Hierarchy.** The screenshot dominates. Controls are quiet and progressively revealed. System font.

**Errors are recoverable.** Nothing in the loop may crash or leave the panel stuck.

| Situation | Behaviour |
|---|---|
| Clipboard data unreadable or an unsupported type | Empty state with a one-line reason and the drop target. |
| Image larger than 64 MP | Same, naming the limit. |
| Render allocation fails | Keep the previous state, show "Too large to render", suggest a smaller shape. |
| Pasteboard write fails | Inline error on Copy, panel stays open. |
| Save denied, folder missing, disk full | Message with Choose folder…; nothing is reported as saved. |
| Drag temp file fails | Drag does not start, error in the caption. |
| Corrupt saved recipe | Fall back to defaults, log once. |

### Keyboard

| Key | Action |
|---|---|
| ⌘⌥⇧Space | Summon or dismiss (global) |
| Esc | Leave Inspect, else dismiss |
| ← / → | Cycle looks (preview or swatch focused) |
| Return, ⌘C | Copy |
| ⌘S | Save |
| E | Toggle Adjust |
| Space | Toggle Inspect |
| Z, + / − (in Inspect) | Fit and 100%, zoom |
| ⌘Z, ⇧⌘Z | Undo, redo |
| ⌘V | Paste an image (empty or replace) |
| ⌘O | Open an image file |

Every control reachable and operable by keyboard, visible focus rings, VoiceOver names, and inactive content (the empty state while an image is shown, the drawer when closed) hidden from assistive technology.

## 6. Architecture and contracts

| Layer | Choice | Why |
|---|---|---|
| Interface | **SwiftUI** | Panel content, drawer, controls, motion. |
| Mac integration | **AppKit** | Non-activating panel, global hotkey, pasteboard, drag source, scroll and magnify events. |
| Rendering | **`Core` Swift package**, no UI dependency | One composition function for preview, Copy, Save, drag-out and the CLI. Testable headlessly. |
| CLI | Thin executable over `Core`, `pshot` | Lets Claude and Codex render and diff without opening the app. Later the Raycast command. |
| Dependencies | **None third-party** | Smaller surface, easier review. |

Targets: macOS 26 only (D2). Swift 6 language mode throughout.

**Concurrency.** UI and AppKit code (including `NSPanel`, which Apple declares main-actor isolated) stay on the main actor. Rendering runs off the main actor on bounded background work: a single render queue for previews that cancels stale requests, and a separate task for exports. `Core` types are `Sendable` values. No blanket relaxing of checks. Any exception (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`) is local, has a comment saying why, and is listed in the hand-off.

**Build.** From the terminal: `make test` (unit and golden tests) and `make app` (builds the app bundle). The method (Xcode project or Swift package plus a bundling script) is Claude's call, provided both commands work from a clean checkout for Codex.

**Panel.** `NSPanel`, non-activating, floating level, joins all Spaces, usable over full-screen apps, does not hide on deactivate, accepts key input. Elevation is drawn by us, in a separate click-through window behind the card (the card window is exactly card-sized), so the Light weight matches the mock and clicks around the card pass through.

**Hotkey.** Carbon `RegisterEventHotKey`, which works without the Accessibility permission. The combination is a defaults value, changeable without a rebuild.

**Presentation is separate from content.** A `PanelPresenter` seam (floating now) lets notch anchoring become a second presenter in M3 without touching the content views. Notch geometry would use the top inset height plus the left and right auxiliary areas.

**Menu bar item.** Show panel, Quit (Launch at login in M2). No Dock icon, no settings window in v1.

**Permissions.** Not sandboxed (D7): personal build, ad-hoc signed, hardened runtime. A one-time Desktop access prompt on first Save is expected.

**Privacy and networking.** The app initiates no networking and sends no telemetry: no networking APIs in our sources, no analytics or update frameworks, no remote content loading. (System frameworks may use the network for their own reasons; that is out of scope.)

### CLI contract

```
pshot render --in <image> --out <file.png>
             [--recipe <recipe.json> | --look dawn --shape fit --space 50 --radius 50 --shadow 55 --frame none]
             [--export-profile srgb|p3] [--json]
pshot layout --in <image> [--recipe <recipe.json> | same flags]    # resolved sizes only, no pixels
pshot validate <recipe.json>
```

`--json` prints the resolved output specification on stdout: `{"width":…,"height":…,"capped":bool,"screenshotScale":…,"profile":"srgb"}`. Exit codes: 0 ok, 2 usage or validation error, 3 input unreadable or unsupported, 4 input too large, 5 write failed. Errors go to stderr as one line.

### Recipe

```json
{ "version": 1, "look": "dawn", "shape": "fit", "space": 50, "radius": 50,
  "shadow": 55, "frame": "none", "redactions": [] }
```

Validation: `version` must be 1 (a newer version is rejected with a message). `look` is one of the five ids; `shape` one of `fit, 16:9, 4:5, 1:1, 1.91:1`; `frame` one of `none, window, browser`; `space`, `radius`, `shadow` integers 0 to 100. The CLI rejects invalid values with exit 2. The app, loading a saved recipe, clamps numbers and replaces unknown ids with defaults rather than failing. `redactions`, when used (M2), holds rectangles in **source-image coordinates** so they survive any scaling.

### Image input policy

Accepted: whatever ImageIO decodes among PNG, JPEG, HEIC/HEIF and TIFF. Orientation metadata is honoured and the source colour space preserved. For multi-image files (multi-page TIFF, HEIC sequences) the **primary image (frame 0)** is used. Other formats (GIF, animated, RAW, PDF) are rejected with a clear message. Source alpha is respected: the window shape and shadow come from the rounded rectangle, not from the image's alpha. Hard limit 64 megapixels.

## 7. Rendering specification

### Layout (the mock's `computeLayout`, ported as pure functions)

All lengths are in source pixels, then scaled once by the cap factor `f`.
- Window = screenshot plus frame bar. Bar height: none 0, window 56, browser 68.
- Space factor `k = lerp(0.03, 0.19, space/100)` (0.11 at the default 50).
- **Fit:** margin `m = clamp(k × min(w, h), 36, 420)`, scale `s = 1`, canvas = window + 2m.
- **Fixed shapes:** canvas 16:9 = 1920 × 1080, 4:5 = 1080 × 1350, 1:1 = 1080 × 1080, 1.91:1 = 1200 × 630. `m = k × min(W, H)`, `s = min((W − 2m)/w, (H − 2m)/h, 1)`. **Never enlarged.**
- **Cap:** `f = min(1, 4096 / longEdge)` applied to canvas, scale and every length. Output dimensions are rounded integers. **The caption, the file and the clipboard image all use this one resolved size.**
- The window is centred, lifted by 0.8% of the canvas height.
- Corner radius `= lerp(0, 64, radius/100) × s`.
- **Pixel grid.** The window rectangle is snapped to integer output pixels (origin and size). At `s = 1` (Fit, any frame) the screenshot is placed on the pixel grid and drawn **without interpolation**, so text stays crisp.

These numbers are a starting point. Tuning them against the corpus is expected; any change is made in `Core` and recorded in the hand-off.

### Looks

| Look | Base | Blobs (x, y, radius × longest edge, colour) | Shadow × | Shadow tint |
|---|---|---|---|---|
| Dawn | #f2d6cb | (.10,.05,.85,#ffb59e) (.95,.10,.70,#dcc4ff) (.85,1,.90,#ffd8a6) (0,.95,.70,#f7b6cc) | 0.80 | 96,44,44 |
| Tide | #0b2a48 | (.1,.05,.9,#1f72e6) (.95,.95,.95,#14b8a6) (.55,.55,.7,#0a1f3a) (.95,.05,.5,#7b93ff) | 1.15 | 0,10,34 |
| Paper | #ecebe6 | (.2,.05,.9,#ffffff) (.95,1,.9,#dad7cc) | 0.65 | 44,40,30 |
| Graphite | #121419 | (.15,0,.9,#2b3342) (.95,.95,.9,#1b2230) (.9,.1,.5,#3a3150) | 1.40 | 0,0,0 |
| Clear | transparent | none | 1.00 | 20,26,48 |

Each blob is a radial gradient from its colour to transparent. **All hex values are sRGB**: they are converted into the working space before blending.

### Grain

Grain keeps gradients from banding. It is a **deterministic field defined on output pixel coordinates**: `value = hash(x, y, fixedSeed)`, evaluated at the resolved output size and blended with Overlay at 0.13. The mock's random tiled noise is replaced by this.
- The settled preview is the **downsampled export**: the same field, the same area-averaging downsample as the image. Cache the grain layer per output size.
- Frames drawn while a slider or animation is moving may use a faster path (for example lower-resolution grain with amplitude scaled by the preview-to-output ratio). The final settled frame must use the exact path.

### Shadow

Two layers, with `T = (shadow/100) × look multiplier` and `L = √(window area)` in output pixels:
- Key: blur `0.05·L·T`, offset-Y `0.032·L·T`, alpha `min(0.6, 0.10 + 0.26·T)`.
- Ambient: blur `0.18·L·T`, offset-Y `0.05·L·T`, alpha `min(0.4, 0.05 + 0.14·T)`.

Match the mock visually; Core Graphics and canvas blur are not numerically identical.

### Frames

None, Window (traffic lights, no title text in M1), Browser (traffic lights and an empty address pill in M1; text arrives in M2). Chrome is dark when the mean luminance of the screenshot's top strip is below 0.42. A 1 px hairline outlines the window.

### Colour, determinism, transparency

- **Working space and export profile.** M0 renders **in the export colour space**: sRGB by default, Display P3 on request. Two 8-bit conversions (source to P3 to sRGB) cannot keep an sRGB screenshot bit-exact, which R5 requires. A wide-gamut working space is only worth adding if spike S9 shows it matters (D4). Never write an untagged image.
- **The preview shows the export colour policy.** It is rendered through the export profile (a soft proof), so gamut limits match what the file will show. Only the panel's own UI is left to the system.
- **Deterministic.** The same recipe, input and export profile give identical pixels on every run.
- **Transparency.** Clear exports a PNG with real alpha: corners and shadow premultiplied correctly, no dark fringe on a light backdrop. The clipboard image keeps alpha.
- **Privacy.** No source image is written to disk. Only Save and the drag-out temp file write anything.

### Performance budgets (on Fabien's Mac)

Summon to first frame ≤ 150 ms with a clipboard image. Look and slider changes redraw the preview at ≥ 50 fps for the wide sample. Copy of a 4096 px export ≤ 400 ms. Peak memory for the largest export ≤ 600 MB. Layer caching (background, shadow, grain) is allowed if it cannot change output.

## 8. Persistence

- The last-used recipe, in user defaults, restored on next summon.
- Hidden preferences: `panelWeight`, summon key combination, export profile, save folder.
- Nothing else persists in M1. M2 adds user-saved looks as a small JSON file in Application Support.

## 9. Out of scope for M1 (do not build)

Settings window, sync, accounts, updater, telemetry, JPEG or WebP output, custom canvas size, annotations, redaction UI, notch, iPhone, Chrome extension, Raycast command.

## 10. Spike checklist (M0)

Each item gets one of the four statuses with evidence. **B** = blocking for the M1 gate (section 4).

| # | | Check | Pass |
|---|---|---|---|
| S1 | B | Panel focus | Summon, use keys, dismiss: the previously active app stays active and keeps its selection. |
| S2 | B | Spaces and full screen | Appears on the current Space and over a full-screen app without switching Space. |
| S3 | | Displays | Appears on the pointer's screen, including an external display. |
| S4 | | Click outside | Dismisses; clicks in the transparent padding pass through. |
| S5 | B | Hotkey | ⌘⌥⇧Space works with Raycast running and without Accessibility permission. |
| S6 | B | Clipboard read | PNG, TIFF, JPEG, HEIC data and a copied image file are all recognised. |
| S7 | B | Clipboard write | Paste the result into X composer in a browser, Slack, Keynote, Notion, Notes, Preview: size correct, colours match, alpha where supported. |
| S8 | B | Drag-out | Using the M0 drag harness, drop into Finder, Slack and a browser upload zone. |
| S9 | | Colour | A vivid Display P3 gradient and a UI screenshot exported as sRGB look acceptable beside the P3 original. Record whether P3 export is worth offering. |
| S10 | | Scroll direction | Using the M0 gesture logger, two-finger swipe zoom follows finger direction with natural scrolling both on and off. |

Items that need a human at the keyboard (S1 to S4, S7, S8, S10) are run by Codex or Fabien from a short script the hand-off provides. Until run, their status is **unverified**.

## 11. Acceptance criteria

Every criterion below is **required** for M1 to be complete. Method: **A** = automated test in `make test`, **R** = Codex review of code or rendered output, **M** = run by Codex or Fabien and recorded.

**Rendering**

| # | Criterion | Method |
|---|---|---|
| R1 | Preview and export call the same composition code. At identical dimensions they are pixel-identical. The settled preview matches the downsampled export, grain included, within a tolerance measured in M0 and written into the test. | A, R |
| R2 | Caption pixels = saved file pixels = clipboard image pixels (read back from the pasteboard). | A, M |
| R3 | Long edge never exceeds 4096; "· capped" shows exactly when it was reduced. | A |
| R4 | The same recipe, input and export profile give identical pixel data across runs. | A |
| R5 | **Pixel preservation.** At Fit, s = 1, no frame, the screenshot is placed on integer output coordinates and drawn without interpolation. In the opaque interior, excluding the rounded-corner zones and the 1 px hairline, output pixels equal the source **after the same colour conversion applied to the source alone**: exactly equal when source and output colour spaces match, within ±1 code value otherwise. Text crispness at 100% is checked by eye on the corpus. | A, M |
| R6 | No shape ever enlarges the screenshot (s ≤ 1). | A |
| R7 | Clear exports real alpha: composited on white and on black shows no fringe, shadow alpha is smooth. | A, R |
| R8 | Every export carries an embedded colour profile matching the stated export profile. A P3 test patch converts as expected within tolerance. Look colours are interpreted as sRGB. | A |
| R9 | The synthetic corpus (tall, wide, small dialog, ultrawide, thin crop, HEIC, rotated, wide-gamut patches) renders without clipping at default settings in every look, shape and frame. | A, R |

**Interaction**

| # | Criterion | Method |
|---|---|---|
| I1 | All states and transitions in section 5 behave as in the mock, including Expanded keeping the preview in place. | M |
| I2 | Copy confirms only after the pasteboard write succeeded; a forced failure shows an error, not a check. | A, M |
| I3 | Arrow keys on a focused radio option or slider never change the look. ←/→ on the preview does. | A, M |
| I4 | Inspect: zoom limits, pointer-anchored zoom, swipe direction, pinch, +/−, Z, Esc order. | A (math), M (gestures) |
| I5 | Undo and redo restore every setting; a slider drag is one step. | A |
| I6 | Re-summon after Copy reopens the matching source session; with no session it shows the "already polished" empty state. | A, M |
| I7 | Drag-out and Save produce valid PNGs of the resolved size. Save never overwrites (collision suffix) and recovers from denied access. | A, M |
| I8 | Reduce Motion removes movement. No animation delays Copy. | M, R |
| I9 | Every row of the error table in section 5 behaves as written. | A, M |

**Mac integration**

| # | Criterion | Method |
|---|---|---|
| X1 | Spike items S1 to S10 each have a status and evidence; any fail has an explained fallback. | R |
| X2 | **No app-initiated networking or telemetry.** Source search finds no networking APIs, analytics or update frameworks; and a runtime check while exercising the full loop shows no outbound connections from the app process (for example with `nettop` or Little Snitch). | R, M |
| X3 | No source image on disk after use except Save output and the cleaned-up drag temp file. | M, R |
| X4 | Light and dark appearance both correct. Increase Contrast does not break legibility. | M |

**Quality bar**

| # | Criterion | Method |
|---|---|---|
| Q1 | Performance budgets in section 7 met, with measurements in the hand-off. | M |
| Q2 | Full keyboard operation, visible focus, VoiceOver names, inactive content hidden from assistive technology. | M, R |
| Q3 | `make test` and `make app` pass from a clean checkout. | A |
| Q4 | Fabien uses the app for his real posts for several days and accepts the look and feel. | M |

## 12. Decisions for review

My default is in bold. Codex has agreed D1 to D9. Change any before M0 starts.

| # | Decision | Default |
|---|---|---|
| D1 | Working name and bundle identifier | **PremiumShot**, `com.fabien.premiumshot` |
| D2 | Deployment target | **macOS 26 only** |
| D3 | Panel weight | **Light**, Standard behind a hidden preference until Fabien picks |
| D4 | Export colour | **sRGB-tagged PNG**; the working space follows spike S9 |
| D5 | Save location | **Desktop**, changeable by a hidden preference or the Choose folder… fallback |
| D6 | Re-summon after Copy | **Reopen the matching in-memory source session** |
| D7 | Sandbox | **Off** for the personal build |
| D8 | Version control | **`git init`, one commit per milestone, synthetic fixtures committed, `corpus/private/` ignored** |
| D9 | Order | **M0 spike first, then M1** |

## 13. Changes in v0.3 (after M0)

Colour: render in the export space instead of Display P3 (reason above). Clipboard order: file before image data. Shadow: separate click-through window. Findings F1 (shadow tail at the canvas edge) and F2 (speed) are open decisions listed in `docs/M0-handoff.md`.

## 14. Changes since v0.1

Adopted from Codex's review: pixel-equality criterion redefined (R5) with grid-aligned 1:1 placement; look colours read as sRGB and the preview shows the export colour policy; grain anchored in output coordinates, with the settled preview equal to the downsampled export; pass / fail / unverified / not applicable statuses, a blocking subset of the spike, and drag and gesture harnesses in M0; the networking check rewritten (X2); CLI, recipe validation, image-selection policy, recoverable errors, Save collision and denial handling, and a session-based pasteboard marker defined; the approved mock pinned by hash; concurrency tightened to main-actor UI plus bounded background rendering with documented exceptions only.
Earlier, from the debate: floating panel first and notch later; SwiftUI plus AppKit plus a small shared renderer with a thin CLI; no speculative extension infrastructure; colour treated as something to test; explicit Copy confirmation after delivery; keyboard focus rules; shortcut ⌘⌥⇧Space; Claude writes the spec and builds, Codex and Fabien review and QA.
