# Icon artwork

`AppIcon.icon` is an editable macOS 26 Icon Composer document. The Dawn field uses the product palette; the dark window and corner highlight are original vector artwork. Apple supplies the platform mask, appearance variants and material rendering during asset compilation.

To regenerate the two source PNGs using the installed SDK:

```sh
swift scripts/make-icon-art.swift Resources/AppIcon.icon/Assets
```

Review the icon in Icon Composer's Default, Dark and Mono appearances and at 16, 32, 128 and 512 pixels before accepting a change. The app build compiles this document into `Assets.car` and an `AppIcon.icns` fallback. No source artwork or developer tool is copied into the bundle.

The menu glyph is drawn as an 18 pt template by `Sources/PremiumShotApp/MenuBarGlyph.swift`, with 1 pt strokes.

## Installer layout

`DMGLayout.ds-store` is the Finder layout copied to the disk image root. It contains only the three installer filenames, their positions and the folder's view settings: a 600 × 360 pt white icon view, with the app and Applications shortcut above the installation notes. It contains no source paths or personal Finder metadata. It is packaging artwork and is never copied into the app.

The template was generated once with `ds-store` 1.3.1 from native Finder view settings. Normal builds and CI copy the template directly and require no Python packages. Review the mounted image in Finder whenever changing it.
