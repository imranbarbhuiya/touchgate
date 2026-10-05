#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
mkdir -p dist/TouchGate.app/Contents/MacOS dist/TouchGate.app/Contents/Resources
cp .build/release/TouchGate dist/TouchGate.app/Contents/MacOS/TouchGate
cp assets/TouchGate.icns dist/TouchGate.app/Contents/Resources/TouchGate.icns
cp assets/Info.plist dist/TouchGate.app/Contents/Info.plist
codesign --force --sign - dist/TouchGate.app
echo 'Built dist/TouchGate.app. Open it with: open dist/TouchGate.app'
