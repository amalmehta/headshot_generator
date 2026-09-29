# File structure

[← README](../README.md) · [Instructions](INSTRUCTIONS.md)

```
Sources/HeadshotCore/        image pipeline: analysis, rendering, framing, avatar styles
Sources/HeadshotGenerator/   SwiftUI app and feedback tab
Tests/HeadshotCoreTests/     unit tests
scripts/build_app.sh         builds the .app bundle
scripts/make_icon.sh         regenerates the Mac and website icons from Resources/AppIcon.svg (needs rsvg-convert)
Resources/                   app icon: AppIcon.icon (Icon Composer, used by the build), AppIcon.svg (flat source for the .icns fallback and website icons), AppIcon.icns
web/                         website: index.html, styles.css, icons, js/ (framing, imageops, avatars, vision, app), tests/
```
