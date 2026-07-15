#!/bin/bash
# 构建 MotionControl.app bundle 并启动，确保 TCC 权限弹窗正常工作
set -e
cd "$(dirname "$0")/.."

BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_DIR="$BUILD_DIR/MotionControl.app"
BINARY="$BUILD_DIR/MotionControl"
AXHELPER="$BUILD_DIR/AXHelper"
RESOURCES="Sources/MotionControl/Resources"
INFO_PLIST="Sources/MotionControl/Info.plist"

echo "🔨 Building..."
swift build 2>&1 | tail -1

echo "📦 Bundling MotionControl.app..."

# Kill existing
killall MotionControl 2>/dev/null || true
killall AXHelper 2>/dev/null || true
sleep 0.5

# Clean & recreate .app bundle
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binaries
cp "$BINARY" "$APP_DIR/Contents/MacOS/MotionControl"
cp "$AXHELPER" "$APP_DIR/Contents/MacOS/AXHelper" 2>/dev/null || echo "⚠️  AXHelper 不存在，跳过"

# Copy Info.plist & Resources
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$RESOURCES"/* "$APP_DIR/Contents/Resources/" 2>/dev/null || true

# Ad-hoc sign (required for TCC)
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "🚀 Launching..."
open "$APP_DIR"

echo "✅ App bundle launched, check for permission dialog."
