#!/usr/bin/env bash
# Builds an AppImage from Flutter's Linux release bundle.
#   packaging/linux/build-appimage.sh <version> <bundle-dir> <out-dir>
# Needs `appimagetool` on PATH (CI downloads it). The AppImage uses the system's GTK 3.
set -euo pipefail

version=${1:?usage: build-appimage.sh <version> <bundle-dir> <out-dir>}
bundle=${2:?missing bundle dir}
out=${3:?missing output dir}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
icon="$repo/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

[ -x "$bundle/OpenRest" ] || { echo "error: $bundle/OpenRest not found or not executable" >&2; exit 1; }
[ -f "$icon" ] || { echo "error: icon not found: $icon" >&2; exit 1; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
appdir="$root/OpenRest.AppDir"

# Flutter finds lib/ and data/ next to the executable, so the bundle stays in one piece.
mkdir -p "$appdir/usr/share/openrest"
cp -a "$bundle/." "$appdir/usr/share/openrest/"
install -m 0644 "$here/openrest.desktop" "$appdir/openrest.desktop"
install -m 0644 "$icon" "$appdir/openrest.png"
ln -s openrest.png "$appdir/.DirIcon"
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
exec "$here/usr/share/openrest/OpenRest" "$@"
APPRUN
chmod +x "$appdir/AppRun"

mkdir -p "$out"
ARCH=x86_64 appimagetool "$appdir" "$out/OpenRest-${version}-linux-x86_64.AppImage"
echo "created $out/OpenRest-${version}-linux-x86_64.AppImage"
