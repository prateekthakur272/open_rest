#!/usr/bin/env bash
# Builds an .rpm (Fedora, RHEL and derivatives, openSUSE) from Flutter's Linux release bundle.
#   packaging/linux/build-rpm.sh <version> <bundle-dir> <out-dir>
# Needs `fpm` and `rpmbuild` on PATH (CI installs them). Same layout as the .deb: /opt/openrest,
# /usr/bin/openrest, a menu entry and an icon.
set -euo pipefail

version=${1:?usage: build-rpm.sh <version> <bundle-dir> <out-dir>}
bundle=${2:?missing bundle dir}
out=${3:?missing output dir}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
icon="$repo/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

[ -x "$bundle/OpenRest" ] || { echo "error: $bundle/OpenRest not found or not executable" >&2; exit 1; }
[ -f "$icon" ] || { echo "error: icon not found: $icon" >&2; exit 1; }

# RPM versions cannot contain '-': a pre-release tag like 2.1.0-beta.1 becomes 2.1.0~beta.1 (sorts before 2.1.0).
rpm_version=${version/-/\~}

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
stage="$root/stage"
mkdir -p "$stage/opt/openrest" "$stage/usr/bin" \
  "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$stage/opt/openrest/"
ln -s /opt/openrest/OpenRest "$stage/usr/bin/openrest"
install -m 0644 "$here/openrest.desktop" "$stage/usr/share/applications/openrest.desktop"
install -m 0644 "$icon" "$stage/usr/share/icons/hicolor/512x512/apps/openrest.png"

mkdir -p "$out"
fpm -s dir -t rpm \
  --name openrest \
  --version "$rpm_version" \
  --iteration 1 \
  --architecture x86_64 \
  --maintainer "Prateek Thakur <noreply@users.noreply.github.com>" \
  --url "https://github.com/prateekthakur272/open_rest" \
  --license "Unspecified" \
  --description "An open, file-based API client. Requests, environments and workflows live in plain folders you own; supports HTTP, GraphQL and WebSocket." \
  --depends gtk3 \
  --rpm-compression xz \
  --package "$out/OpenRest-${version}-linux-x86_64.rpm" \
  -C "$stage" .
echo "created $out/OpenRest-${version}-linux-x86_64.rpm"
