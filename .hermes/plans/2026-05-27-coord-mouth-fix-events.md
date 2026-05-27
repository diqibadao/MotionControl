# MotionControl 坐标映射与嘴部检测修复 — 需求文档

> 生成时间: 2026-05-27 22:50
> 项目路径: ~/Desktop/vibe项目/MotionControl/

---

## 问题总览

| 问题 | 现象 | 严重程度 |
|------|------|---------|
| P1 - 手部标点偏右 | 手在画面中央，但标点全部堆在画面最右边 | 高 |
| P2 - 嘴标点扩散全屏 | 嘴部标点从人脸区域扩散到整个屏幕 | 高 |
| P3 - 嘴型一直 open | 嘴上闭合着，但始终显示 open | 高 |

---

## 问题 P1：手部标点偏右

### 事件链

```
用户抬手在摄像头前 → DetectionPipeline 检测到手
  → HandPoseDetector 返回 HandPoseResult（Vision 归一化坐标）
  → ContentView.onHandResult 提取 21 个关键点到 handKeypoints
  → CameraPreviewView 的 OverlayPreviewNSView 绘制手部骨骼+关键点
  → visionPointToView 将归一化坐标转为视图坐标
    → x = (1.0 - point.x) * videoRect.width + videoRect.origin.x   // ❌ 镜像
    → y = point.y * videoRect.height + videoRect.origin.y
  → 绘制结果：标点显示在画面右侧，不对齐实际手部位置
```

### 根因分析

**坐标系分析：**
- `CALayerDelegate.draw(_:in:)` 的 CGContext：`isFlipped=false`，CTM 身份矩阵
  → (0,0) = 左下角，x 向右，y 向上
- Vision 归一化坐标：`VNPoint.location` → (0,0) = 左下角，x 向右，y 向上
- **两个坐标系一致**，不需要 x 镜像也不需要 y 翻转

**前置摄像头镜像问题：**
- 前置摄像头原始画面是镜像的
- `AVCaptureVideoPreviewLayer` 会自动镜像显示
- Vision 处理的是**原始画面**数据（未镜像），x=0 对应画面的左侧
- PreviewLayer 显示**镜像后**的画面，左侧变右侧
- **但** CALayer 叠加层是直接在 previewLayer 上方绘制的，预览层已经做了一次镜像，所以叠加层的坐标应该直接用 Vision 的原始坐标，不需要额外镜像

### 修复方案

`CameraPreviewView.swift` — `visionPointToView` 函数第 114 行：

当前：
```swift
let x = (1.0 - point.x) * videoRect.width + videoRect.origin.x  // ❌ 镜像
```

改为：
```swift
let x = point.x * videoRect.width + videoRect.origin.x  // ✅ 不镜像
```

### 涉及文件

`Sources/MotionControl/Views/CameraPreviewView.swift` — 第 114 行

### 验证方法

1. 手放在画面中央 → 标点应在画面中央
2. 查看 OVERLAY-DRAW 日志：pt=(0.5, 0.5) → display 应在画面中心区域
3. 截图确认叠加层对齐

---

## 问题 P2：嘴标点扩散到全屏

### 事件链

```
摄像头捕捉到人脸 → DetectionPipeline.didOutputFrame
  → FaceMeshDetector.detect(pixelBuffer:) 返回 [FaceResult]
  → FaceResult 包含 outerLips/faceContour/leftEye 等特征点集
  → faceResult(from:) 中读取 landmarks?.XXX?.normalizedPoints
    → normalizedPoints 是相对人脸框 (boundingBox) 的坐标 ❌
  → ContentView.onFaceResult 收集所有特征点
    → 直接传入 CameraPreviewView 作为 faceKeypoints
  → OverlayPreviewNSView 绘制面部标点
    → 用 visionPointToView 将坐标映射到整个画面
    → 归一化坐标 (0~1) → 被映射到整个画面宽高
    → 本应只覆盖人脸区域，实际扩散到全屏
```

### 根因分析

**关键误区：** Vision 的 `VNFaceLandmarkRegion2D.normalizedPoints` 是**相对于人脸检测框 (boundingBox)** 的归一化坐标，不是**相对于图像**的归一化坐标。

- `normalizedPoints` 范围：(0,0) 到 (1,1)，在人脸框内
- 需要结合 `observation.boundingBox`（也是图像归一化坐标，0~1）将点映射到图像绝对坐标
- 公式：`absX = bbox.origin.x + normalizedX * bbox.size.width`
- `absY` 同理（注意 Vision 的 y 轴是左下角→右上角）

**当前代码直接使用了 normalizedPoints，造成：**
- 面部轮廓点（约在 bbox 边缘）→ 映射到画面边缘 → 扩散到全屏
- 嘴唇点（在 bbox 内部）→ 映射到画面偏位置 → 但跟人脸实际位置无关

### 修复方案

`FaceMeshDetector.swift` — `faceResult(from:)` 方法中，需要用 `observation.boundingBox` 将 landmarks 的相对坐标转为图像绝对坐标。

新增辅助函数：

```swift
/// 将归一化坐标（相对于人脸框）转为图像绝对坐标
private static func landmarkPoints(
    _ region: VNFaceLandmarkRegion2D?, 
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

调用方式变化（在 faceResult 中）：
```swift
let bbox = observation.boundingBox  // 图像归一化坐标 (0~1)
let leftEye = landmarkPoints(landmarks?.leftEye, in: bbox)
// ... 依次对所有特征点做相同处理
```

### 涉及文件

`Sources/MotionControl/Detection/FaceMeshDetector.swift` — 第 122-159 行（faceResult 方法）

### 验证方法

1. 面部标点只集中在人脸区域
2. 背景不再有绿色噪点
3. 面部轮廓点沿人脸轮廓分布

---

## 问题 P3：嘴型一直识别为 open

### 事件链

```
摄像头捕捉到人脸 → DetectionPipeline.didOutputFrame
  → faceMeshDetector.detect() 返回 FaceResult
  → mouthDetector.detect(from:) 计算嘴部开合
  → 从 outerLips 提取 8 个点
    → points[0] = 左嘴角（假设）
    → points[4] = 右嘴角（假设）
    → points[2] = 上嘴唇中点（假设）
    → points[6] = 下嘴唇中点（假设）
  → width = |points[0] - points[4]|  // ❌ 错误计算
  → height = |points[2] - points[6]| // ❌ 错误计算
  → ratio = height / width
  → 日志显示 ratio=1.047 >> openThreshold(0.6)
  → 永远判定为 OPEN
```

### 根因分析

**Vision 的 outerLips 点排列顺序：**

Vision 的外嘴唇点（对于 12 点模型）是从**右嘴角**开始，沿上唇→左嘴角→下唇→右嘴角按顺/逆时针排列：

| 索引 | 位置 |
|------|------|
| 0 | 右嘴角 |
| 1 | 上唇右侧 1/4 |
| 2 | 上唇中央右侧 |
| 3 | 上唇正中央（人中下方） |
| 4 | 上唇中央左侧 |
| 5 | 上唇左侧 1/4 |
| 6 | 左嘴角 |
| 7 | 下唇左侧 1/4 |
| 8 | 下唇中央左侧 |
| 9 | 下唇正中央 |
| 10 | 下唇中央右侧 |
| 11 | 下唇右侧 1/4 |

**MouthDetector 的错误假设：**
- points[0] = 左嘴角 → 实际是**右嘴角**
- points[4] = 右嘴角 → 实际是**上唇中央左**
- points[2] = 上唇中点 → 实际是**上唇中央右**
- points[6] = 下唇中点 → 实际是**左嘴角**

**后果：**
- width = |points[0] - points[4]| = 右嘴角到上唇中央左 = 近距离
- height = |points[2] - points[6]| = 上唇中央右到左嘴角 = 横向跨唇距离
- ratio = 横向大距离 / 纵向小距离 ≈ 1.0+

### 修复方案

`MouthDetector.swift` — 用正确索引计算开合比：

```swift
// 对于 12 点嘴唇模型：
let leftCorner = points[6]        // ✅ 左嘴角
let rightCorner = points[0]       // ✅ 右嘴角
let upperLip = points[3]          // ✅ 上嘴唇正中央
let lowerLip = points[9]          // ✅ 下嘴唇正中央
```

或更健壮的方式：直接复用 `FaceResult.mouthOpenRatio` 的 bounding box 方式（不依赖特定索引）。

**推荐方案：** 改成用 bounding box 方式计算 height/width，因为 bounding box 不依赖具体点数，兼容性好。

```swift
// 用外嘴唇的 bounding box 计算 height/width
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
ratio = Float(height / width)
```

### 涉及文件

`Sources/MotionControl/Detection/MouthDetector.swift` — 第 53-77 行

### 验证方法

1. 嘴闭合时 → ratio ≈ 0.0 ~ 0.2 → status = CLOSED
2. 嘴张开时 → ratio > 0.6 → status = OPEN
3. 日志中 ratio 值符合预期

---

---

## 问题 P4：手/脸离开画面后残留标点

### 事件链

```
手移出摄像头范围 → DetectionPipeline.didOutputFrame
  → HandPoseDetector.detect() 返回 nil
  → ❌ 不执行 onHandResult，handKeypoints 保持旧值
  → CameraPreviewView 继续用旧数据绘制 → 残留标点
```

同样逻辑适用于人脸检测：脸移出画面 → faceKeypoints 保持旧值 → 画面残留面部标点。

### 根因分析

`DetectionPipeline.didOutputFrame` 第 63-71 行：

```swift
// 手部检测
if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
    // ... 仅在有结果时通知
}  // ❌ 没有 else 分支，没检测到就不通知
```

`onHandResult` 闭包（在 ContentView 中）只有在检测到手时才被调用，没检测到就**什么都不做**，画面上的点停留在最后检测位置。

### 修复方案

`DetectionPipeline.swift` — 修改 `onHandResult` 和 `onFaceResult` 闭包签名，使其接收可选值：

```swift
// 修改闭包签名
var onHandResult: ((HandPoseResult?) -> Void)?
var onFaceResult: ((FaceResult?) -> Void)?
```

在 `didOutputFrame` 中，无论是否检测到都调用：

```swift
// 手部检测
if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
    // ... 现有逻辑
    DispatchQueue.main.async {
        self.onHandResult?(handResult)
    }
} else {
    DispatchQueue.main.async {
        self.onHandResult?(nil)  // ✅ 通知清空
    }
}
```

`ContentView.swift` — 收到 nil 时清空标点数组：

```swift
detectionPipeline.onHandResult = { handResult in
    guard let handResult = handResult else {
        handKeypoints = []  // ✅ 手离开画面 → 清空标点
        return
    }
    // ... 现有提取关键点逻辑
}
```

同样修改 `onFaceResult` 处理人脸标点清空。

### 涉及文件

- `Sources/MotionControl/Detection/DetectionPipeline.swift` — 第 26-27 行（闭包签名）、第 63-71 行（手部调用）、第 74-84 行（面部调用）
- `Sources/MotionControl/App/MotionControlApp.swift` (ContentView) — 第 100-134 行（闭包实现）

### 验证方法

1. 手放在摄像头前 → 标点显示正常
2. 手移出画面 → 标点立即消失（1-2 帧内）
3. 脸移出画面 → 面部标点立即消失

---

## 交叉依赖分析

| 问题 | 涉及文件 | 是否互相依赖 |
|------|---------|------------|
| P1 - 手部偏右 | CameraPreviewView.swift | 独立 |
| P2 - 嘴标点扩散 | FaceMeshDetector.swift | 独立 |
| P3 - 嘴一直 open | MouthDetector.swift | 独立 |
| P4 - 残留标点 | DetectionPipeline.swift + ContentView.swift | 独立 |

**全部可以独立修复，不互相阻塞。** 但建议按 P1→P2→P3→P4 顺序执行，因为先修好坐标映射和标点范围，再看嘴的逻辑更清晰。

## 数据源索引

| 文件 | 行号 | 问题 |
|------|------|------|
| `Sources/MotionControl/Views/CameraPreviewView.swift` | 114 | P1 - x 镜像 |
| `Sources/MotionControl/Detection/FaceMeshDetector.swift` | 124-158 | P2 - 相对坐标未转绝对 |
| `Sources/MotionControl/Detection/MouthDetector.swift` | 53-77 | P3 - 索引错误 |
| `Sources/MotionControl/Detection/DetectionPipeline.swift` | 26-27, 63-84 | P4 - 检测失败不通知 |
| `Sources/MotionControl/App/MotionControlApp.swift` (ContentView) | 100-134 | P2, P4 - 特征点收集/清空 |
