# 光标速度 + 叠加层闪烁修复 — 实施计划

**基于日志分析的两个问题**

---

## 问题①：速度太慢

**根因分析：**
- 当前速度公式：`rawVx = (tip.x - pip.x) × screenWidth × mouseSensitivity`
- `(tip.x - pip.x)` 是食指 tip-PIP 在 Vision 归一化坐标中的 x 向距离（实测 0.01~0.03）
- 乘以默认灵敏度 2.0 后：0.02 × 1440 × 2.0 = **57.6 pts/sec**
- 横跨 1440px 屏幕需 **25 秒**
- 公式中 `length × screenWidth` 被 `direction.x = dx/length` 抵消了，实际起效的只有 `dx × screenWidth × sensitivity`

**方案：** 在 `length × screen.width` 后加一个速度放大系数 `CursorSpeedMultiplier`，分辨率自适应

```swift
// 方案一：在计算处加系数（推荐）
cursorController.updateFingerDirection(direction,
                                       length: length * screen.width * CursorSpeedMultiplier,
                                       sensitivity: CGFloat(config.mouseSensitivity))
```

| multiplier | 速度 | 横跨 1440px |
|-----------|------|------------|
| 1x (当前) | 58 pts/sec | 25s |
| 3x | 173 pts/sec | 8.3s |
| **6x** | **346 pts/sec** | **4.2s** |

取值建议：**6x**，横跨屏幕约 4 秒，精细移动也不至于飞。

## 问题②：摄像头叠加层绿色关键点闪烁

**根因分析：**
- `CameraPreviewView.swift:160-175` 每帧画 21 个手部关键点（绿色圆点，直径 8pt）
- `needsDisplay = true` 每帧重绘整个 CALayer，绿色圆点在画面中间闪烁
- 用户以为是「假光标」

**方案：** 减小关键点尺寸 + 降低不透明度，从视觉上弱化

```swift
// 改前：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.8).cgColor)
let rect = CGRect(x: displayPoint.x - 4, y: displayPoint.y - 4, width: 8, height: 8)
// 改后：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.35).cgColor)
let rect = CGRect(x: displayPoint.x - 2, y: displayPoint.y - 2, width: 4, height: 4)
```

同时面部关键点同理缩小淡化（从 4pt → 2pt）。

---

## 改动类型分级

| 改动 | 文件 | 类型 | 说明 |
|------|------|------|------|
| 增加速度放大系数 | MotionControlApp.swift:163 | P-LOGIC | `length * screen.width` 后乘 6 |
| 降低叠加层视觉干扰 | CameraPreviewView.swift | P-PARAM | 关键点尺寸和透明度 |

---

### Task 1：增加速度放大系数

**Objective：** 在方向速度计算中加分辨率无关的放大系数 `* 6`

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:163`

**改动：**
```swift
// 改前：
length: length * screen.width,
// 改后：
length: length * screen.width * 6,
```

**验证方法：** 编译后手指移动光标速度应明显提升，横跨屏幕约 4 秒

**提交信息：** `perf: 光标速度放大 6 倍（分辨率自适应）`

---

### Task 2：降低叠加层视觉干扰

**Objective：** 减小手部/面部关键点的绘制尺寸和不透明度，消除闪烁感

**类型：** P-PARAM

**Files：**
- Modify: `Sources/MotionControl/Views/CameraPreviewView.swift`

**改动一：手部关键点（第 161-174 行）**
```swift
// 改前：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.8).cgColor)
// 每个点 rect: x-4, y-4, width: 8, height: 8

// 改后：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.35).cgColor)
// 每个点 rect: x-2, y-2, width: 4, height: 4
```

**改动二：面部关键点（第 145-158 行）**
```swift
// 改前：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.6).cgColor)
// 每个点 rect: x-2, y-2, width: 4, height: 4

// 改后：
ctx.setFillColor(NSColor.green.withAlphaComponent(0.25).cgColor)
// 每个点 rect: x-1, y-1, width: 2, height: 2
```

**验证方法：** 编译后观察摄像头预览界面，绿色关键点应明显变淡变小，不再闪烁干扰

**提交信息：** `style: 降低叠加层关键点透明度（手部 0.35/4pt，面部 0.25/2pt）`

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 按 Task 顺序用 Aider 执行，每个 Task 独立编译验证 + 提交。
