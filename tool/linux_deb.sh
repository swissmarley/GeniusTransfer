#!/usr/bin/env bash
# Run on Debian 12 with Flutter, GTK 3 build dependencies and dpkg-dev.
# Build each package on its matching architecture (amd64 or arm64).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/app"
arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) flutter_arch=x64 ;;
  arm64) flutter_arch=arm64 ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
flutter build linux --release --target-platform "linux-$flutter_arch"
bundle="$PWD/build/linux/$flutter_arch/release/bundle"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/DEBIAN" "$stage/usr/lib/geniustransfer" \
  "$stage/usr/bin" "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$stage/usr/lib/geniustransfer/"
cat > "$stage/usr/bin/geniustransfer" <<'LAUNCHER'
#!/bin/sh
exec /usr/lib/geniustransfer/geniustransfer "$@"
LAUNCHER
chmod 755 "$stage/usr/bin/geniustransfer"
install -m 644 "$root/tool/geniustransfer.desktop" "$stage/usr/share/applications/"
install -m 644 "$root/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png" \
  "$stage/usr/share/icons/hicolor/256x256/apps/com.nakya.geniustransfer.png"
desktop-file-validate "$stage/usr/share/applications/geniustransfer.desktop"

# Derive library requirements from the actual binaries on Debian 12.
mkdir -p "$stage/debian"
cat > "$stage/debian/control" <<'CONTROL'
Source: geniustransfer
Section: net
Priority: optional
Maintainer: GeniusTransfer <noreply@github.com>

Package: geniustransfer
Architecture: any
Description: Offline local-network file transfer
CONTROL
mapfile -d '' binaries < <(find "$stage/usr/lib/geniustransfer" -type f \
  \( -name '*.so' -o -name geniustransfer \) -print0)
deps="$(cd "$stage" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"$stage/usr/lib/geniustransfer/lib" "${binaries[@]}" | sed -n 's/^shlibs:Depends=//p')"
test -n "$deps"
rm -r "$stage/debian"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: geniustransfer
Version: $version
Section: net
Priority: optional
Architecture: $arch
Maintainer: GeniusTransfer <noreply@github.com>
Depends: $deps, libgl1, libegl1, libgles2, xdg-utils, xdg-user-dirs, xdg-desktop-portal, xdg-desktop-portal-gtk | xdg-desktop-portal-backend
Installed-Size: $(du -sk "$stage/usr" | cut -f1)
Homepage: https://github.com/swissmarley/GeniusTransfer
Description: Offline local-network file transfer
 Share files with nearby phones and computers through their web browser.
 Only one device needs the app. No cloud service is required.
CONTROL
mkdir -p "$PWD/build/releases"
output="$PWD/build/releases/GeniusTransfer-$version-linux-$arch.deb"
dpkg-deb --root-owner-group --build "$stage" "$output"
dpkg-deb --info "$output"
sha256sum "$output"
