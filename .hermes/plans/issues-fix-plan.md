# MotionControl 三个问题修复实施计划

> 需求文档: `.hermes/plans/issues-fix-requirements.md`
> 项目路径: ~/Desktop/vibe项目/MotionControl/

**目标**：修复实时状态不显示/布局溢出、张开五指显示桌面无反应、摄像头画面标识识别点位

**架构变更**：
1. DetectionPipeline 新增手/脸结果闭包（onHandResult/onFaceResult）用于数据分发
2. StatusPanelView 加 ScrollView 防溢出
3. 新增 CameraOverlayView 叠加层绘制检测点位
4. ContentView 统一作为状态同步中枢

**Tech Stack**: Swift, SwiftUI (macOS), Vision, AVFoundation

---

## Phase 1: 修复"显示桌面"无反应

### Task 1.1: 实现 KeyboardController.showDesktop

**Objective:** 将 `executeSystemCommand(.showDesktop)` 的空实现改为 F11 快捷键模拟

**Files:**
- Modify: `Sources/MotionControl/Control/KeyboardController.swift:51-53`

**改动内容：**
将 `case .showDesktop: break` 改为：
```swift
case .showDesktop:
    sendKeyCombo(0x67, flags: []) // F11 = 显示桌面
```

**验证方法：**
1. `swift build` 无编译错误
2. 运行 App，张开五指，桌面应弹出

---

## Phase 2: 修复状态面板布局溢出

### Task 2.1: StatusPanelView 添加 ScrollView

**Objective:** 当状态项超出窗口高度时能滚动查看

**Files:**
- Modify: `Sources/MotionControl/Views/StatusPanelView.swift`

**改动内容：**
StatusPanelView 的 body 用 ScrollView 包裹现有 VStack，并设置 .frame(maxHeight: 300) 固定最大高度

**验证方法：**
1. `swift build` 无错误
2. 运行后缩小窗口高度，状态面板应可滚动

---

## Phase 3: 状态数据实时同步

### Task 3.1: CameraService 添加 FPS 统计

**Objective:** 计算并暴露实时 FPS 值

**Files:**
- Modify: `Sources/MotionControl/Camera/CameraService.swift`

**改动内容：**
在 CameraService 中添加：
```swift
// 新增属性
var onFPSUpdate: ((Double, Int) -> Void)?  // (fps, frameCount)
private var frameTimestamps: [Date] = []
```

在 `captureOutput(_:didOutput:from:)` 方法开头追加 FPS 计算：
```swift
// FPS 计算
let now = Date()
frameTimestamps.append(now)
if frameTimestamps.count > 10 { frameTimestamps.removeFirst() }
if frameTimestamps.count >= 2 {
    let interval = now.timeIntervalSince(frameTimestamps.first!)
    if interval > 0 {
        let fps = Double(frameTimestamps.count - 1) / interval
        onFPSUpdate?(fps, frameTimestamps.count)
    }
}
```

**验证方法：**
1. `swift build` 无错误
2. 运行后 FPS 应显示实时数值

---

### Task 3.2: ContentView 中建立状态同步链路

**Objective:** 将 DetectionPipeline 的各类事件回调连接到 SystemState

**Files:**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift`（ContentView）

**改动内容：**
在 ContentView.onAppear 中补充以下状态同步逻辑：

1. `detectionPipeline.onGesture` 回调中追加：
```swift
state.currentGesture = event.gestureType.displayName
state.gestureConfidence = Float(event.confidence)
state.handPosition = event.handPosition
state.handDetected = event.gestureType != .none
```

2. `detectionPipeline.onMouthEvent` 回调中追加：
```swift
state.mouthStatus = event.status
state.mouthOpenRatio = event.openRatio
```

3. `detectionPipeline.onGaze` 回调中追加：
```swift
state.gazeActive = true
state.gazePosition = gazeResult.point
```

4. `cameraService.onFPSUpdate` 回调中：
```swift
state.currentFPS = fps
state.frameCount = frameCount
```

**验证方法：**
1. `swift build` 无错误
2. 运行后状态面板实时更新（手势、置信度、嘴型、注视等）

---

## Phase 4: 摄像头画面标识识别点位

### Task 4.1: DetectionPipeline 暴露手/脸结果闭包

**Objective:** 新增 onHandResult / onFaceResult 闭包，让上层能拿到原始关键点数据

**Files:**
- Modify: `Sources/MotionControl/Detection/DetectionPipeline.swift`

**改动内容：**
在 DetectionPipeline 类属性区新增：
```swift
var onHandResult: ((HandPoseResult) -> Void)?
var onFaceResult: ((FaceResult) -> Void)?
```

在 `didOutputFrame` 的手部检测分支内追加（~L68）：
```swift
DispatchQueue.main.async {
    self.onGesture?(gestureEvent)
    self.onHandResult?(handResult)  // 新增
}
```

在人脸检测分支内追加（~L79）：
```swift
DispatchQueue.main.async {
    self.onMouthEvent?(mouthEvent)
    self.onFaceResult?(faceResult)  // 新增
}
```

**验证方法：**
1. `swift build` 无错误

---

### Task 4.2: 创建 CameraOverlayView

**Objective:** 新增 NSViewRepresentable，在摄像头画面上绘制手部 21 点和面部 76 点

**Files:**
- Create: `Sources/MotionControl/Views/CameraOverlayView.swift`

**完整代码：**
```swift
import SwiftUI
import AppKit

/// 摄像头识别点位叠加层
struct CameraOverlayView: NSViewRepresentable {
    /// 手部关键点（归一化坐标 0~1）
    var handKeypoints: [CGPoint]
    /// 面部关键点（归一化坐标 0~1）
    var faceKeypoints: [CGPoint]
    /// 是否处于命令触发状态（红色 1 秒）
    var isCommandActive: Bool
    
    func makeNSView(context: Context) -> OverlayNSView {
        OverlayNSView()
    }
    
    func updateNSView(_ nsView: OverlayNSView, context: Context) {
        nsView.handKeypoints = handKeypoints
        nsView.faceKeypoints = faceKeypoints
        nsView.isCommandActive = isCommandActive
        nsView.needsDisplay = true
    }
}

class OverlayNSView: NSView {
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let color = isCommandActive 
            ? NSColor.red.withAlphaComponent(0.9) 
            : NSColor.green.withAlphaComponent(0.8)
        
        // 绘制手部点（半径 4）
        for point in handKeypoints {
            let px = point.x * bounds.width
            let py = point.y * bounds.height
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: px - 3, y: py - 3, width: 6, height: 6))
        }
        
        // 绘制面部点（半径 2，略小以区分）
        let faceColor = isCommandActive 
            ? NSColor.red.withAlphaComponent(0.9) 
            : NSColor.green.withAlphaComponent(0.6)
        for point in faceKeypoints {
            let px = point.x * bounds.width
            let py = point.y * bounds.height
            ctx.setFillColor(faceColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: px - 2, y: py - 2, width: 4, height: 4))
        }
    }
}
```

**验证方法：**
1. `swift build` 无错误
2. （运行时）摄像头画面上应出现绿色/红色点位

---

### Task 4.3: 集成 CameraOverlayView 到 ContentView

**Objective:** 在 ContentView 中用 ZStack 叠加 CameraOverlayView，并处理颜色切换逻辑

**Files:**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift`（ContentView）

**改动内容：**

1. 在 ContentView 中新增状态属性：
```swift
@State private var handKeypoints: [CGPoint] = []
@State private var faceKeypoints: [CGPoint] = []
@State private var commandTriggeredAt: Date = .distantPast
private let overlayTimer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()
```

2. 摄像头区域改为 ZStack：
```swift
ZStack(alignment: .topLeading) {
    CameraPreviewView(session: cameraService.cameraSession)
        .frame(height: 360)
    CameraOverlayView(
        handKeypoints: handKeypoints,
        faceKeypoints: faceKeypoints,
        isCommandActive: Date().timeIntervalSince(commandTriggeredAt) < 1.0
    )
}
.frame(height: 360)
.onReceive(overlayTimer) { _ in
    // Timer 驱动刷新，让 isCommandActive 随 Date() 变化
}
```

3. 在 onAppear 中补充数据接收：
```swift
detectionPipeline.onHandResult = { handResult in
    var points: [CGPoint] = []
    if let p = handResult.wrist { points.append(p) }
    if let p = handResult.thumbTip { points.append(p) }
    if let p = handResult.thumbIP { points.append(p) }
    if let p = handResult.thumbMP { points.append(p) }
    if let p = handResult.indexTip { points.append(p) }
    if let p = handResult.indexDIP { points.append(p) }
    if let p = handResult.indexPIP { points.append(p) }
    if let p = handResult.indexMCP { points.append(p) }
    if let p = handResult.middleTip { points.append(p) }
    if let p = handResult.middleDIP { points.append(p) }
    if let p = handResult.middlePIP { points.append(p) }
    if let p = handResult.middleMCP { points.append(p) }
    if let p = handResult.ringTip { points.append(p) }
    if let p = handResult.ringDIP { points.append(p) }
    if let p = handResult.ringPIP { points.append(p) }
    if let p = handResult.ringMCP { points.append(p) }
    if let p = handResult.littleTip { points.append(p) }
    if let p = handResult.littleDIP { points.append(p) }
    if let p = handResult.littlePIP { points.append(p) }
    if let p = handResult.littleMCP { points.append(p) }
    handKeypoints = points
}

detectionPipeline.onFaceResult = { faceResult in
    var points: [CGPoint] = []
    if let contour = faceResult.faceContour { points.append(contentsOf: contour) }
    if let leftEye = faceResult.leftEye { points.append(contentsOf: leftEye) }
    if let rightEye = faceResult.rightEye { points.append(contentsOf: rightEye) }
    if let leftPupil = faceResult.leftPupil { points.append(leftPupil) }
    if let rightPupil = faceResult.rightPupil { points.append(rightPupil) }
    if let outerLips = faceResult.outerLips { points.append(contentsOf: outerLips) }
    if let innerLips = faceResult.innerLips { points.append(contentsOf: innerLips) }
    faceKeypoints = points
}
```

4. 在手势事件触发时记录时间戳（颜色切换用）：
在原有的 `onGesture` 回调末尾追加：
```swift
if event.gestureType != .none && !event.isRepeat {
    commandTriggeredAt = Date()
}
```

**验证方法：**
1. `swift build` 无错误
2. 运行后摄像头画面上出现绿色识别点位
3. 做出一个手势动作 -> 点位变红约 1 秒后恢复绿色

---

## 执行顺序

| 步骤 | Task | 依赖 | 文件 |
|------|------|------|------|
| 1 | T1.1: 修复 showDesktop | 无 | KeyboardController.swift |
| 2 | T2.1: StatusPanelView 加 ScrollView | 无 | StatusPanelView.swift |
| 3 | T3.1: CameraService FPS | 无 | CameraService.swift |
| 4 | T3.2: 状态同步链路 | T3.1 | MotionControlApp.swift |
| 5 | T4.1: DetectionPipeline 新闭包 | 无 | DetectionPipeline.swift |
| 6 | T4.2: CameraOverlayView | 无 | CameraOverlayView.swift (新建) |
| 7 | T4.3: 集成 Overlay 到 ContentView | T3.2, T4.1, T4.2 | MotionControlApp.swift |

T1、T2、T3、T5、T6 可并行。
T4 需 T3。
T7 需 T4、T5、T6。

---

## 验证命令

每次构建验证：
```bash
cd ~/Desktop/vibe项目/MotionControl
swift build
```

运行时验证（每个 Task 完成后手动跑一次）：
1. F11 显示桌面
2. 缩放窗口看状态面板是否可滚动
3. 观察 FPS 是否实时更新
4. 观察摄像头画面是否有绿色/红色点位
