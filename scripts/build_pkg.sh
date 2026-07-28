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

echo "[1/5] Building..."
swift build -c release 2>&1 | tail -1

echo "[2/5] Package structure..."
PKG_ROOT="/tmp/mc_pkg_$$"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS"
mkdir -p "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources"
mkdir -p "$PKG_ROOT/scripts"

echo "[3/5] Copy + sign binaries..."

# 复制二进制
cp .build/release/MotionControl "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/"
cp .build/release/AXHelper "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/"
chmod +x "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/MotionControl"
chmod +x "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/AXHelper"

# 关键修复：单独签两个 binary（顺序很重要）
# 1. AXHelper 先签（无沙盒）
codesign --force --sign "$SIGN_APP" \
  --entitlements "$BUILD_DIR/Entitlements-NoSandbox.plist" \
  --timestamp=none \
  "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/AXHelper" 2>&1

# 2. MotionControl（沙盒）
codesign --force --sign "$SIGN_APP" \
  --entitlements "$BUILD_DIR/Entitlements.plist" \
  --timestamp=none \
  "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/MotionControl" 2>&1

# 3. 复制 Info.plist
cp Sources/MotionControl/Info.plist "$PKG_ROOT/Applications/MotionControl.app/Contents/"

# 4. 复制资源
if [ -f "$BUILD_DIR/MotionControl.app/Contents/Resources/AppIcon.icns" ]; then
    cp "$BUILD_DIR/MotionControl.app/Contents/Resources/AppIcon.icns" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ AppIcon.icns"
fi

if [ -f "$BUILD_DIR/MotionControl.app/Contents/Resources/Localizable.json" ]; then
    cp "$BUILD_DIR/MotionControl.app/Contents/Resources/Localizable.json" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ Localizable.json"
elif [ -f Sources/MotionControl/Resources/Localizable.json ]; then
    cp Sources/MotionControl/Resources/Localizable.json "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ Localizable.json (from Sources)"
fi

if [ -d ".build/release/MotionControl_MotionControl.bundle" ]; then
    cp -R ".build/release/MotionControl_MotionControl.bundle" "$PKG_ROOT/Applications/MotionControl.app/Contents/Resources/"
    echo "  ✓ Resource bundle"
fi

# 5. 签整个 bundle，--preserve-metadata=entitlements 防止覆盖内嵌 binary 的 entitlements
codesign --force --sign "$SIGN_APP" \
  --timestamp=none --preserve-metadata=entitlements \
  "$PKG_ROOT/Applications/MotionControl.app" 2>&1

# 验证
echo "  验证签名："
echo -n "  MotionControl: "
if codesign -d --entitlements - "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/MotionControl" 2>&1 | grep -q "app-sandbox"; then
    echo "✅ sandbox"
else
    echo "❌ NO sandbox"
fi
echo -n "  AXHelper: "
if codesign -d --entitlements - "$PKG_ROOT/Applications/MotionControl.app/Contents/MacOS/AXHelper" 2>&1 | grep -q "app-sandbox"; then
    echo "❌ HAS sandbox (should be empty)"
else
    echo "✅ no sandbox"
fi

echo "[4/5] Postinstall..."
cat > "$PKG_ROOT/scripts/postinstall" << POSTINSTALL
#!/bin/bash
set -e
HELPER="$HELPER_PATH"
SOCKET="$SOCKET"

chmod +x "\$HELPER" 2>/dev/null || true

echo "MotionControl: Configuring AXHelper..."
pkill -f AXHelper 2>/dev/null || true
rm -f "\$SOCKET"

"\$HELPER" --socket "\$SOCKET" >/var/log/motioncontrol_axhelper.log 2>&1 &

for i in \$(seq 1 50); do
    [ -S "\$SOCKET" ] && break
    sleep 0.2
done

[ -S "\$SOCKET" ] && echo "AXHelper started OK" || echo "AXHelper may need Accessibility permission"

exit 0
POSTINSTALL
chmod +x "$PKG_ROOT/scripts/postinstall"

echo "[5/5] Building PKG..."
pkgbuild --root "$PKG_ROOT/Applications" \
    --identifier com.motioncontrol.app \
    --version "$VERSION" \
    --install-location "/Applications" \
    --scripts "$PKG_ROOT/scripts" \
    --sign "$SIGN_PKG" \
    "$OUTPUT_PKG"

echo ""
echo "✅ PKG built: $OUTPUT_PKG ($(ls -lh "$OUTPUT_PKG" | awk '{print $5}'))"

# 验证 PKG 内的签名
echo ""
echo "===== PKG 内签名验证 ====="
pkgutil --expand "$OUTPUT_PKG" /tmp/verify_pkg_sign 2>/dev/null
mkdir -p /tmp/verify_extract_sign && cd /tmp/verify_extract_sign
cat /tmp/verify_pkg_sign/Payload | gunzip -dc | cpio -idmu 2>/dev/null

echo -n "  MotionControl (PKG 内): "
if codesign -d --entitlements - /tmp/verify_extract_sign/MotionControl.app/Contents/MacOS/MotionControl 2>&1 | grep -q "app-sandbox"; then
    echo "✅ sandbox"
else
    echo "❌ NO sandbox"
fi
echo -n "  AXHelper (PKG 内): "
if codesign -d --entitlements - /tmp/verify_extract_sign/MotionControl.app/Contents/MacOS/AXHelper 2>&1 | grep -q "app-sandbox"; then
    echo "❌ HAS sandbox"
else
    echo "✅ no sandbox"
fi

rm -rf /tmp/verify_pkg_sign /tmp/verify_extract_sign
rm -rf "$PKG_ROOT"