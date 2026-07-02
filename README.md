# MotionControl

Control your Mac with hand gestures — using just your webcam.

## Features

| Gesture | Action |
|---------|--------|
| ✋ Point | Move cursor |
| 👆 Pinch | Left click |
| 👇 Double pinch | Double click |
| ✊ Pinch & drag | Scroll |

- **Element overlay** — every clickable element on screen is highlighted
- **Cursor snap** — cursor auto-aligns to nearest button center
- **Menu bar** — toggle gesture/cursor/camera independently

All processing runs locally. No data leaves your machine.

## Build from source

```bash
git clone https://github.com/diqibadao/MotionControl.git
cd MotionControl
swift build -c release
./.build/release/MotionControl
```

> Build requires Xcode 15+ on macOS 14+.
> Core gesture recognition and cursor algorithms are not in this repository.
> Download the [Release DMG](https://github.com/diqibadao/MotionControl/releases/latest) for the full experience.

## License

CC BY-NC-ND 4.0 — view only, no commercial use, no derivatives.
