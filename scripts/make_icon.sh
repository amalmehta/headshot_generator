#!/bin/zsh
# Regenerates the Mac icon (Resources/AppIcon.icns) and the website icons (web/icon.svg,
# web/apple-touch-icon.png) from Resources/AppIcon.svg. Needs rsvg-convert (brew install librsvg).
# Only needed after editing the SVG; the outputs are committed so normal builds don't need it.
set -euo pipefail
cd "${0:A:h}/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "${ICONSET:h}"

# Website: crop the viewBox to the tile so it fills the browser tab.
sed 's|viewBox="0 0 1024 1024"|viewBox="100 100 824 824"|' Resources/AppIcon.svg > web/icon.svg
# iOS applies its own rounded mask and shows transparency as black, so the touch icon is square and full-bleed.
sed -e 's|viewBox="0 0 1024 1024"|viewBox="100 100 824 824"|' -e 's|rx="185"|rx="0"|g' Resources/AppIcon.svg \
  | rsvg-convert -w 180 -h 180 -o web/apple-touch-icon.png
echo "Wrote Resources/AppIcon.icns, web/icon.svg, web/apple-touch-icon.png"
