#!/bin/zsh
# Builds Iris.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

app=build/Iris.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Iris "$app/Contents/MacOS/Iris"
cp Resources/Info.plist "$app/Contents/Info.plist"

iconset=build/AppIcon.iconset
swift Resources/MakeIcon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

codesign --force --sign - "$app"

mkdir -p ~/Applications
pkill -x Iris 2>/dev/null || true
rm -rf ~/Applications/Iris.app
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Iris.app"
