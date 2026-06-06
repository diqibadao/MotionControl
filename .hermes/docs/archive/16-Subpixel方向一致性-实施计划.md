# Sub-pixel 累积 + 方向一致性检查 — 实施计划

**问题：** 画十字时水平移动结束后的 EMA 拖尾导致垂直移动时 X 方向漂移，且 CGWarp 取整丢失小数导致跳变

**改动范围：** 一个文件 `CursorController.swift`，两处修改

---

## 改动 1：方向一致性检查

**位置：** `updateWithDelta` 方法内，Velocity EMA 之后、计算 smoothDx 之前

```swift
// 当前：
smoothVx = velocityEMAAlpha * rawVx + (1 - velocityEMAAlpha) * smoothVx
smoothVy = velocityEMAAlpha * rawVy + (1 - velocityEMAAlpha) * smoothVy

// 改为：
smoothVx = velocityEMAAlpha * rawVx + (1 - velocityEMAAlpha) * smoothVx
smoothVy = velocityEMAAlpha * rawVy + (1 - velocityEMAAlpha) * smoothVy

// 方向一致性：原始速度方向与平滑速度不一致 → 清零（防拖尾）
if rawVx * smoothVx <= 0 { smoothVx = 0 }
if rawVy * smoothVy <= 0 { smoothVy = 0 }
```

## 改动 2：Sub-pixel 余数累积

**位置：** `CursorController` 类中新增属性 + `updateWithDelta` 末尾修改累加逻辑

新增属性：
```swift
/// Sub-pixel 余数累积（鼠标驱动标准做法）
private var subPixelRemainderX: CGFloat = 0
private var subPixelRemainderY: CGFloat = 0
```

修改末尾累加逻辑（替换 `currentPosition.x += smoothDx * factor`）：
```swift
// 当前：
currentPosition.x += smoothDx * factor
currentPosition.y += smoothDy * factor

// 改为（Sub-pixel 累积）：
let moveX = smoothDx * factor
let moveY = smoothDy * factor
subPixelRemainderX += moveX
subPixelRemainderY += moveY

let intX = floor(subPixelRemainderX)
let intY = floor(subPixelRemainderY)
subPixelRemainderX -= intX
subPixelRemainderY -= intY

currentPosition.x += intX
currentPosition.y += intY
```

---

## 审批

状态：✅ 已确认
确认人：小明
确认时间：2026-05-31
