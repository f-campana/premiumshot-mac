# Icon artwork

`AppIcon.icon` is an editable macOS 26 Icon Composer document. The Dawn field uses the product palette; the dark window and corner highlight are original vector artwork. Apple supplies the platform mask, appearance variants and material rendering during asset compilation.

To regenerate the two source PNGs using the installed SDK:

```sh
swift scripts/make-icon-art.swift Resources/AppIcon.icon/Assets
```

Review the icon in Icon Composer's Default, Dark and Mono appearances and at 16, 32, 128 and 512 pixels before accepting a change. The app build compiles this document into `Assets.car` and an `AppIcon.icns` fallback. No source artwork or developer tool is copied into the bundle.

The menu glyph is drawn as an 18 pt template by `Sources/PremiumShotApp/MenuBarGlyph.swift`, with 1 pt strokes.

## Installer layout

`Installer.tiff` contains a 600 × 400 pt background at 1× and 2×. The packaging step generates Finder's layout on the mounted image so the background alias carries that image's real volume and file IDs. The alias names the volume and the path relative to its root; it contains no home or source-checkout path. The detailed installation notes remain in the image for reference, hidden from the two-icon installation view. The volume uses the compiled app icon. Finder saves the full window frame, so its default size is 600 × 432 pt: the artwork's 400 pt height plus the 32 pt title bar measured on macOS 26 with optional bars hidden. The packaging verifier reads the actual TIFF size and saved bounds and rejects a clipped or scrolled viewport. These resources are packaging artwork and never enter the app bundle.

Regenerate the background with `swift scripts/make-installer-art.swift Resources/Installer.tiff`. Release packaging installs hash-pinned `ds-store` and `mac-alias` into the generated build directory to write the layout. They are packaging tools, excluded from the app and DMG. App builds and `make check` do not need these packages. Review the mounted image in Finder whenever changing it.
