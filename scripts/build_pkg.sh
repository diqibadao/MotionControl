#!/bin/bash
set -e
echo "=== MotionControl PKG Builder v0.9.0 ==="

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
VERSION="0.9.0"
SIGN_APP="E8C6A3F3FD92B4EF51BD9DA41151883D1EBBFFB8"
SIGN_PKG="3rd Party Mac Developer Installer: wang bangdong (J5V4KAAAY3)"
OUTPUT_PKG="$BUILD_DIR/MotionControl-${VERSION}.pkg"
SOCKET="/tmp/com.motioncontrol.axhelper.sock"
HELPER_PATH="/Applications/MotionControl.app/Contents/MacOS/AXHelper"

cd "$PROJECT_DIR"

echo "[1/6] Building..."
swift build -c release 2>&1 | tail -1

echo "[2/6] Package structure..."
PKG_ROOT="/tmp/mc_pkg_$$"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS"
mkdir -p "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources"
mkdir -p "$PKG_ROOT/scripts"

echo "[3/6] Signing..."
cp .build/release/MotionControl "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/"
cp .build/release/AXHelper "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/"
chmod +x "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/MotionControl"
chmod +x "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/AXHelper"

# Sign AXHelper first (no sandbox)
codesign --force --sign "$SIGN_APP" \
  --entitlements "$BUILD_DIR/Entitlements-NoSandbox.plist" \
  --timestamp=none \
  "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/AXHelper" 2>&1

# Sign MotionControl (sandbox)
codesign --force --sign "$SIGN_APP" \
  --entitlements "$BUILD_DIR/Entitlements.plist" \
  --timestamp=none \
  "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/MotionControl" 2>&1

echo "[4/6] Resources..."
# Info.plist from Sources (with all required keys)
cp Sources/MotionControl/Info.plist "$PKG_ROOT/Applications/MotionControl.app/Contents/"

# AppIcon
if [ -f "$BUILD_DIR/MotionControl.app/Contents/Resources/AppIcon.icns" ]; then
    cp "$BUILD_DIR/MotionControl.app/Contents/Resources/AppIcon.icns" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ AppIcon.icns"
else
    echo "  ⚠️  AppIcon.icns not found"
fi

# Localizable.json
if [ -f "$BUILD_DIR/MotionControl.app/Contents/Resources/Localizable.json" ]; then
    cp "$BUILD_DIR/MotionControl.app/Contents/Resources/Localizable.json" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ Localizable.json"
elif [ -f Sources/MotionControl/Resources/Localizable.json ]; then
    cp Sources/MotionControl/Resources/Localizable.json "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ Localizable.json (from Sources)"
fi

# Resource bundle (SPM)
if [ -d ".build/release/MotionControl_MotionControl.bundle" ]; then
    cp -R ".build/release/MotionControl_MotionControl.bundle" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ MotionControl_MotionControl.bundle"
fi

# Sign the .app bundle (after all resources are copied)
codesign --force --sign "$SIGN_APP" --timestamp=none \
    "$PKG_ROOT/Applications/MotionControl.app" 2>&1
echo "  ✓ App bundle signed"

echo "[5/6] Postinstall..."
cat > "$PKG_ROOT/scripts/postinstall" << POSTINSTALL
#!/bin/bash
set -e
HELPER="$HELPER_PATH"
SOCKET="$SOCKET"
chmod +x "\$HELPER"

pkill -f AXHelper 2>/dev/null || true
rm -f "\$SOCKET"

CONSOLE_USER=\$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -n "\$CONSOLE_USER" ] && [ "\$CONSOLE_USER" != "root" ]; then
    USER_UID=\$(id -u "\$CONSOLE_USER" 2>/dev/null || echo "501")
    LAUNCHD_DIR="/Users/\$CONSOLE_USER/Library/LaunchAgents"
    PLIST="\$LAUNCHD_DIR/com.motioncontrol.axhelper.plist"
    mkdir -p "\$LAUNCHD_DIR"
    cat > "\$PLIST" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.motioncontrol.axhelper</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HELPER_PATH</string>
        <string>--socket</string>
        <string>$SOCKET</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST_EOF
    chown "\$CONSOLE_USER:staff" "\$PLIST" 2>/dev/null || true
    launchctl asuser "\$USER_UID" launchctl bootout "gui/\$USER_UID/com.motioncontrol.axhelper" 2>/dev/null || true
    launchctl asuser "\$USER_UID" launchctl bootstrap "gui/\$USER_UID" "\$PLIST" 2>/dev/null || true
    for i in \$(seq 1 60); do [ -S "\$SOCKET" ] && break; sleep 0.2; done
fi
exit 0
POSTINSTALL
chmod +x "$PKG_ROOT/scripts/postinstall"

echo "[6/6] Building PKG..."
pkgbuild --root "$PKG_ROOT/Applications" \
    --identifier com.motioncontrol.app \
    --version "$VERSION" \
    --install-location "/Applications" \
    --scripts "$PKG_ROOT/scripts" \
    --sign "$SIGN_PKG" \
    "$OUTPUT_PKG"

echo ""
echo "✅ PKG built: $OUTPUT_PKG ($(ls -lh "$OUTPUT_PKG" | awk '{print $5}'))"
rm -rf "$PKG_ROOT"
