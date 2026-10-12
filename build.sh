#!/bin/zsh
# Builds ClaudeBar.app next to this script. Usage: [VERSION=1.2] ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ClaudeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Release builds take their version from the git tag.
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
fi

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos14.0" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    Sources/*.swift -o "build/ClaudeBar-$arch"
done
lipo -create build/ClaudeBar-arm64 build/ClaudeBar-x86_64 -output "$APP/Contents/MacOS/ClaudeBar"
rm build/ClaudeBar-arm64 build/ClaudeBar-x86_64

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClaudeBar 2>/dev/null || true
  rm -rf /Applications/ClaudeBar.app
  cp -R "$APP" /Applications/
  open /Applications/ClaudeBar.app
  echo "Installed to /Applications and launched"
fi
