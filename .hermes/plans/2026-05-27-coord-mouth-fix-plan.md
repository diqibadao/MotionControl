# MotionControl 坐标映射与嘴部检测修复 — 实施计划

> **执行方式：** Aider 逐任务执行，每完成一个任务编译+确认
> **前置文档：** `.hermes/plans/2026-05-27-coord-mouth-fix-events.md`

**目标：** 修复 4 个问题：手部标点偏右、嘴标点扩散全屏、嘴一直 open、手/脸离开后残留标点

**涉及文件：** CameraPreviewView.swift / FaceMeshDetector.swift / MouthDetector.swift / DetectionPipeline.swift / MotionControlApp.swift

**验证方式：** swift build + 运行看画面/日志

---

## 任务清单

### Task 1: 修复手部标点偏右（去镜像）

**Objective:** 去掉 `visionPointToView` 中多余的 x 镜像

**文件：**
- Modify: `Sources/MotionControl/Views/CameraPreviewView.swift:114`

**修改内容：**

第 114 行，将：
```swift
let x = (1.0 - point.x) * videoRect.width + videoRect.origin.x
```
改为：
```swift
let x = point.x * videoRect.width + videoRect.origin.x
```

**验证：**
1. `cd {project} && swift build` → Build complete!
2. 运行后手放在画面中央 → 标点应在画面中央区域

**提交：**
```bash
git add Sources/MotionControl/Views/CameraPreviewView.swift
git commit -m "fix: 去除 visionPointToView 的 x 镜像（CALayer 坐标系与 Vision 一致，无需镜像）"
```

---

### Task 2: 修复面部标点扩散全屏（FaceMeshDetector）

**Objective:** 将 landmarks 的人脸框相对坐标转为图像绝对坐标

**文件：**
- Modify: `Sources/MotionControl/Detection/FaceMeshDetector.swift`

**修改点1：** 新增 `landmarkPoints` 辅助方法（放在 `faceResult(from:)` 之上）

```swift
    /// 将人脸特征点从人脸框相对坐标转为图像绝对坐标
    /// - Parameters:
    ///   - region: Vision 人脸特征区域
    ///   - bbox: 人脸检测框（图像归一化坐标）
    /// - Returns: 图像绝对坐标数组，若 region 为空则返回 nil
    private static func landmarkPoints(
        from region: VNFaceLandmarkRegion2D?,
        in bbox: CGRect
    ) -> [CGPoint]? {
        guard let region = region, region.pointCount > 0 else { return nil }
        return region.normalizedPoints.map { pt in
            CGPoint(
                x: bbox.origin.x + pt.x * bbox.size.width,
                y: bbox.origin.y + pt.y * bbox.size.height
            )
        }
    }
```

**修改点2：** 修改 `faceResult(from:)` 方法第 133-145 行

当前：
```swift
let leftEye = landmarks?.leftEye?.normalizedPoints
let rightEye = landmarks?.rightEye?.normalizedPoints
let leftPupil = landmarks?.leftPupil?.normalizedPoints.first
let rightPupil = landmarks?.rightPupil?.normalizedPoints.first
let outerLips = landmarks?.outerLips?.normalizedPoints
let innerLips = landmarks?.innerLips?.normalizedPoints
let faceContour = landmarks?.faceContour?.normalizedPoints
```

改为（在方法开头获取 bbox，然后用 landmarkPoints 转换）：
```swift
let bbox = observation.boundingBox
let leftEye = Self.landmarkPoints(from: landmarks?.leftEye, in: bbox)
let rightEye = Self.landmarkPoints(from: landmarks?.rightEye, in: bbox)
let leftPupil = Self.landmarkPoints(from: landmarks?.leftPupil, in: bbox)?.first
let rightPupil = Self.landmarkPoints(from: landmarks?.rightPupil, in: bbox)?.first
let outerLips = Self.landmarkPoints(from: landmarks?.outerLips, in: bbox)
let innerLips = Self.landmarkPoints(from: landmarks?.innerLips, in: bbox)
let faceContour = Self.landmarkPoints(from: landmarks?.faceContour, in: bbox)
```

注意：`leftPupil` 和 `rightPupil` 原来直接取 `.normalizedPoints.first`，改为先转再取 first。

**验证：**
1. `cd {project} && swift build` → Build complete!
2. 运行后面部标点只集中在人脸区域，不再扩散全屏

**提交：**
```bash
git add Sources/MotionControl/Detection/FaceMeshDetector.swift
git commit -m "fix: 将面部 landmarks 从人脸框相对坐标转为图像绝对坐标"
```

---

### Task 3: 修复嘴一直 open（MouthDetector）

**Objective:** 用 bounding box 方式计算嘴开合比，不依赖固定索引

**文件：**
- Modify: `Sources/MotionControl/Detection/MouthDetector.swift`

**修改内容：** 替换 `detect(from:)` 方法中第 53-80 行的开合比计算逻辑

当前代码（53-80行）：
```swift
let ratio: Float
if let points = face.outerLips, points.count >= 8 {
    let leftCorner = points[0]
    let rightCorner = points[4]
    let width = hypot(rightCorner.x - leftCorner.x, rightCorner.y - leftCorner.y)
    guard width > 0 else { ... }
    let upperLip = points[2]
    let lowerLip = points[6]
    let height = hypot(lowerLip.x - upperLip.x, lowerLip.y - upperLip.y)
    ratio = Float(height / width)
} else {
    ratio = 0.0
}
```

改为：
```swift
let ratio: Float
if let points = face.outerLips, points.count >= 4 {
    // 用外嘴唇的 bounding box 计算 height/width，不依赖固定索引
    var minX = CGFloat.greatestFiniteMagnitude
    var maxX = CGFloat.leastNormalMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxY = CGFloat.leastNormalMagnitude
    for point in points {
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
    }
    let width = maxX - minX
    let height = maxY - minY
    guard width > 0 else {
        let logInput = "mouth_detect ratio=0.0"
        let logOutput = "status=CLOSED confirmed=CLOSED"
        EventLogger.log(event: "mouth_detect", frame: nil, input: logInput, output: logOutput, duration: nil)
        return MouthEvent(status: .closed, confirmedStatus: .closed, ratio: 0.0, justOpened: false, justClosed: false)
    }
    ratio = Float(height / width)
} else {
    ratio = 0.0
}
```

注意：去掉旧的 guard width>0 分支（已合并到新逻辑内），保持其余代码不变（滞回判断、防抖、边缘触发逻辑不变）。

**验证：**
1. `cd {project} && swift build` → Build complete!
2. 运行后嘴闭合时 → 日志显示 status=CLOSED
3. 嘴张开时 → 日志显示 status=OPEN (ratio > 0.6)

**提交：**
```bash
git add Sources/MotionControl/Detection/MouthDetector.swift
git commit -m "fix: 用 bounding box 计算嘴开合比，修复索引错误导致一直 OPEN"
```

---

### Task 4: 修复手/脸离开画面后残留标点（DetectionPipeline + ContentView）

**Objective:** 检测不到手/脸时清空标点数组

**文件：**
- Modify: `Sources/MotionControl/Detection/DetectionPipeline.swift`
- Modify: `Sources/MotionControl/App/MotionControlApp.swift`

**修改点1 — DetectionPipeline.swift：** 将闭包签名改为接收可选值

第 26-27 行：
```swift
var onHandResult: ((HandPoseResult) -> Void)?
var onFaceResult: ((FaceResult) -> Void)?
```
改为：
```swift
var onHandResult: ((HandPoseResult?) -> Void)?
var onFaceResult: ((FaceResult?) -> Void)?
```

**修改点2 — DetectionPipeline.swift：** 在检测失败时发送 nil

第 63-71 行（手部检测），在 `if let handResult` 的 else 分支添加：
```swift
if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
    self.lastHand = handResult
    let gestureEvent = self.gestureAnalyzer.analyze(handResult)
    DispatchQueue.main.async {
        self.onGesture?(gestureEvent)
        self.onHandResult?(handResult)
    }
} else {
    DispatchQueue.main.async {
        self.onHandResult?(nil)
    }
}
```

第 74-84 行（人脸检测），添加 else 分支：
```swift
if let faceResults = self.faceMeshDetector.detect(pixelBuffer: pixelBuffer),
   let faceResult = faceResults.first {
    self.lastFace = faceResult
    let mouthEvent = self.mouthDetector.detect(from: faceResult)
    DispatchQueue.main.async {
        self.onMouthEvent?(mouthEvent)
        self.onFaceResult?(faceResult)
    }
    self.didOutputFace(faceResult)
} else {
    DispatchQueue.main.async {
        self.onFaceResult?(nil)
    }
}
```

**修改点3 — MotionControlApp.swift（ContentView）：** 处理 nil 时清空数组

第 100-122 行的 `onHandResult`，在开头添加 guard：
```swift
detectionPipeline.onHandResult = { handResult in
    guard let handResult = handResult else {
        handKeypoints = []
        return
    }
    // ... 下面的原有代码不变
}
```

第 124-133 行的 `onFaceResult`，同样添加 guard：
```swift
detectionPipeline.onFaceResult = { faceResult in
    guard let faceResult = faceResult else {
        faceKeypoints = []
        return
    }
    // ... 下面的原有代码不变
}
```

**验证：**
1. `cd {project} && swift build` → Build complete!
2. 运行后手在画面中 → 标点正常
3. 手移出画面 → 标点立即消失（1-2 帧内）
4. 脸移出画面 → 面部标点立即消失

**提交：**
```bash
git add Sources/MotionControl/Detection/DetectionPipeline.swift Sources/MotionControl/App/MotionControlApp.swift
git commit -m "fix: 检测不到手/脸时清空标点，防止残留"
```

---

## 执行顺序

按 Task 1 → 2 → 3 → 4 顺序执行。每个 Task 完成后：
1. `swift build` 确认编译通过
2. 运行软件确认效果
3. 提交 git
4. 继续下一个

## 回滚策略

如果某个 Task 导致问题：
```bash
git log --oneline -5  # 找到最近的 commit hash
git reset --hard HEAD~1  # 回退一个 commit
```
