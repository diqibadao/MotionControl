# 光标控制重构 — 行业标准 EMA 位置映射方案

**放弃 velocity 累积，改用指尖位置直接映射 + EMA 平滑**

---

## 核心改动

将方向向量→velocity→累积位置 的复杂链路，替换为行业通用的：

```
指尖 Vision 坐标 → (镜像+翻转) → 屏幕目标位置 → EMA 平滑 → 光标
```

| 维度 | 当前（velocity 累积）| 新方案（位置+EMA）|
|------|-------------------|-----------------|
| 输入 | tip.x - pip.x 方向向量 | indexTip 绝对坐标 |
| 映射 | dx * screenWidth * 灵敏度 * 加速度曲线 | (1-x)*宽, y*高 |
| 平滑 | OneEuroFilter + 0.92 阻尼 | EMA: += (target - current) / 7 |
| 卡角 | baseCursor 漂移 | 目标位置在屏幕内，天然不卡 ✅ |
| 死区 | 额外加 | EMA 分离量小 → 自动忽略 ✅ |
| 方向 | dx/dy 要手工翻转 | x 镜像 + y 翻转即正确 ✅ |

**改两个文件：**
- `CursorController.swift` — 重写为位置+EMA
- `MotionControlApp.swift` — 用 tip 坐标直接映射

---

### Task 1：重构 CursorController

**Objective：** 去掉 OneEuroFilter/filteredVelocity/baseCursor/velocity 阻尼，改为位置+EMA

**Files：**
- Rewrite: `Sources/MotionControl/Control/CursorController.swift`

**新结构：**

```swift
class CursorController {
    // 注视追踪（保留）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0
    private var gazeActive = false
    
    // EMA 平滑后的光标位置
    private var currentPosition: CGPoint = .zero
    
    // 手指是否激活
    private(set) var fingerActive = false
    
    // EMA 平滑系数（行业标准值）
    private let smoothingFactor: CGFloat = 7
    
    // 1. 设置目标位置（从 MotionControlApp 调用）
    func updateTargetPosition(_ target: CGPoint) {
        currentPosition.x += (target.x - currentPosition.x) / smoothingFactor
        currentPosition.y += (target.y - currentPosition.y) / smoothingFactor
        fingerActive = true
    }
    
    // 2. 添加注视偏移 → 返回最终光标位置
    func computeCursor(screenSize: CGSize, sensitivity: Float) -> CGPoint {
        var cursor = currentPosition
        if gazeActive {
            cursor.x += CGFloat(yawOffset) * screenSize.width * 0.05
            cursor.y += CGFloat(pitchOffset) * screenSize.height * 0.05
        }
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))
        return cursor
    }
    
    // 注视追踪（不变）
    func updateGazeOffset(yaw: Float, pitch: Float, hasFace: Bool) { ... }
    func resetGaze() { ... }
    func resetCursor() { currentPosition = .zero; fingerActive = false }
    
    // 删除：OneEuroFilter, filteredVelocity, baseCursor, updateFingerDirection, damping
}
```

**移除的属性和方法：**
- `OneEuroFilter` 内部类
- `filteredVelocity: CGPoint`
- `baseCursor: CGPoint`
- `fingerFilter: OneEuroFilter`
- `updateFingerDirection()` 方法
- `updateHandTip()` 方法
- velocity 阻尼逻辑

**新增：**
- `currentPosition: CGPoint` — EMA 平滑后的光标位置
- `smoothingFactor: CGFloat = 7` — 行业标准值
- `updateTargetPosition(_:)` — 新入口

---

### Task 2：MotionControlApp 用 tip 坐标映射

**Objective：** 方向向量 → 指尖绝对位置直接映射

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:132-173`

**改后的逻辑：**

```swift
// 原方向+velocity 代码（全部删除）：
// let dx = tip.x - pip.x
// let dy = tip.y - pip.y
// let length = sqrt(...)
// let speedMultiplier = ...
// cursorController.updateFingerDirection(direction, length:..., ...)

// 新代码（替换）：
let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)

// 行业标准：指尖 Vision 坐标 → 屏幕坐标
// X: 镜像（前置摄像头画面镜像） → (1 - tip.x) * 屏幕宽
// Y: Vision y↑ → 光标 y↓ → tip.y * 屏幕高
let targetX = (1.0 - tip.x) * screen.width
let targetY = tip.y * screen.height

// 激活条件保留（只有食指伸出且其他手指收回时才控制光标）
let extensions = handResult.fingerExtension()
let indexExt = extensions[.index] ?? 0
let middleExt = extensions[.middle] ?? 0
let ringExt = extensions[.ring] ?? 0
let littleExt = extensions[.little] ?? 0
let thumbExt = extensions[.thumb] ?? 0

let otherLow = middleExt < 0.30 && ringExt < 0.30 && littleExt < 0.30 && thumbExt < 0.30
let allHigh = [indexExt, middleExt, ringExt, littleExt, thumbExt].allSatisfy { $0 > 0.5 }

if indexExt > 0.06 && otherLow && !allHigh {
    cursorController.updateTargetPosition(CGPoint(x: targetX, y: targetY))
}

// computeCursor 调用不变
let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0)
mouseCtrl.moveCursor(to: finalCursor)
```

**核心变化：** 不再传 direction/length/sensitivity/dt，直接传屏幕目标位置

---

## 改动摘要

| Task | 文件 | 操作 | 说明 |
|------|------|------|------|
| 1 | CursorController.swift | 重写 | 删除 ~60 行旧代码，加 ~30 行新代码 |
| 2 | MotionControlApp.swift | 修改 | 替换方向计算为位置映射，约删 20 行加 15 行 |

**删除的概念：** velocity、阻尼、加速度曲线、死区、OneEuroFilter、baseCursor 漂移问题

**保留的概念：** 注视追踪、手指激活条件（indexExt > 0.06 && otherLow）

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> Task 1 和 2 分两次 Aider 调用执行，每次编译验证 + 独立提交。
