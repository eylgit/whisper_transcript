#!/bin/bash
# Builds Transcribe.app and the `transcribe` CLI from source.
# Requires only Xcode Command Line Tools; whisper.cpp must already be built.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
WBIN="$ROOT/vendor/whisper.cpp/build/bin"
APP="$ROOT/Transcribe.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
SWIFTC=/usr/bin/swiftc

[ -x "$WBIN/whisper-cli" ] || { echo "error: whisper.cpp not built; run setup.sh" >&2; exit 1; }
mkdir -p "$BUILD"

echo "==> compiling"
"$SWIFTC" -swift-version 5 -O "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/CLI/main.swift \
  -o "$BUILD/transcribe"
"$SWIFTC" -swift-version 5 -O "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift \
  -o "$BUILD/Transcribe-bin"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$RES"
cp "$BUILD/Transcribe-bin" "$CONTENTS/MacOS/Transcribe"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                  <string>Transcribe</string>
  <key>CFBundleDisplayName</key>           <string>Transcribe</string>
  <key>CFBundleIdentifier</key>            <string>local.whisper.transcribe</string>
  <key>CFBundleExecutable</key>            <string>Transcribe</string>
  <key>CFBundleIconFile</key>              <string>Transcribe</string>
  <key>CFBundlePackageType</key>           <string>APPL</string>
  <key>CFBundleShortVersionString</key>    <string>1.0</string>
  <key>CFBundleVersion</key>               <string>1</string>
  <key>LSMinimumSystemVersion</key>        <string>13.0</string>
  <key>NSHighResolutionCapable</key>       <true/>
  <key>LSApplicationCategoryType</key>     <string>public.app-category.productivity</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key> <string>Audio File</string>
      <key>CFBundleTypeRole</key> <string>Viewer</string>
      <key>LSHandlerRank</key>    <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.audio</string>
        <string>public.mp3</string>
        <string>public.mpeg-4-audio</string>
        <string>com.apple.m4a-audio</string>
        <string>com.microsoft.waveform-audio</string>
        <string>public.aiff-audio</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> icon"
rm -rf "$BUILD/Transcribe.iconset"
if /usr/bin/swift "$ROOT/scripts/make-icon.swift" "$BUILD" 2>/dev/null \
   && iconutil -c icns "$BUILD/Transcribe.iconset" -o "$RES/Transcribe.icns" 2>/dev/null; then
  echo "    icon generated"
else
  echo "    warning: icon generation failed; app will use the default icon" >&2
fi

echo "==> bundling whisper.cpp"
cp "$WBIN/whisper-cli" "$RES/"
# Copy the dylibs whisper-cli actually needs, following the @rpath references.
for lib in $(otool -L "$WBIN/whisper-cli" | awk '/@rpath/{print $1}' | sed 's|@rpath/||'); do
  # Copy the real file and recreate the symlink chain it is reached through.
  cp -a "$WBIN/$lib" "$RES/" 2>/dev/null || true
  real=$(cd "$WBIN" && readlink "$lib" || true)
  [ -n "$real" ] && cp -a "$WBIN/$real" "$RES/" 2>/dev/null || true
done

echo "==> repointing rpaths at the bundle"
old_rpath=$(otool -l "$RES/whisper-cli" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; exit}')
if [ -n "${old_rpath:-}" ]; then
  install_name_tool -delete_rpath "$old_rpath" "$RES/whisper-cli" 2>/dev/null || true
fi
install_name_tool -add_rpath "@executable_path" "$RES/whisper-cli"
for dylib in "$RES"/*.dylib; do
  [ -L "$dylib" ] && continue
  install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done

echo "==> model"
# APFS clone: instant and consumes no extra disk until one copy is modified.
for f in "$ROOT"/models/ggml-*.bin; do
  [ -e "$f" ] || continue
  cp -c "$f" "$RES/" 2>/dev/null || cp "$f" "$RES/"
done

echo "==> signing (ad-hoc; required on Apple Silicon after install_name_tool)"
for bin in "$RES"/*.dylib "$RES/whisper-cli" "$CONTENTS/MacOS/Transcribe"; do
  [ -f "$bin" ] && codesign --force --sign - "$bin" >/dev/null 2>&1 || true
done
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo
echo "built: $APP"
echo "       $BUILD/transcribe"
