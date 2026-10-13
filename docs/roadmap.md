# Mac roadmap

Approved 13 October 2026. The product remains a small, local screenshot finishing tool: few decisions, trustworthy output and refined native interaction.

## Delivery before expansion

1. Prove the exact beta DMG in Finder, or use a plain app-and-Applications image with instructions in the release notes and download page.
2. Verify support@premiumshot.app receiving and replying; enable Send feedback only after evidence is recorded.
3. Establish downloaded installation, first launch, permission recovery and login behaviour on a clean account or second Mac.
4. Collect and triage beta feedback, then settle updates and signing before product expansion.

Crop's brief may be prepared during beta. Product implementation remains in Backlog until beta feedback has been reviewed.

## Product priorities

| Order | Addition | Boundary |
|---|---|---|
| 1 | Crop in Inspect | First implementation slice alone. Brief the selection, aspect lock, source coordinates, undo/cancel, source fidelity and export identity. |
| 2 | Opaque redaction | Brief beside crop as a sibling using the same source-editing seam. Begin with one solid rectangular cover tool. |
| 3 | Global Custom lightness | One global control. Decide its home before implementation: the fixed 412 pt drawer is already full. |
| Conditional | Saved looks | Only on beta demand. The last-used recipe already persists; consider a few unnamed slots before a preset manager. |
| Low priority | Custom orientation | First consider whether the spatial field can solve the need without another control. Drawer capacity applies. |
| Conditional | Annotations | Only after redaction and evidence of demand. Preview-first markup remains a valid workflow. |
| Declined | Via and notch anchoring | Keep Custom to two endpoint decisions and preserve the focused floating editor. |

Intel support remains conditional on a compatible device, an architecture-specific build and native testing. In-app updates require a separate feasibility/security brief for the selected distribution model; updater signing and Apple Developer ID/notarization are distinct decisions.

## Tracking and acceptance

Linear holds one canonical work item per addition or concrete gap. GitHub holds source, reviews, CI and releases; implementation chats link their issue, base revision, branch and PR. The shared release tracker holds cross-product gates and evidence links, without duplicating issue statuses.

Each issue contains a short problem/outcome/scope brief, software contracts, dependencies and explicit acceptance checks. Crop and annotations need fuller flow specifications before coding. A required Evidence section links the exact revision, checks and native captures; it stays marked unverified where the workflow has not been exercised. A merged PR alone does not close native or craft acceptance.

Keep one implementation owner for shared geometry/colour/state and serialize native QA on one Mac. Preserve accepted rendering and motion; do not expand the surface or refresh goldens to make a check pass.
