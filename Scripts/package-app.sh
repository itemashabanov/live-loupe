#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Live Loupe"
DISPLAY_NAME="Live Loupe"
BUNDLE_ID="com.local.liveloupe"
EXECUTABLE_NAME="LiveLoupe"
PLUGIN_NAME="Live Loupe.lrplugin"
CONFIGURATION="${1:-release}"
APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/.build/$APP_NAME.zip"
KIT_DIR="$ROOT_DIR/.build/$APP_NAME Kit"
KIT_ZIP_PATH="$ROOT_DIR/.build/$APP_NAME Kit.zip"
ICONSET_PATH="$ROOT_DIR/.build/AppIcon.iconset"
ICON_PATH="$ROOT_DIR/.build/AppIcon.icns"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"

cd "$ROOT_DIR"
export COPYFILE_DISABLE=1

swift build -c "$CONFIGURATION"
swift "$ROOT_DIR/Scripts/generate-icon.swift" "$ICONSET_PATH"
iconutil -c icns "$ICONSET_PATH" -o "$ICON_PATH"
BINARY_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH"
cp "$BINARY_PATH" "$MACOS_PATH/$EXECUTABLE_NAME"
chmod +x "$MACOS_PATH/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$RESOURCES_PATH/AppIcon.icns"

cat > "$CONTENTS_PATH/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.photography</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Live Loupe serves Lightroom preview images to your iPhone over your local Wi-Fi network.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_PATH" >/dev/null
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_PATH" "$ZIP_PATH"

rm -rf "$KIT_DIR" "$KIT_ZIP_PATH"
mkdir -p "$KIT_DIR"
ditto "$APP_PATH" "$KIT_DIR/$APP_NAME.app"
ditto "$ROOT_DIR/LightroomPlugin/$PLUGIN_NAME" "$KIT_DIR/$PLUGIN_NAME"
cp "$ROOT_DIR/README.md" "$KIT_DIR/README.md"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$KIT_DIR" "$KIT_ZIP_PATH"

echo "$APP_PATH"
echo "$ZIP_PATH"
echo "$KIT_ZIP_PATH"
