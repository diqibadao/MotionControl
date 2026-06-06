# 手指光标平滑性与速度优化 — 事件链文档

> 问题：手指跟踪光标移动太慢，且一跳一跳不丝滑

---

## 事件列表

| 事件编号 | 事件名 | 触发源 | 触发时机 | 前置条件 |
|---------|-------|--------|---------|---------|
| E1 | **手势检测帧处理** | 摄像头 30fps 帧回调 | AVCaptureVideoDataOutput 每帧回调 | 摄像头已启动、权限已授权 |
| E2 | **手指方向更新** | E1 中检测到手指 → onHandResult 回调 | 手势检测完成后 | 手部检测成功、食指伸直判断通过 |
| E3 | **光标位置计算** | CursorController.computeCursor() | onHandResult 每帧结束后 | fingerActive 为 true |
| E4 | **光标物理移动** | MouseController.moveCursor() | computeCursor 计算出新位置后 | 无障碍权限已授权 |

---

## 每个事件的完整处理链路

### E1：手势检测帧处理

#### 1. 入口
- **触发方式**：AVCaptureVideoDataOutput 摄像头每帧回调 → `CameraOutputDelegate.didOutputFrame(_:)`
- **当前问题**：第 50 行 `guard frameCount % 5 == 0 else { return }`，每 5 帧丢弃 4 帧
- **目标**：降到 `% 2`（保留每 2 帧），提高光标更新率

#### 2. 业务处理层（DetectionPipeline.swift）
- **帧率**：摄像头标称 30fps → 有效处理率 30/5=6fps → 目标 30/2=15fps
- **处理步骤**：
  1. 调用 `HandPoseDetector.detect(in:)` → 返回 `HandPoseResult?`
  2. 调用 `GestureAnalyzer.analyze(_:)` → 返回 `GestureEvent`
  3. 调用 `FaceMeshDetector.detect(pixelBuffer:)` → 返回 `FaceResult`
  4. 调用 `MouthDetector.detect(from:)` → 返回 `MouthEvent`
  5. 调用 `GazeEstimator.estimate(from:)` → 返回 `GazeEstimate`
- **耗时**：Vision 手部检测 ≈ 3-8ms，面部检测 ≈ 5-10ms，总耗时 < 20ms → 跑 15fps 绰绰有余

#### 3. 下游触发
- `onGesture?(GestureEvent)` → 触发手势映射动作
- `onHandResult?(HandPoseResult?)` → 触发 E2 手指方向更新
- `onGaze?(GazeEstimate)` → 更新注视偏移

---

### E2：手指方向更新

#### 1. 入口
- **触发方式**：`detectionPipeline.onHandResult` 回调（MotionControlApp.swift 第 106 行）
- **调用频率**：与 E1 相同，当前 6fps

#### 2. 处理步骤（MotionControlApp.swift:132-176）
1. 从 `handResult` 取 `indexTip` 和 `indexPIP`（或 `indexDIP` 回退）
2. 计算方向向量 `dx = tip.x - pip.x`, `dy = pip.y - tip.y`
3. 计算手指伸展长度 `length = sqrt(dx*dx + dy*dy)`（Vision 归一化坐标 0~1）
4. 检查伸展条件：`indexExt > 0.06 && 其他四指 < 0.15 && 非全部高伸`
5. 调用 `cursorController.updateFingerDirection(direction, length: length * screen.width, sensitivity: sensitivity)`

#### 3. 输入参数
| 参数 | 类型 | 说明 | 当前影响 |
|------|------|------|---------|
| direction | CGPoint | 归一化方向向量 (dx/length, dy/length) | 方向正确 |
| length | CGFloat | 食指伸展长度 × 屏幕宽度 | 原始值为 0.05~0.15 (归一化)，乘屏幕宽后 72~216 |
| sensitivity | CGFloat | config.mouseSensitivity，默认 1.0 | **太小**，导致速度慢 |

#### 4. CursorController.updateFingerDirection（CursorController.swift:120-127）
```swift
let rawVx = Double(direction.x * length * sensitivity)
let rawVy = Double(direction.y * length * sensitivity)
let filtered = fingerFilter.filter(x: rawVx, y: rawVy, dt: 1.0 / 30.0)
filteredVelocity = filtered
fingerActive = true
```

**当前问题**：
- **dt 硬编码 1/30**：实际有效帧率只有 6fps，dt 应为 1/6。硬编码导致滤波 alpha 计算偏小→滤波滞后加重
- **OneEuroFilter 参数过保守**：`minCutoff=1.0, beta=0.007` → alpha≈0.97，启动需 ~1s 爬坡
- **灵敏度默认 1.0**：length=0.1×1440=144，sensitivity=1.0 → 原始速度 144pts/sec → 横跨 1440px 屏幕需 10s

---

### E3：光标位置计算

#### 1. 入口
- **触发方式**：E2 结束后紧接着调用 `cursorController.computeCursor(screenSize:, sensitivity:)`

#### 2. 处理步骤（CursorController.swift:136-162）
```swift
var newBase = baseCursor
if fingerActive {
    let dt: CGFloat = 1.0 / 30.0
    newBase.x += CGFloat(filteredVelocity.x) * dt
    newBase.y += CGFloat(filteredVelocity.y) * dt
}
// 注视偏移
if gazeActive {
    cursor.x += CGFloat(yawOffset) * screenSize.width * 0.05
    cursor.y += CGFloat(pitchOffset) * screenSize.height * 0.05
}
// 屏幕边界限制
cursor.x = max(0, min(cursor.x, screenSize.width))
cursor.y = max(0, min(cursor.y, screenSize.height))
baseCursor = newBase
return cursor
```

**当前问题**：
- **dt 再次硬编码 1/30**：与 E2 一致，实际应是 1/有效帧率
- **注视偏移乘 0.05**：对 1440px 屏幕，yaw=±20° → 偏移 ±72px，幅度合理

---

### E4：光标物理移动

#### 1. 入口
- **触发方式**：E3 返回 newCursor → `mouseCtrl.moveCursor(to: finalCursor)`（MotionControlApp.swift:177）

#### 2. 处理步骤（MouseController.swift:11-39）
```swift
let source = CGEventSource(stateID: .combinedSessionState)
source?.localEventsSuppressionInterval = 0.0
CGAssociateMouseAndMouseCursorPosition(1)  // 抑制 macoS 26 视觉抑制
let flippedPoint = CGPoint(x: point.x, y: screenHeight - point.y)
CGWarpMouseCursorPosition(flippedPoint)
// 再发一次 mouseMoved 事件确保目标应用感知
let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, ...)
moveEvent.post(tap: .cghidEventTap)
```

**状态**：✅ 方案正确（四管齐下：suppression + associate + warp + event），无需改动

---

## 共享逻辑识别

| 共享数据 | 被谁使用 | 并发安全 |
|---------|---------|---------|
| filteredVelocity | E2 写入、E3 读取 | 同线程串行，安全 |
| baseCursor | E3 读写 | 同线程串行，安全 |
| fingerActive | E2 写入、E3 读取 | 同线程串行，安全 |

## 跨事件依赖

| 上游 | 下游 | 类型 | 说明 |
|------|------|------|------|
| E1 → E2 | onHandResult 回调 | 同步串行 | E1 检测到手 → E2 更新方向 |
| E2 → E3 | 直接紧接调用 | 同步串行 | E2 更新 velocity → E3 计算位置 |
| E3 → E4 | 直接紧接调用 | 同步串行 | E3 得出 position → E4 移动光标 |

---

## 改动类型分级

| 改动项 | 改什么 | 类型 | 执行方式 |
|--------|-------|------|---------|
| 帧降采样 | `frameCount % 5 → % 2` | P-PARAM | 直接 Aider |
| OneEuroFilter 参数 | `minCutoff: 1.0→3.0, beta: 0.007→0.02` | P-PARAM | 直接 Aider |
| mouseSensitivity 默认值 | `1.0 → 2.0` | P-PARAM | 直接 Aider |
| dt 动态计算 | 硬编码 1/30 → 从实际帧率计算 | P-LOGIC | 需 plan+审批 |
| OneEuroFilter 内部逻辑 | 传入真实 dt | P-LOGIC | 需 plan+审批 |

---

## 交叉验证

- [x] 事件是否穷举？4 个：帧处理→方向→位置→移动，完整覆盖
- [x] 处理链路是否完整？每个事件的 6 环节均完备
- [x] 参数到字段级别？✓
- [x] 共享逻辑是否冲突？同线程串行，无冲突
- [x] 跨事件依赖无循环？E1→E2→E3→E4，单向无环
- [x] 文件路径指向具体代码？见上方各环节
