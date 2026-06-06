# macOS 26 Tahoe 程序化光标移动方案

> 2026-05-28 验证通过。MotionControl v0.2。

## 问题

macOS 26 Tahoe 引入了窗口隔离保护（防 tap-jacking），对程序化光标移动施加了**视觉渲染抑制**。每次调用 CGEvent 或 CGWarp 后，系统会冻结可见光标约 0.25 秒。

如果程序以高频率（如每帧）发送光标移动事件，抑制期不断重置，光标看起来完全不动。

`NSEvent.mouseLocation` 会正确更新为逻辑位置，但**可见光标不渲染**。

## 解决方案（四管齐下）

```swift
func moveCursor(to point: CGPoint) {
    // 1. 创建自定义事件源，抑制期归零
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.localEventsSuppressionInterval = 0.0

    // 2. 重连硬件鼠标子系统
    CGAssociateMouseAndMouseCursorPosition(1)  // boolean_t

    // 3. Y 坐标翻转（CGEvent 用 top-left 原点）
    let screenHeight = NSScreen.main?.frame.height ?? 0
    let flippedPoint = CGPoint(x: point.x, y: screenHeight - point.y)

    // 4. CGWarp 强制移动
    CGWarpMouseCursorPosition(flippedPoint)

    // 5. CGEvent post 到 HID 事件流
    if let moveEvent = CGEvent(mouseEventSource: source,
                               mouseType: .mouseMoved,
                               mouseCursorPosition: flippedPoint,
                               mouseButton: .left) {
        moveEvent.post(tap: .cghidEventTap)
    }
}
```

## 关键原理

| 步骤 | 作用 |
|------|------|
| `localEventsSuppressionInterval = 0.0` | 解除 macOS 强制视觉延迟 |
| `CGAssociateMouseAndMouseCursorPosition(1)` | 强制硬件/逻辑层同步 |
| `CGWarpMouseCursorPosition(flippedPoint)` | 底层光标 warp |
| `CGEvent(.mouseMoved).post(cghidEventTap)` | HID 事件注入 |

单独用哪个都不行，必须四个一起上。

## 版本 tag

```bash
git tag v0.2-cursor-moves-20260528
```

## 文件位置

`Sources/MotionControl/Control/MouseController.swift` → `moveCursor(to:)` 方法。
