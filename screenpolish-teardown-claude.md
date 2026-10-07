# ScreenPolish teardown (getscreenpolish.com)

Researched 2026-10-05 by Claude. Method: read every public page (home, pricing, FAQ, about, changelog, why-local, vs pages, guides, legal, sitemap), ran the live editor with a locally generated test image, and inspected the shipped JS bundle (13 chunks, about 600 KB) for limits, endpoints and logic. No account was created, no export was run, and nothing was paid for. Items marked **[inferred]** come from code reading, not from observed behaviour.

---

## 1. TL;DR

- **What it is:** a free "screenshot beautifier" that runs in a browser tab. You drop an image, get a gradient background, padding, rounded corners and a shadow, size it for a social platform, and export. Nothing is uploaded.
- **The wedge is privacy plus price, not features.** The pitch is "Private by design · No account · No watermark", at $4/mo against Screenhance at $12/mo. The feature set is deliberately thin.
- **The product is very small.** There are 12 backgrounds, 4 window frames, 9 canvas presets, a redaction tool and a 5-size social pack. There are no annotations, no device mockups, no text and no templates.
- **The landing page is the product.** The editor sits above the fold with no signup, which is the best growth mechanic they have.
- **Monetization is weak.** Every plan is watermark-free. The only levers are an export count (5 per month free), 4× resolution and the social pack. The anonymous limit lives in localStorage, so it is trivially bypassable.
- **Opportunity:** keep the local-first, no-watermark promise and own the territory they skipped. That means annotations, smart (auto-detected) redaction, device and browser mockups, custom gradients, batch and style reuse, and a capture flow.

---

## 2. Product snapshot

| | |
|---|---|
| Positioning | "Polish your screenshots. Nothing is uploaded." A "browser screenshot tool, not a design app". |
| Audience | Indie makers (release posts), devs (changelogs), designers (WIP), support and marketing. |
| Maker | Gauthier Huguenin, solo, France. Built after "repeatedly uploading sensitive client screenshots to online tools". |
| Stage | Early. Launched 2026-07-21 per the changelog. Terms of Service still carry a placeholder ("legal entity… confirmed before general availability"). The latest changelog entry is 2026-07-26. |
| Tone | "Honest freemium". No ads, no cross-site trackers, no data sale, no dark patterns on cancel. |
| Site size | 14 URLs in the sitemap: home/editor, pricing, FAQ, about, changelog, 2 guides, 2 "vs" pages, why-local, 4 legal pages. |

---

## 3. Feature inventory (observed in the live editor)

**Import**
- Accepts drag-drop, file picker and clipboard paste (⌘/Ctrl+V).
- Formats are PNG, JPEG and WebP only, with a 40 MB cap per file. There is no multi-image or batch input.
- The code contains a "Capture a visible tab with the ScreenPolish Chrome extension" flow with handoff tokens and error states. The link is not shown in the live UI, so the extension looks unreleased or gated **[inferred]**.

**Toolbar:** Replace, Undo, Redo (50 steps, edits within 1 s coalesced), Randomize style, Reset (also clears saved prefs), Redact, Pack.

**Styles**
- Settings are auto-restored from localStorage (`screenpolish.prefs.v1`).
- Saved styles are named snapshots, stored locally. There are no templates and no sharing.

**Background** (Preset / Solid / Image / None)
- Presets: 12 total, in 4 families.
  - Pastel: Morning Haze, Peach Veil, Mint Air, Lilac Tide
  - Vivid: Electric Bloom, Cobalt Ember, Tropical Night, Solar Plum
  - Light Neutral: Porcelain, Frost
  - Dark Neutral: Graphite Glow, Ink Blue
- Solid is any colour. None gives a transparent PNG. Image is a custom upload used locally.
- There is no custom gradient builder, no noise or blur controls, and no wallpapers.

**Layout**
- Aspect ratios: Auto/Original, 1:1, X 16:9, X Portrait 4:5, LinkedIn 1.91:1, Product Hunt 1.67:1, Open Graph 1.91:1, Story 9:16, Custom.
- Sliders (default, range):

  | Control | Default | Range |
  |---|---|---|
  | Padding | 12% | 0–40 |
  | Inset | 3% | 0–12, with Auto or Solid mode |
  | Screenshot scale | 90% | 30–100 |
  | Alignment | centre | ±100 on each axis, plus a 3×3 grid |

- **Adaptive inset** (their signature trick): a thin margin that continues the colours sampled from the screenshot's edge, so the capture blends into the background. It is visible in my test as a soft glow along the edges.

**Appearance**
- Corner radius: default 12, range 0–30.
- Shadow: default 55, range 0–100. The formula is blur = 0.06 × maxEdge × r, offsetY = 0.03 × maxEdge × r, alpha = 0.05 + 0.45 × r **[inferred]**.
- Frames: None, macOS Light, macOS Dark, Browser Light, Browser Dark. The browser frames include a URL pill, and the macOS ones have traffic-light dots.

**Redaction** (up to 24 regions)
- Each region is either Blur or Solid, and you can switch a region between the two.
- Regions are draggable with 8 handles, and also have X/Y/W/H sliders.
- The UI warns that "Blur is cosmetic only" and recommends solid for secrets.
- Regions are session-only: never saved to styles, prefs or anywhere else.
- There is no auto-detection of emails, tokens or card numbers.

**Social pack** (Pro)
- Five sizes in one ZIP, assembled locally: X 1920×1080, LinkedIn 1200×627, Product Hunt 1270×760, Open Graph 1200×630, and the current canvas.
- Each size has a preview. Free users can inspect the previews but cannot generate.
- Dimensions are cited to official docs, "verified 2026-07-23".

**Export**
- Formats: PNG, JPEG, WebP. Scale: 1×, 2×, 4× (4× is Pro).
- Also "Copy image" to the clipboard. The code includes `navigator.share` for the OS share sheet (the changelog's "native sharing" entry), but I did not see a Share button on desktop.
- Default canvas is 1600 px wide at the chosen ratio, so 1600×1000 for my test.
- Hard caps, with human-readable error messages ("Try 2× instead…") **[inferred]**:

  | Tier | Max edge | Max pixels | Max RGBA bytes |
  |---|---|---|---|
  | Larger (desktop-class) | 8192 | 32 MP | 128 MB |
  | Smaller | 4096 | 16 MP | 64 MB |

  Which devices get which tier is not confirmed. A UA-regex check selects between them.

**Claimed in the changelog but not found in the UI or bundle:** "lightweight brand kit" (Jul 23). No brand-kit strings appear in the shipped JS, so it is either removed or not built.

---

## 4. Pricing and entitlements

| Tier | Price | Exports | Scale | Formats | Social pack | Watermark |
|---|---|---|---|---|---|---|
| Anonymous | $0 | 1 lifetime on this device | 1×, 2× | PNG/JPEG/WebP | No | No |
| Free account | $0 | 5 per calendar month | 1×, 2× | all | No | No |
| Pro monthly | $4/mo | Unlimited | 1×, 2×, 4× | all | Yes | No |
| Pro yearly | $34/yr (29% off) | Unlimited | 1×, 2×, 4× | all | Yes | No |

How limits are enforced (from client code, privacy policy and cookies page):
- Anonymous: a localStorage counter. It is trivially resettable and is not a real gate.
- Signed in: the client POSTs `{scale, format}` plus an `Idempotency-Key` to `/api/export` before exporting. The server meters the export and returns allowed or denied. It never sees pixels, filenames or dimensions.
- Retry and idempotency records are capped at 256 per account per month.
- Refunds: 14-day EU withdrawal; otherwise no pro-rating. Billing-error exceptions apply.

---

## 5. Tech stack

**Observed**
- Next.js App Router (RSC prefetch requests, `_next/static`) and React.
- Tailwind-style utility classes and zod validation.
- Dark-only UI: `color-scheme: dark`, theme-color `#0a0a0b`.
- One single `<canvas>`. In my test the preview backing store was 2400×1500 for a 1600×1000 canvas. Rendering uses Canvas 2D (`roundRect`, `getImageData` for inset colour sampling) and `createImageBitmap` with EXIF orientation and a 30 s timeout. Export uses `toBlob`.
- Internal API: `/api/me`, `/api/export`, `/api/analytics`.
- Analytics: self-hosted Umami at `stats.hgnn.io` (cookieless, 90-day retention), plus a first-party aggregate counter of (day, event, signed-in?).
- Resource timing during import and redact showed no image uploads, which is consistent with the claim. It showed only `/api/me`, `/api/analytics` and Umami.

**Named in the privacy policy, not independently observed:** Google OAuth, Resend magic-link email, Stripe for payments.

**Browser storage:** four keys: demo-export count, editor prefs, saved styles, and a sign-out marker used to sync tabs. Cookies are limited to a session cookie and a CSRF cookie.

**Offline test:** the "why-local" page invites visitors to verify privacy with DevTools or airplane mode, which is a strong trust mechanic.

---

## 6. Growth and marketing

- **No-friction landing:** the editor is on the homepage, and the 1 anonymous export is the free sample.
- **Trust loop:** a dedicated "why local" page with verification steps, privacy copy in the hero, and the maker's story.
- **SEO surface:** the 1,800-word "make screenshots look professional" guide, a social-image-sizes reference, "vs Screenhance" and "vs design apps" pages. These are all linked from the footer.
- **Comparison claims (their own):**
  - Their $4/$34 against Screenhance's $12/$99 (plus a $6 launch pass).
  - Free tier: 5 clean exports against Screenhance's 3 watermarked PNGs.
  - They concede Screenhance has 100+ templates, 40+ device frames, App Store sets, localisation, animation and video, none of which ScreenPolish offers.
- **Public changelog:** 6 entries in 6 days (Jul 21–26). It builds credibility for a new product, but nothing newer is listed.
- **Missing:** no testimonials, no social proof, no gallery or showcase, no Product Hunt or press mentions.

---

## 7. Weaknesses and gaps (our opening)

1. **No annotation.** There are no arrows, text, callouts, numbered steps or highlights. This is the most common thing people do with screenshots.
2. **Redaction is manual only.** Competitors such as Xnapper auto-detect emails, IPs, tokens and card numbers.
3. **Frames are minimal.** Only 4 window chromes and no device mockups (phone, laptop, tablet).
4. **Backgrounds are thin.** 12 presets, no custom gradient, mesh or noise controls, and no wallpaper packs.
5. **No reuse at scale.** There is no batch, no multi-image or side-by-side layout, no shareable or exportable style, and no brand kit (despite the changelog).
6. **Input range is narrow.** PNG, JPEG and WebP only, with no HEIC, AVIF, SVG or GIF, no paste-from-URL, and no scrolling or full-page capture.
7. **Weak paywall.** Everything is watermark-free, so the only reasons to pay are 4× and the pack. The anonymous gate is client-side.
8. **Single theme.** Dark only, and desktop-first (tablet is "usable", phones are not the target).
9. **Single-maker risk.** There is no team or collab, no API, and the legal entity is still a placeholder.
10. **Possible tension in the privacy claim:** signed-in exports call a metering endpoint, so the "works offline" test only holds when signed out.

---

## 8. Competitive context

Competitor pricing below comes from third-party roundups and search snippets, so treat it as unverified.

| Tool | Notes |
|---|---|
| Screenhance | $12/mo or $99/yr per ScreenPolish's own comparison. Templates, 40+ device frames, video, GIF. |
| Xnapper | About $25 one-time, Mac. Auto-balance and auto-redact are its hooks. |
| CleanShot X | About $29 one-time, Mac. Capture-first, with a cloud add-on. |
| Pika Style | Free tier. Pro about $13/mo. Templates and device frames. |
| Shots.so | Free, basic and pro plans. Many device models, 3D, animation. |
| Shottr | Free or about $8. Capture and annotate. |

Market read: the beautifier space splits into (a) polished but heavy template or mockup suites, (b) Mac-only capture tools, and (c) ScreenPolish's lane, which is fast, private and cheap. A new entrant can win by pairing ScreenPolish's trust and speed with the features that lane lacks.

---

## 9. Recommendations for our app

**Keep (these are what works)**
- Editor on the landing page with no signup, and local-only processing with a verifiable "watch the network tab" claim.
- Smart defaults on drop (padding, inset, shadow, radius), plus the adaptive colour inset.
- Platform presets with sourced dimensions, and the one-click social pack.
- Auto-restore of settings and named saved styles.
- No watermark on any tier.

**Add (P0, MVP differentiators)**
- Annotations: arrow, box, text, numbered callouts, highlight.
- Auto-detect redaction, running locally with regex plus OCR (for example Tesseract in WASM) for emails, tokens and card numbers.
- Device and browser mockups beyond 4 frames.
- Custom gradient and mesh builder, plus a larger preset set.

**Add (P1)**
- Batch: apply a style to N images, with ZIP export.
- Shareable style via URL or JSON, and brand kit (colours, logo, fixed frame).
- HEIC and AVIF import.
- Chrome extension for visible-tab and full-page capture, with the same local handoff.
- Light theme, and a PWA with a real offline mode.

**Add (P2)**
- Multi-image layouts, before/after, and animated export.
- Keyboard-shortcut layer, and a native share sheet on desktop where supported.

**Monetization to test (their thin paywall is the opening)**
- Keep free generous (clean exports, no watermark). Gate the value-add features instead: auto-redact, batch, brand kit, extension capture, device mockups and 4×.
- Keep metering server-side but light: counters only, never pixels.
- Price in the same $4–6/mo band with a yearly discount, or a one-time option to differentiate from subscription fatigue.

**Do not copy**
- A client-only anonymous gate as the sole barrier.
- Changelog claims for features not shipped (their brand kit).
- A dark-only UI.

---

## 10. Not verified (follow up if it matters)

- Actual export quality and file size. I ran no export, to avoid consuming the anonymous demo and triggering a download.
- The Pro and signed-in experience: Stripe flow, billing portal, the generated ZIP.
- Whether the Chrome extension exists, and where its link is shown.
- Mobile and tablet behaviour of the editor, and which devices get the 4096/16 MP caps.
- The social-image-sizes guide (not read; the other guide was only summarised), and the hosting provider.
