#!/usr/bin/env bash
# Builds a .deb from Flutter's Linux release bundle.
#   packaging/linux/build-deb.sh <version> <bundle-dir> <out-dir>
# Installs to /opt/openrest, with /usr/bin/openrest, a menu entry and an icon.
set -euo pipefail

version=${1:?usage: build-deb.sh <version> <bundle-dir> <out-dir>}
bundle=${2:?missing bundle dir}
out=${3:?missing output dir}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
icon="$repo/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

[ -x "$bundle/OpenRest" ] || { echo "error: $bundle/OpenRest not found or not executable" >&2; exit 1; }
[ -f "$icon" ] || { echo "error: icon not found: $icon" >&2; exit 1; }

# A pre-release tag like 2.1.0-beta.1 becomes 2.1.0~beta.1, which sorts before 2.1.0.
deb_version=${version/-/\~}
arch=amd64
pkg="openrest_${version}_${arch}"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
stage="$root/$pkg"

mkdir -p "$stage/DEBIAN" "$stage/opt/openrest" "$stage/usr/bin" \
  "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$stage/opt/openrest/"
ln -s /opt/openrest/OpenRest "$stage/usr/bin/openrest"
install -m 0644 "$here/openrest.desktop" "$stage/usr/share/applications/openrest.desktop"
install -m 0644 "$icon" "$stage/usr/share/icons/hicolor/512x512/apps/openrest.png"

size=$(du -sk "$stage" | cut -f1)
cat > "$stage/DEBIAN/control" <<CONTROL
Package: openrest
Version: $deb_version
Section: devel
Priority: optional
Architecture: $arch
Installed-Size: $size
Maintainer: Prateek Thakur <noreply@users.noreply.github.com>
Depends: libgtk-3-0, libglib2.0-0
Recommends: zenity | kdialog
Homepage: https://github.com/prateekthakur272/open_rest
Description: An open, file-based API client
 OpenRest keeps requests, environments and workflows in plain folders you
 own. It supports HTTP, GraphQL and WebSocket requests, workflows, a
 collection runner, scripting and tests, and imports from Postman, Insomnia,
 Bruno and OpenAPI.
CONTROL

mkdir -p "$out"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$out/OpenRest-${version}-linux-amd64.deb"
echo "created $out/OpenRest-${version}-linux-amd64.deb"
