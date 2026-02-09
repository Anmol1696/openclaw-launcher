#!/bin/bash
# ============================================================================
#  Build OpenClaw Launcher into a macOS .app bundle + .dmg
#  Requirements: Xcode command line tools (xcode-select --install)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenClawLauncher"
BUILD_DIR="$SCRIPT_DIR/.build"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"

# Derive version from git tag (e.g. v1.2.3 → 1.2.3), fallback to 1.0.0
APP_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")

echo "🐙 Building ${APP_NAME}.app (${APP_VERSION}) ..."

# ──────────────────────────────────────────────
# 1. Compile Swift (Universal Binary)
# ──────────────────────────────────────────────
echo "   Compiling Swift (universal binary)..."
cd "$SCRIPT_DIR"

# Build for arm64
echo "      Building for arm64..."
swift build -c release --arch arm64 2>&1
ARM64_BIN="$BUILD_DIR/arm64-apple-macosx/release/OpenClawLauncher"

# Build for x86_64
echo "      Building for x86_64..."
swift build -c release --arch x86_64 2>&1
X86_64_BIN="$BUILD_DIR/x86_64-apple-macosx/release/OpenClawLauncher"

# Check both binaries exist
if [ ! -f "$ARM64_BIN" ]; then
    echo "❌ Build failed — arm64 binary not found"
    exit 1
fi

if [ ! -f "$X86_64_BIN" ]; then
    echo "❌ Build failed — x86_64 binary not found"
    exit 1
fi

# Create universal binary with lipo
UNIVERSAL_DIR="$BUILD_DIR/universal"
mkdir -p "$UNIVERSAL_DIR"
BINARY="$UNIVERSAL_DIR/OpenClawLauncher"

echo "      Creating universal binary with lipo..."
lipo -create -output "$BINARY" "$ARM64_BIN" "$X86_64_BIN"

if [ ! -f "$BINARY" ]; then
    echo "❌ Failed to create universal binary"
    exit 1
fi

echo "   ✅ Compiled (universal: arm64 + x86_64)"

# ──────────────────────────────────────────────
# 2. Create .app bundle
# ──────────────────────────────────────────────
echo "   Creating .app bundle..."

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/${APP_NAME}"

# Generate app icon from emoji
echo "   Generating app icon..."
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift "$SCRIPT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"
echo "   ✅ App icon generated"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OpenClawLauncher</string>
    <key>CFBundleDisplayName</key>
    <string>OpenClawLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>ai.openclaw.launcher</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>OpenClawLauncher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "   ✅ .app bundle created"

# ──────────────────────────────────────────────
# 3. Code signing
# ──────────────────────────────────────────────
# DEVELOPER_ID: Set to sign with Developer ID (e.g., "Developer ID Application: Name (TEAMID)")
# Without DEVELOPER_ID: ad-hoc signing (local dev only, triggers Gatekeeper warnings)
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "   Code signing with Developer ID..."
    codesign --force --sign "$DEVELOPER_ID" \
        --options runtime \
        --timestamp \
        --entitlements "$SCRIPT_DIR/OpenClawLauncher.entitlements" \
        "$APP_DIR"
    echo "   ✅ Signed with Developer ID"
else
    echo "   Code signing (ad-hoc)..."
    codesign --force --deep --sign - "$APP_DIR"
    echo "   ✅ Signed (ad-hoc — will trigger Gatekeeper warning)"
fi

# ──────────────────────────────────────────────
# 4. Create .dmg
# ──────────────────────────────────────────────
if command -v hdiutil &>/dev/null; then
    echo "   Creating DMG..."
    DMG_PATH="$DIST_DIR/OpenClawLauncher.dmg"
    rm -f "$DMG_PATH"

    DMG_STAGING="$DIST_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -r "$APP_DIR" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "OpenClawLauncher" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDBZ \
        "$DMG_PATH"

    rm -rf "$DMG_STAGING"
    [ -f "$DMG_PATH" ] && echo "   ✅ DMG created"
fi

echo ""
echo "  Done! App: $APP_DIR"
[ -f "$DIST_DIR/OpenClawLauncher.dmg" ] && echo "  DMG: $DIST_DIR/OpenClawLauncher.dmg"
echo ""
echo "  Install: cp -r '$APP_DIR' /Applications/"

