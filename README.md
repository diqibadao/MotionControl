# MotionControl

Control your Mac with hand gestures — using just your webcam.

All processing runs **100% locally**. No data ever leaves your machine.

## Features

| Gesture | Action |
|---------|--------|
| ✋ Extend index finger | Move cursor |
| 👆 Pinch index + thumb | Left click |
| 👇 Pinch twice quickly | Double click |
| ✊ Pinch & drag up/down | Scroll |
| ✋ Pinch & hold | Drag start / end |

**Element overlay** — every clickable element on screen is highlighted with a green box. See exactly where you can click before you move your hand.

**Cursor snap** — cursor automatically snaps to the nearest button center when your hand is close. No more pixel-hunting.

**Privacy-first design** — camera stream stays on your machine. Open source privacy proof files let anyone verify.

**Menu bar control** — independent toggles for gesture detection, cursor movement, and camera preview.

## Requirements

- macOS 14 (Sonoma) or later
- Built-in or external webcam (720p+ recommended)
- Xcode 15+ (for building from source)

## Status

MotionControl 处于早期开发阶段。此仓库中的源代码仅用于**安全审查**，不包含核心手势引擎。

安装包已发布：[**Download MotionControl.dmg**](https://github.com/diqibadao/MotionControl/releases/latest)（macOS 14+，需要摄像头）

## Privacy

This repository contains privacy-proof source files:

- `CameraService.swift` — the entire camera pipeline, open for inspection
- `UIElementScanner.swift` — accessibility scanning scope and depth
- `AXHelper/main.swift` — AX tree traversal implementation
- `PermissionManager.swift` — all permission requests and their purpose

Nothing is transmitted. No analytics. No telemetry.

## License

CC BY-NC-ND 4.0 — view only, no commercial use, no derivatives.

---

**Bug reports & feature requests**: [Open an issue](https://github.com/diqibadao/MotionControl/issues)
