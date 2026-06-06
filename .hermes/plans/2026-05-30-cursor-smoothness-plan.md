# 手指光标平滑性与速度优化 — 实施计划

> **对于调度 Agent：** 按 Task 顺序逐个执行，每个 Task 改完编译验证 + 独立提交。

**目标：** 解决手指跟踪光标「慢 + 不丝滑」问题，从 6fps/10s 跨屏提升到 15fps/3s 跨屏

**架构方案：**
- 提高帧处理率（1/5 → 1/2）
- 放宽 OneEuroFilter 让响应更快
- 用实际帧间隔计算 dt（不硬编码 1/30）
- 提高默认灵敏度

**改动类型分级：**

| 改动 | 类型 | 执行方式 |
|------|------|---------|
| 帧降采样 %5 → %2 | P-PARAM | 直接 Aider |
| OneEuroFilter 参数 | P-PARAM | 直接 Aider |
| mouseSensitivity 默认值 | P-PARAM | 直接 Aider |
| CursorController 支持动态 dt | P-LOGIC | plan+审批 |
| 调用处传递动态 dt | P-LOGIC | plan+审批 |

---

### Task 1：提升帧处理率

**Objective：** 将 DetectionPipeline 的帧降采样从每 5 帧处理 1 帧改为每 2 帧处理 1 帧

**类型：** P-PARAM

**Files：**
- Modify: `Sources/MotionControl/Detection/DetectionPipeline.swift:50`

**Step 1：改参数**

在 `DetectionPipeline.swift` 第 50 行，将：
```swift
guard frameCount % 5 == 0 else { return }
```
改为：
```swift
guard frameCount % 2 == 0 else { return }
```

**Step 2：编译验证**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -5
```
预期：`Build complete!`（零错误）

**Step 3：提交**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
git add Sources/MotionControl/Detection/DetectionPipeline.swift
git commit -m "perf: 帧降采样从 %5 改为 %2，提升光标更新率至 15fps"
```

**回退方法：** `git reset --hard HEAD~1`

---

### Task 2：调整 OneEuroFilter 参数

**Objective：** 将 CursorController 中 OneEuroFilter 的滤波参数改激进，减少响应延迟

**类型：** P-PARAM

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift:15`

**Step 1：改参数**

在 `CursorController.swift` 第 15 行，将：
```swift
init(minCutoff: Double = 1.0, beta: Double = 0.007)
```
改为：
```swift
init(minCutoff: Double = 3.0, beta: Double = 0.02)
```

**参数说明：**
- `minCutoff: 1.0 → 3.0`：静止时截止频率提高 3 倍，滤波 alpha 从 0.97 → 0.91，更多新值通过
- `beta: 0.007 → 0.02`：速度敏感度提升，快速移动时延迟更低

**Step 2：编译验证**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -5
```
预期：`Build complete!`（零错误）

**Step 3：提交**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
git add Sources/MotionControl/Control/CursorController.swift
git commit -m "perf: 调高 OneEuroFilter minCutoff(1→3) 和 beta(0.007→0.02) 减少延迟"
```

**回退方法：** `git reset --hard HEAD~1`

---

### Task 3：调整默认鼠标灵敏度

**Objective：** 将默认 mouseSensitivity 从 1.0 提高到 2.0，让光标移动速度翻倍

**类型：** P-PARAM

**Files：**
- Modify: `Sources/MotionControl/Config/GestureConfig.swift:176`

**Step 1：改默认值**

在 `GestureConfig.swift` 第 176 行，将：
```swift
var mouseSensitivity: Float = 1.0
```
改为：
```swift
var mouseSensitivity: Float = 2.0
```

> **注意：** 此值只在首次运行时作为默认值，已有 config.json 的用户不会被覆盖（ConfigManager 第 37 行强制重置手势映射为默认，但不重置 mouseSensitivity）。如果你已运行过 MotionControl，需要手动删除配置或调灵敏度滑块。

**Step 2：编译验证**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -5
```
预期：`Build complete!`（零错误）

**Step 3：提交**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
git add Sources/MotionControl/Config/GestureConfig.swift
git commit -m "feat: 默认鼠标灵敏度从 1.0 提高到 2.0"
```

**回退方法：** `git reset --hard HEAD~1`

---

### Task 4：CursorController 支持动态 dt

**Objective：** CursorController 的 `updateFingerDirection` 和 `computeCursor` 改用传入的实际帧间隔 dt，而非硬编码 1/30

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Control/CursorController.swift`

**Step 1：修改 updateFingerDirection 签名**

将第 120 行签名从：
```swift
func updateFingerDirection(_ direction: CGPoint, length: CGFloat, sensitivity: CGFloat) {
```
改为：
```swift
func updateFingerDirection(_ direction: CGPoint, length: CGFloat, sensitivity: CGFloat, dt: Double = 1.0 / 30.0) {
```

**Step 2：修改 filter 调用传 dt**

第 124 行将：
```swift
let filtered = fingerFilter.filter(x: rawVx, y: rawVy, dt: 1.0 / 30.0)
```
改为：
```swift
let filtered = fingerFilter.filter(x: rawVx, y: rawVy, dt: dt)
```

**Step 3：修改 computeCursor 签名**

将第 136 行签名从：
```swift
func computeCursor(screenSize: CGSize, sensitivity: Float) -> CGPoint {
```
改为：
```swift
func computeCursor(screenSize: CGSize, sensitivity: Float, dt: CGFloat = 1.0 / 30.0) -> CGPoint {
```

**Step 4：修改 computeCursor 内部 dt**

第 140 行将：
```swift
let dt: CGFloat = 1.0 / 30.0
```
改为：
```swift
// dt 改为使用传入参数（Method parameter）
```

即去掉局部 `let dt: CGFloat = 1.0 / 30.0` 的定义，直接使用参数 `dt`。

完整改后代码第 138-143 行应为：
```swift
var newBase = baseCursor
if fingerActive {
    newBase.x += CGFloat(filteredVelocity.x) * dt
    newBase.y += CGFloat(filteredVelocity.y) * dt
}
```

**Step 5：编译验证**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -5
```
预期：`Build complete!`（零错误，因为默认参数兼容旧调用方）

**Step 6：提交**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
git add Sources/MotionControl/Control/CursorController.swift
git commit -m "refactor: updateFingerDirection 和 computeCursor 支持动态 dt 参数"
```

**回退方法：** `git reset --hard HEAD~1`

---

### Task 5：调用处传递动态 dt

**Objective：** 在 `MotionControlApp.swift` 的 `onHandResult` 回调中计算实际帧间隔 dt，并传给 CursorController

**类型：** P-LOGIC

**Files：**
- Modify: `Sources/MotionControl/Detection/DetectionPipeline.swift` — 输出实际帧率信息
- Modify: `Sources/MotionControl/App/MotionControlApp.swift` — 计算 dt 并传递

**Step 1：DetectionPipeline 暴露帧间隔**

在 `DetectionPipeline.swift` 中添加一个公开方法获取实际帧间隔（用时间戳计算）：

在 `DetectionPipeline.swift` 第 25 行附近（`private var frameCount = 0` 后面）添加：
```swift
private var lastProcessedTime: Date = .distantPast
```

在 `didOutputFrame` 中，`guard frameCount % 2 == 0` 条件通过后，添加 dt 计算（放在 `guard let self = self` 后面，第 53 行前）：
```swift
let now = Date()
let frameDt = lastProcessedTime == .distantPast ? (1.0 / 15.0) : now.timeIntervalSince(lastProcessedTime)
lastProcessedTime = now
```

但 dt 需要传给外部。有两种方式：
1. 在 `HandPoseResult` 中添加 dt 字段
2. 在 `onHandResult` 回调中添加 dt 参数

方案 2 更干净。但改变回调签名是 P-ARCH。不过既然已经确认了 plan，我们直接改。

**修改 onHandResult 类型：**

将 `DetectionPipeline.swift` 第 21 行：
```swift
var onHandResult: ((HandPoseResult?) -> Void)?
```
改为：
```swift
var onHandResult: ((HandPoseResult?, dt: TimeInterval) -> Void)?
```

在 `didOutputFrame` 第 56-59 行修改回调调用处：
```swift
DispatchQueue.main.async {
    self.onGesture?(gestureEvent)
    self.onHandResult?(handResult, dt: frameDt)  // 添加 dt
}
```

同样第 62-64 行 nil 情况也要传一个默认 dt：
```swift
DispatchQueue.main.async {
    self.onHandResult?(nil, dt: 1.0/15.0)
}
```

**Step 2：MotionControlApp.swift 传递 dt**

修改第 106 行回调签名：
```swift
detectionPipeline.onHandResult = { handResult, dt in
```

修改第 163-165 行的 updateFingerDirection 调用：
```swift
cursorController.updateFingerDirection(direction,
                                       length: length * screen.width,
                                       sensitivity: CGFloat(config.mouseSensitivity),
                                       dt: dt)
```

修改第 175 行的 computeCursor 调用：
```swift
let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0, dt: CGFloat(dt))
```

**Step 3：编译验证**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -10
```
预期：`Build complete!`（零错误）

**Step 4：提交**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
git add Sources/MotionControl/Detection/DetectionPipeline.swift Sources/MotionControl/App/MotionControlApp.swift
git commit -m "feat: onHandResult 传递实际帧间隔 dt，cursor 使用动态 dt"
```

**回退方法：** `git reset --hard HEAD~1`

---

### Task 6：编译验证 + 启动测试

**Objective：** 整体编译通过后启动 App 验证效果

**Files：** 无代码改动

**Step 1：完整编译**

```bash
cd /Users/diqibadao/Desktop/vibe项目/MotionControl
swift build 2>&1 | tail -10
```
预期：`Build complete!`

**Step 2：启动 App**

```bash
open /Users/diqibadao/Desktop/vibe项目/MotionControl/.build/MotionControl.app
```

**Step 3：运行后观察**
- 手指移动时光标是否更流畅（不跳帧）
- 光标移动速度是否变快
- 确认 FPS 显示从 ~6 提升到 ~15

---

## 审批

状态：✅ 已确认
确认人：老板
确认时间：2026-05-30

---

> 按 Task 顺序逐个用 Aider 执行，每个 Task 独立编译验证 + 提交。
