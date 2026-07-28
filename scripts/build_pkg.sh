#!/bin/bash
set -e
echo "=== MotionControl PKG Builder v0.9.0 ==="

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
VERSION="0.9.1"
SIGN_APP="E8C6A3F3FD92B4EF51BD9DA41151883D1EBBFFB8"
SIGN_PKG="3rd Party Mac Developer Installer: wang bangdong (J5V4KAAAY3)"
OUTPUT_PKG="$BUILD_DIR/MotionControl-${VERSION}.pkg"
# 关键：socket 必须在 App 沙盒容器内！沙盒 App 无法访问 /tmp
SOCKET="$HOME/Library/Containers/com.motioncontrol.app/Data/tmp/axhelper.sock"
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

# 关键：用 console user 身份启动 AXHelper，否则 root 启动的 socket
# 沙盒 App (用户身份) 连不上 root 启动的 socket
CONSOLE_USER=\$(stat -f%Su /dev/console 2>/dev/null || echo "")
if [ -n "\$CONSOLE_USER" ] && [ "\$CONSOLE_USER" != "root" ]; then
    USER_UID=\$(id -u "\$CONSOLE_USER" 2>/dev/null || echo "501")

    # 杀掉之前的所有 AXHelper
    pkill -f AXHelper 2>/dev/null || true
    rm -f "\$SOCKET"
    sleep 0.5

    # 以用户身份启动 AXHelper，LaunchAgent 保持运行
    LAUNCHD_DIR="/Users/\$CONSOLE_USER/Library/LaunchAgents"
    PLIST="\$LAUNCHD_DIR/com.motioncontrol.axhelper.plist"
    mkdir -p "\$LAUNCHD_DIR"
    chown "\$CONSOLE_USER:staff" "\$LAUNCHD_DIR" 2>/dev/null || true

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
    <key>StandardOutPath</key>
    <string>/tmp/motioncontrol_axhelper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/motioncontrol_axhelper.err</string>
</dict>
</plist>
PLIST_EOF
    chown "\$CONSOLE_USER:staff" "\$PLIST" 2>/dev/null || true
    chmod 644 "\$PLIST" 2>/dev/null || true

    # 用 launchctl asuser 启动 LaunchAgent（用户身份）
    launchctl asuser "\$USER_UID" launchctl bootout "gui/\$USER_UID/com.motioncontrol.axhelper" 2>/dev/null || true
    launchctl asuser "\$USER_UID" launchctl bootstrap "gui/\$USER_UID" "\$PLIST" 2>/dev/null || true

    # 等 socket 就绪
    for i in \$(seq 1 60); do
        [ -S "\$SOCKET" ] && break
        sleep 0.2
    done

    if [ -S "\$SOCKET" ]; then
        # 修复 socket 权限：让 sandbox App 可读可写
        chmod 666 "\$SOCKET" 2>/dev/null || true
        echo "AXHelper started OK (user=\$CONSOLE_USER)"
    else
        echo "AXHelper socket not ready, check /tmp/motioncontrol_axhelper.err"
        cat /tmp/motioncontrol_axhelper.err 2>/dev/null | head -3
    fi
else
    echo "No console user detected"
    # 兜底：用 root 启动
    pkill -f AXHelper 2>/dev/null || true
    rm -f "\$SOCKET"
    "\$HELPER" --socket "\$SOCKET" >/var/log/motioncontrol_axhelper.log 2>&1 &
    sleep 2
    chmod 666 "\$SOCKET" 2>/dev/null || true
fi

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