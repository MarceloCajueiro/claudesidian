#!/bin/bash
# Build and install Claudesidian.app
# Usage: bash build.sh
# On first launch, configure your command and working directory in the setup wizard.
set -e

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/Claudesidian.app"

echo "Building Claudesidian..."
cd "$PROJ_DIR"
swift build -c release 2>&1

echo "Installing to $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources}

cp "$PROJ_DIR/.build/release/Claudesidian" "$APP_DIR/Contents/MacOS/Claudesidian"
cp "$PROJ_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy icon if it exists
if [ -f "$PROJ_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJ_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Register with LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null
touch "$APP_DIR"

echo ""
echo "Done! Claudesidian.app installed at $APP_DIR"
echo "Run: open ~/Applications/Claudesidian.app"
