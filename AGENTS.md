# Agent instructions

PremiumShot is a native macOS 26 screenshot finishing tool. Preserve the accepted editor, renderer and motion. Crop and annotations remain ideas; do not add them during release preparation.

## Working here

- Use short-lived branches from `main`, Conventional Commits and semantic PR titles.
- Read the relevant source and tests before editing. Keep fixes scoped; do not reformat untouched files.
- `make check` is the quality gate: release tests, signed bundle inspection and the dev CLI contract.
- `make dev-app` builds diagnostics into a separate `PremiumShot Dev.app`. Release builds must compile all diagnostics out.
- `make release` requires a clean committed tree and packages an ad-hoc private beta. It never publishes.
- Never update golden images to hide a regression. Renderer changes require explicit visual acceptance.
- Tests use private pasteboards and isolated preferences. Never mutate the user's clipboard, login registration, privacy grants or installed app to make a test pass.
- Native window tests must run without concurrent mouse/keyboard input. Report unavailable native checks separately from automated or hosted-view evidence.
- Never claim signing is notarization, emulation is another Mac, or a hosted capture proves physical interaction.
- Preserve existing SwiftPM/AppKit/SwiftUI choices. Consult the shared Foundry skill for relevant architecture, acceptance or agent-documentation changes if it is available; its frontend stack defaults do not replace this native stack.
- Don't commit secrets, personal screenshots or local reports. Don't rewrite shared history or use destructive Git commands without explicit authorization.

## Boundaries

`PremiumShotCore` owns geometry, colours, decoding and output. `PremiumShotMac` owns editor state and native integration. `PremiumShotApp` owns lifecycle, menu, bundle links and DEBUG-only developer entry points. The `Tools/pshot` executable is a development parity tool; it never goes into the app bundle. No third-party runtime dependencies, analytics or screenshot uploads.

## Delivery

State what changed, why, checks and evidence, and open native or owner decisions. Leave concrete review material before requesting release approval. Publishing a tag/release, installing a candidate and enabling paid signing/updating are separate actions.
