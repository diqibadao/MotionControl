# Gate 2 Plan — offset 上限修复

**日期**：2026-06-11
**分支**：feat/frame-loss-guard
**触发**：边缘拉不回来，根因是 cursorX 被 gain 放大后产生负数

---

## 根因

```
offset 无上限 → gain 放大 → cursorX 飞负 → clamp 兜底 → 回程死区
```

## 方案

offset 加天花板，cursorX 永不越界。

```
offset 上限 = 屏幕中心 ÷ (屏幕宽 × gain) = 0.5 / gain
offset 被夹在 [-上限, +上限] 内
→ cursorX 自然落在 [0, 屏幕宽]
→ 不需要 clamp 兜底
```

## 改动

`CursorController.swift` 第 294 行后加 4 行：
```swift
let maxOffsetX = screenCX / (screenSize.width * effectiveGain)
let maxOffsetY = screenCY / (screenSize.height * effectiveGain)
let clampedOffsetX = max(-maxOffsetX, min(offsetX, maxOffsetX))
let clampedOffsetY = max(-maxOffsetY, min(offsetY, maxOffsetY))
```

cursorX/CY 计算改用 clampedOffset。

## 不碰

- 1€ filter (fcMin=1.2)
- gain (2.0)
- gainMultiplier (1.0~1.3)
- 原点 (0.5, 0.4)
- clamp (保留，成摆设)

## 验证

1. swift build + swift test
2. swift run 测试 30s
3. 全管道分析
