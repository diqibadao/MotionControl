# MotionControl 坐标修复 + 流程合规需求文档

> 生成时间: 2026-05-27

---

## 当前问题

### 1. CameraService 线程安全修复导致的配置不生效（严重 bug）

**事件链：**
```
用户启动 App → CameraService.start()
  → if !isConfigured { configureSession() }
  → configureSession() 内部 sessionQueue.async { ... }
    → 异步任务还没执行，方法就返回了
  → if !session.isRunning { session.startRunning() }
    → 此时 session 尚未配置（无分辨率、无输入、无输出）
    → session.startRunning() 以默认配置运行
    → 实际分辨率不是 VGA 640×480，可能是 1080p 或更高
  → OverlayNSView 的 videoRect 计算基于 640×480
    → 坐标与实际画面尺寸不匹配 → 点位偏移
```

**根因：** `configureSession()` 改成 `sessionQueue.async` 后，`start()` 方法中的顺序逻辑被破坏。配置还没做完就开始运行了。

**修复方案：**
- 方案 A：`configureSession()` 用 `sessionQueue.sync` 代替 `async`，确保配置同步完成
- 方案 B：保持 async，但 `start()` 也通过回调确认配置完成后再 startRunning
- 推荐方案 A（最简单、最小改动）

### 2. 坐标映射 x 镜像可能不需要

**当前代码：** `visionPointToView` 同时做了 x 镜像和 y 翻转：
```swift
let x = (1.0 - point.x) * ...  // x 镜像
let y = (1.0 - point.y) * ...  // y 翻转
```

**问题：** 根据参考项目 hand-gesture-grab，MediaPipe 用 `flipHorizontal: true` 是因为浏览器 video 标签默认镜像。Vision 框架处理的是原始像素缓冲区，**不需要** x 镜像。如果画面显示镜像，那是 AVCaptureVideoPreviewLayer 自动处理的。

**修复方案：** 去掉 x 镜像，只保留 y 翻转：
```swift
let x = point.x * videoRect.width + videoRect.origin.x  // 不镜像
let y = (1.0 - point.y) * videoRect.height + videoRect.origin.y  // y 翻转
```

### 3. 骨骼连线绘制条件过于严格

**当前代码：** `if handKeypoints.count >= 20 { ... 画骨骼线 }`

**问题：** 当检测到手部但关键点不足 20 个时，不画骨骼线，只画点。用户说"没看到白色线"。

**修复方案：** 放宽条件，只要有至少 2 个点就尝试画连线（缺失的点自动跳过）。

### 4. 上一轮违反开发流程

上一轮修复布局和骨骼线时，跳过了需求文档 → 计划 → 确认的流程，直接调用 Aider 修改。

---

## 改动文件清单

| 文件 | 改动内容 |
|------|---------|
| `CameraService.swift` | `configureSession()` 内用 `sessionQueue.sync` 替代 `async` |
| `CameraOverlayView.swift` | `visionPointToView` 去掉 x 镜像；骨骼连线放宽条件 |

---

## 验证方法

1. `swift build` 零错误
2. 运行后手部/面部点位应与实际画面吻合
3. 做手势时点位变红 1 秒
4. 手部有白色半透明骨骼连线
