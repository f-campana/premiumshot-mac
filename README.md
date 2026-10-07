# PremiumShot

A personal Mac utility that turns the screenshot on your clipboard into a polished image in a few seconds.
Native SwiftUI and AppKit, a small renderer package with a CLI, no third-party dependencies, no networking.

- Plan, scope, acceptance criteria: [`build-spec.md`](build-spec.md)
- Current milestone, statuses, findings and the manual check script: [`docs/M0-handoff.md`](docs/M0-handoff.md)
- Visual and interaction reference (approved mock): `mock/panel-mock.html`

```
make test        # unit and golden tests
make app         # build/PremiumShot.app
pshot render --in fixtures/wide-dashboard.png --out out/x.png --look tide --shape 16:9
```

Fixtures in `fixtures/` are synthetic. Private screenshots belong in `corpus/private/`, which is git-ignored.
