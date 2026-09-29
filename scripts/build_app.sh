#!/bin/zsh
# Builds a release HeadshotGenerator.app into ./build.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HeadshotGenerator"
APP="build/Headshot Generator.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HeadshotGenerator"
# Icon: compile the Icon Composer file (glass, dark and tinted looks on macOS 26) when this Xcode can;
# otherwise use the pre-built AppIcon.icns. actool also writes an .icns fallback for older macOS.
# (Absolute paths: actool resolves relative ones against a different directory.)
if xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" --platform macosx \
     --minimum-deployment-target 14.0 --app-icon AppIcon --target-device mac \
     --output-partial-info-plist "$(mktemp)" >/dev/null 2>&1 \
   && [[ -f "$APP/Contents/Resources/Assets.car" ]]; then
  echo "Icon: compiled Resources/AppIcon.icon"
else
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  echo "Icon: actool unavailable, using Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Headshot Generator</string>
    <key>CFBundleDisplayName</key><string>Headshot Generator</string>
    <key>CFBundleIdentifier</key><string>com.amalmehta.headshotgenerator</string>
    <key>CFBundleExecutable</key><string>HeadshotGenerator</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Accept images dropped on the Dock icon and list the app under Finder's Open With.
         Alternate rank: never takes over as the default app for images. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.image</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
