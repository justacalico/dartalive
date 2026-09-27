#!/bin/bash
set -euo pipefail
# Package a flutter linux bundle into tar.gz, zip, .deb, .rpm and AppImage.
# Usage: package-linux.sh <bundle-dir> <outdir> <name> <version>
BUNDLE="$1"; OUT="$2"; NAME="$3"; VER="${4:-0.0.0}"
mkdir -p "$OUT"

tar -czf "$OUT/$NAME-linux-x86_64.tar.gz" -C "$BUNDLE" .
(cd "$BUNDLE" && zip -qr "$OUT/$NAME-linux-x86_64.zip" .)

# .deb
DEB="$OUT/debwork/$NAME"
mkdir -p "$DEB/DEBIAN" "$DEB/usr/lib/$NAME" "$DEB/usr/bin" "$DEB/usr/share/applications"
cp -r "$BUNDLE/." "$DEB/usr/lib/$NAME/"
cat > "$DEB/DEBIAN/control" <<EOC
Package: $NAME
Version: ${VER#v}
Architecture: amd64
Maintainer: dartalive
Description: DartAlive video editor
EOC
ln -sf "/usr/lib/$NAME/$NAME" "$DEB/usr/bin/$NAME"
cat > "$DEB/usr/share/applications/$NAME.desktop" <<EOC
[Desktop Entry]
Name=DartAlive
Exec=$NAME
Type=Application
Categories=AudioVideo;Video;
Icon=$NAME
EOC
[ -f "$BUNDLE/dartalive.png" ] && { mkdir -p "$DEB/usr/share/icons/hicolor/512x512/apps"; cp "$BUNDLE/dartalive.png" "$DEB/usr/share/icons/hicolor/512x512/apps/$NAME.png"; }
dpkg-deb --build "$DEB" "$OUT/$NAME-${VER#v}-amd64.deb"

# .rpm
if command -v rpmbuild >/dev/null; then
  TOP="$OUT/rpmwork"
  mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  cat > "$TOP/SPECS/$NAME.spec" <<EOC
Name: $NAME
Version: ${VER#v}
Release: 1
Summary: DartAlive video editor
License: AGPL-3.0
%description
DartAlive video editor
%prep
%build
%install
mkdir -p %{buildroot}/usr/lib/%{name} %{buildroot}/usr/bin
cp -r $BUNDLE/. %{buildroot}/usr/lib/%{name}/
ln -sf /usr/lib/%{name}/%{name} %{buildroot}/usr/bin/%{name}
%files
/usr/lib/%{name}
/usr/bin/%{name}
EOC
  rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/$NAME.spec" || true
  find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT/$NAME-${VER#v}-x86_64.rpm" \;
fi

# AppImage
if [ ! -f /tmp/appimagetool ]; then
  curl -fsSL -o /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" || true
  chmod +x /tmp/appimagetool
fi
if [ -x /tmp/appimagetool ]; then
  AI="$OUT/appimage/$NAME.AppDir"
  mkdir -p "$AI/usr/bin" "$AI/usr/share/applications"
  cp -r "$BUNDLE/." "$AI/usr/bin/"
  cat > "$AI/$NAME.desktop" <<EOC
[Desktop Entry]
Name=DartAlive
Exec=$NAME
Type=Application
Categories=AudioVideo;Video;
Icon=$NAME
EOC
  cat > "$AI/AppRun" <<EOC
#!/bin/sh
exec "\$(dirname "\$0")/usr/bin/$NAME" "\$@"
EOC
  chmod +x "$AI/AppRun"
  [ -f "$BUNDLE/dartalive.png" ] && cp "$BUNDLE/dartalive.png" "$AI/$NAME.png" || true

  ARCH=x86_64 /tmp/appimagetool "$AI" "$OUT/$NAME-${VER#v}-x86_64.AppImage" || echo "appimagetool failed"
fi
