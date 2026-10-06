#!/bin/bash
# Builds BrowserSwitcher.app from main.swift using only the system Swift toolchain.
set -euo pipefail
cd "$(dirname "$0")"

APP="BrowserSwitcher.app"
BIN="BrowserSwitcher"
BUNDLE_ID="local.browserswitcher"

echo "→ Cleaning previous build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "→ Installing app icon"
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  (AppIcon.icns not found — skipping)"
fi

echo "→ Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>BrowserSwitcher</string>
    <key>CFBundleDisplayName</key>     <string>Browser Switcher</string>
    <key>CFBundleExecutable</key>      <string>$BIN</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Local build</string>
</dict>
</plist>
PLIST

echo "→ Compiling (Release)"
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | head -1)"
swiftc -O ${SDK:+-sdk "$SDK"} -framework AppKit -o "$APP/Contents/MacOS/$BIN" main.swift

echo "→ Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built $APP"
echo
echo "Run it:   open \"$APP\""
echo "Install:  cp -R \"$APP\" /Applications/   then add to Login Items"
