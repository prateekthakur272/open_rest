#!/usr/bin/env bash
# Packages the built macOS app into a drag-to-Applications DMG.
#   packaging/macos/build-dmg.sh <version> <app-path> <out-dir>
# Example (after "flutter build macos --release"):
#   packaging/macos/build-dmg.sh 2.1.0 build/macos/Build/Products/Release/OpenRest.app dist
# Output: <out-dir>/OpenRest-<version>-macos-universal.dmg
set -euo pipefail

version=${1:?usage: build-dmg.sh <version> <app-path> <out-dir>}
app=${2:?missing path to OpenRest.app}
out=${3:?missing output dir}

name=$(basename "$app" .app)
[ -d "$app" ] || { echo "error: $app not found (run the macOS release build first)" >&2; exit 1; }

# The app must be signed (ad-hoc is enough) or Apple Silicon refuses to launch it.
codesign --verify --deep --strict "$app"

# Flutter's release build contains both architectures; fail if one is missing, since the DMG is called "universal".
archs=$(lipo -archs "$app/Contents/MacOS/$name")
echo "architectures: $archs"
case "$archs" in
  *arm64*x86_64* | *x86_64*arm64*) ;;
  *) echo "error: expected a universal binary (arm64 + x86_64), got: $archs" >&2; exit 1 ;;
esac

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

mkdir -p "$out"
dmg="$out/${name}-${version}-macos-universal.dmg"
rm -f "$dmg"
hdiutil create -volname "$name" -srcfolder "$stage" -ov -format UDZO "$dmg"
echo "created $dmg"
