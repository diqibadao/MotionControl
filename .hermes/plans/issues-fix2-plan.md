# MotionControl 修复二实施计划

**目标**：修复识别点位坐标不准 + 实时状态移到摄像头画面左上角

**架构**：
1. CameraPreviewView videoGravity 从 .resizeAspectFill 改为 .resizeAspect
2. CameraOverlayView 计算实际画面矩形 + y 轴翻转 + 偏移修正
3. MotionControlApp.swift ZStack 添加状态文字叠加层，去掉 StatusPanelView

---

### Task 1: CameraPreviewView 改 videoGravity

**Objective:** 从 .resizeAspectFill（裁剪）改为 .resizeAspect（完整显示+黑边）

**Files:**
- Modify: `Sources/MotionControl/Views/CameraPreviewView.swift:14`

**改动：**
```swift
// 改前
previewLayer.videoGravity = .resizeAspectFill
// 改后
previewLayer.videoGravity = .resizeAspect
```

**验证：** `swift build` 无错误

---

### Task 2: CameraOverlayView 修复坐标映射

**Objective:** 计算画面实际矩形位置，做 y 轴翻转

**Files:**
- Modify: `Sources/MotionControl/Views/CameraOverlayView.swift:32-70`

**改动：**
在 `draw(_:)` 方法中，计算视频画面在视图中的实际矩形：
```swift
let cameraAspect: CGFloat = 640.0 / 480.0  // 4:3
let viewAspect = bounds.width / bounds.height
var videoRect: CGRect
if viewAspect > cameraAspect {
    // 视图更宽 → 上下黑边
    let videoHeight = bounds.height
    let videoWidth = videoHeight * cameraAspect
    let xOffset = (bounds.width - videoWidth) / 2
    videoRect = CGRect(x: xOffset, y: 0, width: videoWidth, height: videoHeight)
} else {
    // 视图更高 → 左右黑边
    let videoWidth = bounds.width
    let videoHeight = videoWidth / cameraAspect
    let yOffset = (bounds.height - videoHeight) / 2
    videoRect = CGRect(x: 0, y: yOffset, width: videoWidth, height: videoHeight)
}
```

然后绘点时用这个转换函数：
```swift
func visionPointToView(_ point: CGPoint, videoRect: CGRect) -> CGPoint {
    // Vision: (0,0)=左下, (1,1)=右上 → NSView: (0,0)=左上, (width,height)=右下
    let x = point.x * videoRect.width + videoRect.origin.x
    let y = (1.0 - point.y) * videoRect.height + videoRect.origin.y
    return CGPoint(x: x, y: y)
}
```

将 faceKeypoints 和 handKeypoints 的绘制循环中的坐标计算替换为 visionPointToView。

注意：`NeedsDisplay` 已在 updateNSView 中触发。

**验证：** `swift build` 无错误

---

### Task 3: 状态文字叠加到画面左上角 + 去掉独立 StatusPanelView

**Objective:** 在 ZStack 中添加半透明背景的文字层，去掉下方的 StatusPanelView

**Files:**
- Modify: `Sources/MotionControl/App/MotionControlApp.swift:27-38`

**改动：**
在 ZStack 中 CameraOverlayView 之后、关闭 ZStack 之前，添加：
```swift
// 状态信息叠加层（左上角）
VStack(alignment: .leading, spacing: 2) {
    Text(String(format: "FPS: %.1f", state.currentFPS))
    Text("手势: \(state.currentGesture)  \(String(format: "%.2f", state.gestureConfidence))")
    Text("嘴型: \(state.mouthStatus == .open ? "open" : state.mouthStatus == .closed ? "closed" : "unknown")")
}
.font(.caption)
.foregroundColor(.white)
.padding(6)
.background(Color.black.opacity(0.5))
.cornerRadius(4)
.padding(8)
```

同时移除 VStack 中 `StatusPanelView(state: state)` 这一行（L37）。

**验证：** `swift build` 无错误
