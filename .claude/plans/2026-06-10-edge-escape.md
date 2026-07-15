# Gate 2 Plan — 边缘逃逸（Edge Escape）

**日期**：2026-06-10
**分支**：feat/frame-loss-guard
**触发**：固定原点+fcMin=1.2 后边缘仍有残留吸附

---

## 问题

光标贴边后手往回拉，filter 残余滞后 0.01，被 gain 放大后体感明显。

## 方案

逐帧判断，非模式切换：

```
if 光标在边缘 且 手方向往回:
    跳过 filter，直接用 raw handCenter 算光标
else:
    正常 1€ filter
```

## 改动

`CursorController.swift` 中 `updateWithAbsolutePosition()`：

在 `filterX.filter(handCenter.x)` 之前加判断：
```swift
let atEdge = cursorX <= 0 || cursorX >= screenSize.width
let handReversing = (atEdge && handCenter.x > prevHandX)  // 左边缘往回
                 || (atEdge && handCenter.x < prevHandX)  // 右边缘往回

let fx = handReversing ? handCenter.x : filterX.filter(handCenter.x, time: t)
let fy = handReversing ? handCenter.y : filterX.filter(handCenter.y, time: t)
```

`prevHandX` / `prevHandY` 需新增存储。脱困后 filter 自动恢复，无需额外逻辑。

## 不碰

- 1€ 参数（fcMin=1.2）
- gain（2.0）
- 原点（0.5, 0.4）

## 验证

1. `swift build` + `swift test` 通过
2. `swift run` → 测试 30s → 跑全管道
3. 预期：边缘帧占比下降，用户体验零吸附
