PROJECT NAME: headshot_generator

META-INSTRUCTIONS:

<Read it all before acting. Ask about anything unclear, contradictory or
 underspecified — before starting and mid-build. Ask in the question widget
 (AskUserQuestion): related questions batched, concrete options, your
 recommendation first. Plain text only if the widget isn't available.>

<Don't expand scope. Anything not listed here is a proposal, including changes
 to this file — propose it, don't do it.>

<Prefer doing over describing: run the code, write the files, test it.>

<Always in scope, no proposal needed: a README with build and usage steps when
 it goes on GitHub, and a small unobtrusive feedback tab if what you're
 building is an application rather than a script.>

<If what you're building is an application, build it as a Mac app first; the
 website comes after, as its own step.>

<Finish by listing every deliverable: path, what it is, how to check it works.>

<Git rules (no Claude attribution, never commit .claude/) are in
 ~/.claude/CLAUDE.md and apply on their own — nothing to repeat here.>

<Keep the changelog at the bottom current.>

CONTEXT:

create a headshot/clean up existing picture and include an avatar vizualization

OPEN QUESTIONS / ASSUMPTIONS:

<Agent fills in: what it guessed, what it decided without asking.>

Asked and answered (2026-09-28):
- Engine: on-device cleanup only (Apple Vision + Core Image). No cloud or generative AI, no API keys, photos never leave the Mac.
- "Avatar visualization" = stylized avatars made from the cleaned headshot (Cartoon, Pop Art, Pencil Sketch, Duotone, Halftone, Pixel), shown side by side, exportable, with an optional circle crop.
- Scope for this pass: native Mac app only, local. Website and GitHub push are later, separate steps.

Decided without asking:
- SwiftUI app built as a Swift package (no .xcodeproj); scripts/build_app.sh wraps it into build/Headshot Generator.app, signed ad hoc. macOS 14+.
- Cleanup = auto-enhance, exposure/contrast/saturation/warmth, edge-preserving skin smoothing (person only), background (original / blur / solid / studio gradient) via Vision person segmentation, auto head-and-shoulders crop (1:1, 4:5 or uncropped) from the largest detected face. No face found = centre crop; no person mask = background left as is.
- Feedback tab: small "Feedback" tab at the window's bottom-right; saves locally to ~/Library/Application Support/HeadshotGenerator/feedback.jsonl (nothing sent anywhere).
- GitHub repo created private at first (visibility not specified), then made public so GitHub Pages could serve the site (user's choice, 2026-09-28).

Website (asked and answered, 2026-09-28): hosted on GitHub Pages from /web; MediaPipe runs in the browser for the face and person outline; plain HTML/JS with no build step.
Website, decided without asking:
- Pixel pipeline rewritten in plain JS (web/js/imageops.js, avatars.js) to match the Mac app's features and six avatar styles. The look is close, not pixel-identical.
- Models: blaze_face_short_range + selfie_segmenter (small). The WASM runtime is about 11.7 MB, downloaded once from jsDelivr.
- Feedback tab on the web opens a GitHub issue (the Mac app saves feedback locally).
- Deployed by a GitHub Actions workflow (Pages can't serve /web straight from a branch); the workflow runs the web tests first.
- App icon (added on request, 2026-09-28): white head-and-shoulders on an indigo tile, with viewfinder corners (the crop) and a gold sparkle (the cleanup). The SVG is the source; the .icns is committed so builds don't need rsvg-convert. Superseded the same day by an Icon Composer version (below); the SVG/.icns remain as the fallback and website source.
- Icon Composer icon (added on request, 2026-09-28): Resources/AppIcon.icon, with three layers (person, viewfinder corners, sparkles) over a gradient fill; the person and corners are slightly translucent glass. build_app.sh compiles it with actool (Xcode 26+) into Assets.car plus an .icns fallback for older macOS, and uses the committed .icns if actool can't. The icon.json was written by hand, as there were no sample files on this Mac; actool compiles it with no warnings, but it hasn't been opened in Icon Composer yet.
- Tests don't ship a face image. The real-portrait test runs only when HEADSHOT_TEST_IMAGE is set.

CHANGELOG:

- 2026-09-28 — created
- 2026-09-15 — added meta-instruction: built-out applications include a small feedback tab
- 2026-09-15 — added meta-instruction: no "Claude" attribution in commits, PRs, or branches
- 2026-09-16 — added meta-instruction: always include a README when adding to GitHub
- 2026-09-16 — changed meta-instruction: ask clarifying questions in the question widget
- 2026-09-17 — added meta-instructions: Claude never a contributor; never commit .claude/
- 2026-09-26 — compressed the meta-instructions and every field prompt; git rules moved to the global instruction file
- 2026-09-27 — added meta-instruction: applications are built as a Mac app first, then a website
- 2026-09-28 — folded inputs, instructions, constraints, deliverables and done criteria into one free-form CONTEXT
- 2026-09-28 — built v0.1 Mac app: on-device headshot cleanup + stylized avatars, feedback tab, tests, build script
- 2026-09-28 — added README and .gitignore; pushed to GitHub (private repo)
- 2026-09-28 — built website version (web/), deployed to GitHub Pages; repo made public
- 2026-09-28 — added Mac app icon (Resources/AppIcon.svg → AppIcon.icns)
- 2026-09-28 — website uses the app icon (favicon + iOS home-screen icon, generated from the same SVG)
- 2026-09-28 — Mac app opens photos dropped on its Dock icon or chosen with Finder's Open With (it never becomes the default image app)
- 2026-09-28 — fixed: a photo with no person was turned almost entirely into background, because the person mask always exists; now a mask covering under 5% of the photo counts as no person (Mac app and website)
- 2026-09-28 — Icon Composer app icon (Resources/AppIcon.icon), compiled by build_app.sh; native glass rendering on macOS 26
