#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -m)" in
  arm64) arch=arm64 ;;
  x86_64) arch=x64 ;;
  *) echo 'Unsupported Mac architecture' >&2; exit 1 ;;
esac
bash scripts/build.sh
archive="TouchGate-macos-${arch}.zip"
ditto -c -k --norsrc --noextattr --noqtn --keepParent dist/TouchGate.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
echo "Packaged dist/$archive"
