#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
set -eu

version=$1
binary=$2
plugindir=$3
language=$4
base_package=vlc-plugin-clickpause
case "$language" in
    en) package=$base_package ;;
    fr) package=$base_package-fr ;;
    *) echo "Unsupported package language: $language" >&2; exit 1 ;;
esac
maintainer=${DEB_MAINTAINER:-VLC click-pause contributors <noreply@example.invalid>}

for command in dpkg-deb dpkg-architecture dpkg-shlibdeps nm; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing $command. Install dpkg-dev and binutils to build a .deb." >&2
        exit 1
    }
done
case "$plugindir" in
    /usr/*/vlc/plugins) ;;
    *) echo "A .deb requires the system VLC plugin directory under /usr." >&2; exit 1 ;;
esac

# Debian's VLC packages provide the ABI named by the plugin's entry point.
# This also distinguishes time64 builds from older VLC 3.x builds.
abi=$(nm -D --defined-only "$binary" | awk '
    $3 ~ /^vlc_entry__[0-9]/ {
        sub(/^vlc_entry__/, "vlc-plugin-abi-", $3);
        gsub(/_/, "-", $3);
        print $3;
    }')
test -n "$abi" || { echo "Cannot determine the VLC plugin ABI." >&2; exit 1; }

arch=$(dpkg-architecture -qDEB_HOST_ARCH)
mkdir -p dist
work=$(mktemp -d "${TMPDIR:-/tmp}/vlc-click-pause-deb.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
root=$work/debian/$package
doc=$root/usr/share/doc/$package
install -Dm755 "$binary" "$root$plugindir/video_filter/libclickpause_plugin.so"
install -Dm644 README.md "$doc/README.md"
install -Dm644 LICENSE "$doc/copyright"

# Resolve actual shared-library requirements instead of guessing libc versions.
mkdir -p "$work/debian" "$root/DEBIAN"
cat > "$work/debian/control" <<EOF
Source: $package
Section: video
Priority: optional
Maintainer: $maintainer

Package: $package
Architecture: any
Description: Pause or play VLC videos by clicking on the image
EOF
deps=$(cd "$work" && dpkg-shlibdeps -O \
    -e"$root$plugindir/video_filter/libclickpause_plugin.so")
deps=${deps#shlibs:Depends=}
cat > "$root/DEBIAN/control" <<EOF
Package: $package
Version: $version
Section: video
Priority: optional
Architecture: $arch
Maintainer: $maintainer
Depends: $abi, $deps
Recommends: vlc
Installed-Size: $(du -sk "$root/usr" | cut -f1)
Description: Pause or play VLC videos by clicking on the image
 A minimal VLC 3.x video filter with $language interface text. Enable or disable
 it in Preferences > All > Video > Filters, then save and restart VLC.
EOF

# Language variants install the same module and are mutually exclusive. The
# internal clickpause name is unchanged, preserving the user's VLC settings.
if [ "$package" != "$base_package" ]; then
    cat >> "$root/DEBIAN/control" <<EOF
Provides: $base_package
Conflicts: $base_package
Replaces: $base_package
EOF
fi

dpkg-deb --root-owner-group --build "$root" "dist/${package}_${version}_${arch}.deb"
