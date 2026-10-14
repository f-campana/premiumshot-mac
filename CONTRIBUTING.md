# Contributing

Requires macOS 26 and Xcode 26.6 or a compatible Swift 6.2+ toolchain with the macOS SDK. The icon build uses Apple's asset compiler.

Start a small branch from `main`. Explain the observable problem and resulting behavior in the PR; use a Conventional Commit title such as `fix: preserve a screenshot after a failed drop`. Run `make check` before review. Relevant tests should establish behavior, not repeat an implementation. Don't change rendering goldens without an accepted visual change.

`make dev-app` produces an isolated debug bundle with the native QA flags. Diagnostic captures show hosted content, not the desktop or full interaction. See [release process](docs/release-process.md) for packaging and review gates.

No personal screenshots, credentials or generated build products belong in a PR. Tests must leave the user's clipboard, preferences and login items alone. Keep agent instructions in [AGENTS.md](AGENTS.md) in view.
