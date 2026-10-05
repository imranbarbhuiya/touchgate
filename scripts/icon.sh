#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/TouchGate.iconset
swift scripts/make-icon.swift assets/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/icon.png --out ".build/TouchGate.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" assets/icon.png --out ".build/TouchGate.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/TouchGate.iconset -o assets/TouchGate.icns
