# MotionControl 问题修复需求文档

> 生成时间: 2026-05-27
> 项目路径: ~/Desktop/vibe项目/MotionControl/

---

## 问题一：实时状态数据不显示 & 布局溢出

### 事件链

```
用户打开 MotionControl → 右侧状态面板显示
  → 状态数据字段（FPS、手势、置信度等）均为默认值（"—"/0）
  → 状态项垂直排列，超出窗口底部被裁剪
```

### 根因分析

1. **状态数据无更新链路**：`DetectionPipeline` 的 `onGesture`、`onMouthEvent`、`onGaze` 闭包在 `ContentView.onAppear` 中只被用于执行动作（鼠标点击/系统命令），没有同步更新到 `SystemState`。`SystemState` 中的 `currentGesture`、`gestureConfidence`、`mouthStatus`、`gazeActive`、`currentFPS`、`frameCount` 等字段从未被写入。
2. **FPS 从未计算**：`CameraService` 没有 FPS 统计逻辑，`SystemState.currentFPS` 永远是 0。
3. **布局溢出**：`StatusPanelView` 使用纯 `VStack`（无 `ScrollView`），当窗口高度不足时会超出底部。

### 修复方案

**A. 在 DetectionPipeline 或 ContentView 中建立状态同步链路**
- `onGesture` → 更新 `state.currentGesture`、`state.gestureConfidence`、`state.handDetected`、`state.handPosition`
- `onMouthEvent` → 更新 `state.mouthStatus`、`state.mouthOpenRatio`
- `onGaze` → 更新 `state.gazeActive`、`state.gazePosition`
- `onSampleBuffer` 回调中计算 FPS → 更新 `state.currentFPS`、`state.frameCount`
- 更新手脸检测状态：`state.handDetected`、`state.faceDetected`

**B. 修复布局**
- `StatusPanelView` 外包裹 `ScrollView`（或设置 `.frame(maxHeight: ...)`）
- 保持状态面板展开时不会溢出

### 字段级别

| SystemState 字段 | 数据来源 | 更新时机 | 默认值 |
|---|---|---|---|
| `currentFPS` | CameraService 帧计数 | 每秒一次 | `0` |
| `frameCount` | CameraService 帧计数 | 每帧 | `0` |
| `handDetected` | HandPoseDetector | 每次检测 | `false` |
| `faceDetected` | FaceMeshDetector | 每次检测 | `false` |
| `currentGesture` | GestureEvent.gestureType.displayName | 每次手势事件 | `"—"` |
| `gestureConfidence` | GestureEvent.confidence | 每次手势事件 | `0` |
| `handPosition` | GestureEvent.handPosition | 每次手势事件 | `.zero` |
| `gazeActive` | GazePoint | 每次注视事件 | `false` |
| `gazePosition` | GazePoint.point | 每次注视事件 | `.zero` |
| `mouthOpenRatio` | FaceResult.mouthOpenRatio | 每次人脸检测 | `0` |
| `mouthStatus` | MouthDetector | 每次嘴部检测 | `.closed` |

---

## 问题二：张开五指（OPEN_PALM）→ 显示桌面无反应

### 事件链

```
用户张开五指 → HandPoseDetector 检测到手 → GestureAnalyzer 输出 .openPalm 事件
  → DetectionPipeline.onGesture 触发
  → ContentView 读取 ConfigManager 配置映射
  → 匹配到 .systemCommand / "SHOW_DESKTOP"
  → KeyboardController.executeSystemCommand(.showDesktop) 被调用
  → 函数内 switch case .showDesktop: break // ❌ 空操作
  → 没有任何效果
```

### 根因分析

1. **`KeyboardController.executeSystemCommand(.showDesktop)` 为空实现**（第 51-53 行）：`case .showDesktop: break`。
2. **`GestureMappingView` 使用独立本地状态**，不读写 `ConfigManager`，但这是 UI 问题，不影响现有映射执行（因为 `ContentView` 中 `ConfigManager.shared.currentConfig.gestureMapping` 的默认映射已有 OPEN_PALM → SHOW_DESKTOP）。

### 修复方案

**实现 `KeyboardController.executeSystemCommand(.showDesktop)`**

macOS 显示桌面的快捷键：
- F11（keycode `0x67` = 103）— 传统 Show Desktop
- 但 macOS 中需要确保系统快捷键未被禁用

需要确认：F11 在系统偏好设置 > 键盘 > 键盘快捷键 > Mission Control 中，"显示桌面"默认是 F11。但更可靠的方式是使用 Accessibility API（NXSystemKeys）或直接发送 CGEvent 模拟 F11。

**方案选择：**
直接用 `sendKeyCombo(0x67, flags: [])` （F11 无修饰键），这是默认的 Show Desktop 快捷键。

### 验证方法

```
1. 确认 ConfigManager 默认映射中 OPEN_PALM → .systemCommand / "SHOW_DESKTOP"
2. 张开五指 → 查看 EventLogger 日志确认 .openPalm 事件正确触发
3. 确认 executeSystemCommand(.showDesktop) 被执行
4. 检查桌面是否显示
```

---

## 问题三：摄像头画面中标识识别点位（手部 21 点 + 面部 76 点）

### 事件链

```
摄像头画面显示 → 用户期望看到手部/面部识别点位叠加
  → 当前 CameraPreviewView 只显示原始 AVCaptureSession
  → 无任何叠加层
```

### 需求细节

- 在摄像头画面上叠加显示识别点位
- **手部**：21 个关键点（Vision HandPose 的 21 个关节）
- **面部**：76 个特征点（Vision FaceLandmarks 的 76 点面部星座）
- **颜色逻辑**：
  - 正常状态：识别点位为 **绿色**（`NSColor.green`）
  - 命令触发时：识别点位变为 **红色**（`NSColor.red`），持续 **1 秒** 后恢复绿色
- 点位位置需要从归一化坐标（0~1）映射到摄像头画面实际坐标

### 实现方案

**A. 新增 OverlayView（NSViewRepresentable）**
- 叠加在 `CameraPreviewView` 之上（ZStack）
- 使用 `NSView` 的 `draw(_:)` 方法绘制圆形标注点
- 接受手部关键点和面部特征点数据作为输入
- 接受 `isCommandActive: Bool` 状态控制颜色

**B. 数据链路改造**
- `DetectionPipeline` 需要将 `HandPoseResult` 和 `FaceResult` 暴露给上层
- 新增 `onHandResult: ((HandPoseResult) -> Void)?` 和 `onFaceResult: ((FaceResult) -> Void)?` 闭包
- `ContentView` 中将检测结果传递给 `CameraOverlayView`

**C. 颜色切换逻辑**
- 在 `ContentView` 中监听手势事件，当非 `.none` 非重复手势被触发时
- 设置 `commandTriggeredAt = Date()` 
- OverlayView 根据 `Date().timeIntervalSince(commandTriggeredAt) < 1.0` 判断颜色

### 字段级别

| 新数据结构 | 类型 | 说明 |
|---|---|---|
| `handKeypoints` | `[CGPoint]` | 归一化坐标 (0~1)，手部 21 点 |
| `faceKeypoints` | `[CGPoint]` | 归一化坐标 (0~1)，面部 76 点 |
| `isCommandActive` | `Bool` | 命令触发后 1 秒内为 true |

---

## 交叉依赖分析

| 问题 | 前置依赖 | 是否阻塞其他 |
|---|---|---|
| 1（状态同步） | 无 | 否（独立改动） |
| 1（布局溢出） | 无 | 否（独立改动） |
| 2（显示桌面） | 无 | 否（独立改动，单文件） |
| 3（点位标识） | 需要 DetectionPipeline 新增闭包 | 不影响 1、2 |

三个问题可以并行开发，不互相阻塞。

---

## 数据源索引

| 文件 | 行号 | 相关 |
|---|---|---|
| `ContentView.swift`（在 MotionControlApp.swift 中）| L22-L78 | 全部三个问题的联动逻辑 |
| `StatusPanelView.swift` | L1-L41 | 问题一 UI |
| `SystemState.swift` | L1-L35 | 问题一 数据结构 |
| `DetectionPipeline.swift` | L1-L97 | 问题三 数据出口改造 |
| `KeyboardController.swift` | L42-L72 | 问题二 空实现 |
| `GestureConfig.swift` | L184 | 问题二 OPEN_PALM → SHOW_DESKTOP 映射 |
| `CameraPreviewView.swift` | L1-L25 | 问题三 叠加层嵌入点 |
| `HandPoseDetector.swift` | L16-L123 | 问题三 HandPoseResult 有全部 21 点 |
| `FaceMeshDetector.swift` | L11-L59 | 问题三 FaceResult 有面部特征点 |
