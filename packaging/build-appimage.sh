#!/usr/bin/env bash
# Build HyprNotes.AppImage.
#
# What this bundles vs. what it leans on the host for:
#   bundled : python3 interpreter + stdlib, PyGObject ("gi"), and the
#             GTK4 / libadwaita / Pango / cairo / GLib shared libraries
#             (found via `ldd`, copied by soname) plus their .typelib
#             files, so the exact library versions this was built
#             against travel with the app.
#   host    : the kernel/libc/X11-or-Wayland/D-Bus session, fontconfig
#             + fonts, and the Adwaita icon theme (already required by
#             libadwaita itself, so any machine that can display a
#             libadwaita app already has it). Not vendored: it's
#             per-theme data, not a library version.
#
# This is the same tradeoff every non-static AppImage makes: portable
# across distros close to the build machine's glibc, not a fully
# hermetic bundle like Flatpak. Rebuild on the oldest distro you want
# to support if that matters.
#
# Requires (build machine only): python-gobject, gtk4, libadwaita,
# rsvg-convert, and appimagetool (downloaded automatically if missing).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/dist}"
APPDIR="$WORK/HyprNotes.AppDir"
TOOLS="${TOOLS:-$WORK/.tools}"
ARCH="$(uname -m)"

log() { echo "==> $*"; }

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$TOOLS"

# --- 1. locate the python interpreter we're bundling ------------------
PYBIN="$(readlink -f "$(command -v python3)")"
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
STDLIB="/usr/lib/python$PYVER"
GI_SITE="$STDLIB/site-packages/gi"
log "python $PYVER at $PYBIN"
[ -d "$GI_SITE" ] || { echo "PyGObject (gi) not found at $GI_SITE — install python-gobject"; exit 1; }

# --- 2. copy the python interpreter + stdlib (minus dev cruft we don't need) ---
log "copying python stdlib"
cp "$PYBIN" "$APPDIR/usr/bin/python3"
mkdir -p "$APPDIR/usr/lib/python$PYVER"
cp -a "$STDLIB"/. "$APPDIR/usr/lib/python$PYVER/"
rm -rf "$APPDIR/usr/lib/python$PYVER"/{site-packages,test,idlelib,tkinter,turtledemo,ensurepip}

# only the gi bindings from site-packages, not the whole (huge, unrelated) tree
mkdir -p "$APPDIR/usr/lib/python$PYVER/site-packages"
cp -a "$GI_SITE" "$APPDIR/usr/lib/python$PYVER/site-packages/"
find "$APPDIR/usr/lib/python$PYVER" -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# --- 3. resolve and copy the native library closure via ldd -----------
LDCONFIG_CACHE="$WORK/.ldconfig-p"
ldconfig -p > "$LDCONFIG_CACHE"
find_lib() {
    # first cached-ldconfig match for a library name pattern. Grepping a
    # regular file (not piping from the live `ldconfig` process) avoids
    # a SIGPIPE (exit 141) when the match is found before EOF, which
    # `set -o pipefail` would otherwise turn into a script abort.
    grep -m1 -E "$1" "$LDCONFIG_CACHE" | awk '{print $NF}'
}

ENTRY_POINTS=(
    "$APPDIR/usr/bin/python3"
    "$APPDIR/usr/lib/python$PYVER/site-packages/gi/_gi.cpython-${PYVER/./}-${ARCH}-linux-gnu.so"
    "$APPDIR/usr/lib/python$PYVER/site-packages/gi/_gi_cairo.cpython-${PYVER/./}-${ARCH}-linux-gnu.so"
    "$(find_lib 'libgtk-4\.so')"
    "$(find_lib 'libadwaita-1\.so')"
    "$(find_lib 'libgirepository-2\.0\.so')"
    "$(find_lib 'libpangocairo-1\.0\.so')"
    "$(find_lib 'libpango-1\.0\.so')"
    "$(find_lib 'libpangoft2-1\.0\.so')"
    "$(find_lib 'libgdk_pixbuf-2\.0\.so')"
    "$(find_lib 'libcairo-gobject\.so')"
    "$(find_lib 'libharfbuzz\.so')"
    "$(find_lib 'libgraphene-1\.0\.so')"
)

log "resolving shared-library closure"
LIBSET="$WORK/.libset"
: > "$LIBSET"
for f in "${ENTRY_POINTS[@]}"; do
    [ -e "$f" ] || { echo "missing entry point: $f" >&2; exit 1; }
    ldd "$f" 2>/dev/null | awk '$3 ~ /^\// {print $3}' >> "$LIBSET"
done
sort -u "$LIBSET" -o "$LIBSET"

log "copying $(wc -l < "$LIBSET") shared libraries"
while read -r lib; do
    cp -n "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done < "$LIBSET"
# the entry-point libs themselves (ldd only lists their *dependencies*)
for f in "${ENTRY_POINTS[@]:3}"; do
    cp -n "$f" "$APPDIR/usr/lib/" 2>/dev/null || true
done
rm -f "$LIBSET"

# --- 4. typelibs (GObject-Introspection metadata the above libs need) --
log "copying typelibs"
cp -r /usr/lib/girepository-1.0 "$APPDIR/usr/lib/"

# --- 5. app source ------------------------------------------------------
log "copying app source"
mkdir -p "$APPDIR/usr/share/hyprnotes"
cp "$ROOT/HyprNotes.py" "$APPDIR/usr/share/hyprnotes/"
cp -r "$ROOT/hyprnotes" "$APPDIR/usr/share/hyprnotes/"
find "$APPDIR/usr/share/hyprnotes" -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# --- 6. icon + desktop entry --------------------------------------------
log "rendering icon"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$APPDIR/usr/share/icons/hicolor/scalable/apps"
rsvg-convert -w 256 -h 256 "$ROOT/packaging/icon.svg" -o "$APPDIR/hyprnotes.png"
cp "$APPDIR/hyprnotes.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/hyprnotes.png"
cp "$ROOT/packaging/icon.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/hyprnotes.svg"
cp "$ROOT/packaging/hyprnotes.desktop" "$APPDIR/hyprnotes.desktop"
mkdir -p "$APPDIR/usr/share/applications"
cp "$ROOT/packaging/hyprnotes.desktop" "$APPDIR/usr/share/applications/"

# --- 7. AppRun: the actual entry point AppImage execs -------------------
log "writing AppRun"
cat > "$APPDIR/AppRun" <<EOF
#!/bin/bash
# Resolve symlinks so this also works when the AppImage is invoked
# through a symlinked/renamed copy.
HERE="\$(cd "\$(dirname "\$(readlink -f "\${0}")")" && pwd)"

# Point the dynamic linker and GObject-Introspection at the libraries
# and typelibs we bundled, ahead of anything already on the host's path.
export LD_LIBRARY_PATH="\$HERE/usr/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export GI_TYPELIB_PATH="\$HERE/usr/lib/girepository-1.0\${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"

# Make python use our bundled stdlib instead of searching the host's.
export PYTHONHOME="\$HERE/usr"
export PYTHONPATH="\$HERE/usr/lib/python$PYVER/site-packages"
export PYTHONDONTWRITEBYTECODE=1

# Icons/fonts/cursors/portals are intentionally left to the host desktop.
exec "\$HERE/usr/bin/python3" "\$HERE/usr/share/hyprnotes/HyprNotes.py" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

# --- 8. appimagetool ------------------------------------------------------
APPIMAGETOOL="$TOOLS/appimagetool-$ARCH.AppImage"
if [ ! -x "$APPIMAGETOOL" ]; then
    log "downloading appimagetool"
    curl -fL -o "$APPIMAGETOOL" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

log "building AppImage"
OUT="$WORK/HyprNotes-$ARCH.AppImage"
rm -f "$OUT"
ARCH="$ARCH" "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$OUT"

log "done: $OUT"
du -h "$OUT"
