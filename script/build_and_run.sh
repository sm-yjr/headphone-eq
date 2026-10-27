#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HeadphoneEQ"
BUNDLE_ID="com.sm-yjr.headphone-eq"
CONFIGURATION="${CONFIGURATION:-debug}"
cd "$ROOT_DIR"
VERSION="$(cat VERSION)"
BUILD_ARGS=(--build-system native --configuration "$CONFIGURATION")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}" --product "$APP_NAME"
BUILD_BINARY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
# Replace only our generated bundle; never terminate the user's running audio.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Headphone EQ</string>
<key>CFBundleDisplayName</key><string>Headphone EQ</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAudioCaptureUsageDescription</key><string>在本机均衡正在播放的系统音频。不保存或上传音频。Process system audio locally for equalization. Audio is never recorded to disk or uploaded.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Headphone EQ contributors. GPL-3.0-only.</string>
</dict></plist>
PLIST
SIGNING_IDENTITY="${HEADPHONE_EQ_SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
  --build-only) echo "$APP_BUNDLE" ;;
  run) /usr/bin/open "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|--telemetry) /usr/bin/open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  *) echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
