# Instructions

[← README](../README.md) · [File structure](FILE-STRUCTURE.md)

## Features

**Headshot**
- Finds the face and crops head-and-shoulders automatically (square 1:1, portrait 4:5, or uncropped)
- Outlines the person and replaces the background: keep it, blur it, use a solid colour or a studio gradient
- Auto-enhance, plus sliders for exposure, contrast, saturation and warmth
- Edge-preserving skin smoothing that only touches the person
- Before/after toggle; export as PNG or JPEG at full resolution

**Avatars**
- Six styles made from your headshot: Cartoon, Pop Art, Pencil Sketch, Duotone, Halftone, Pixel
- Export each one, with an optional circular profile-picture crop (transparent corners)

**Feedback**
- A small "Feedback" tab in the window's bottom-right corner. Feedback is saved locally to `~/Library/Application Support/HeadshotGenerator/feedback.jsonl`.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (for the Swift toolchain)

## Build

```bash
./scripts/build_app.sh
```

This builds a release binary and packages it as `build/Headshot Generator.app`, signed ad hoc. With Xcode 26 or later it compiles the Icon Composer icon (`Resources/AppIcon.icon`), which gives macOS 26's glass, dark and tinted looks. With older Xcode it uses `Resources/AppIcon.icns` instead.

The icon's artwork exists twice: the three layer SVGs in `Resources/AppIcon.icon/Assets/` and the flat `Resources/AppIcon.svg`. If you change the design, update both (open `AppIcon.icon` in Icon Composer to edit the layers), then run `scripts/make_icon.sh` to rebuild the fallback and website icons. Open it with:

```bash
open "build/Headshot Generator.app"
```

For development you can also run it straight from the package:

```bash
swift run HeadshotGenerator
```

## Usage

1. Drag a photo into the window, click **Open…** (⌘O), drop it on the app's Dock icon, or right-click it in Finder and choose **Open With → Headshot Generator**.
2. On the **Headshot** tab, choose a crop and background, and adjust light, colour and smoothing. The side panel shows whether a face and a person outline were found.
3. Click **Export Headshot…** (⌘E).
4. Switch to the **Avatars** tab and click **Export…** under any style.

If no face is found, the app crops from the centre. If no person is found (the outline covers less than 5% of the photo), the background is left as it is.

## Tests

```bash
swift test
```

The test that runs on a real face is skipped unless you point it at a portrait. It can also write its outputs to a folder:

```bash
HEADSHOT_TEST_IMAGE=/path/to/portrait.jpg HEADSHOT_TEST_OUTPUT=/tmp/out swift test
```

## Website

The site in `web/` does the same job in the browser: MediaPipe (WebAssembly) finds the face and outlines the person, and plain JavaScript does the pixel work. Your photo never leaves the browser. The first photo downloads about 12 MB of library and model files from jsDelivr and Google, and the browser caches them after that.

It's plain HTML and JavaScript with no build step. To run it locally:

```bash
cd web
npm run serve        # http://localhost:8080
```

To run its tests (Node 20 or later):

```bash
cd web
npm test
```

Every push to `main` that touches `web/` runs those tests and deploys the site to GitHub Pages (`.github/workflows/pages.yml`).
