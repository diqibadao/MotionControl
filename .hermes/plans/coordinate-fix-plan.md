# MotionControl 坐标修复实施计划

**目标**：修复坐标偏差（配置不生效 + x 镜像错误 + 骨骼连线条件）

---

### Task 1: CameraService configureSession 改为同步

**Objective:** `configureSession()` 内部用 `sessionQueue.sync` 代替 `async`，确保配置在 `start()` 中同步完成

**Files:**
- Modify: `Sources/MotionControl/Camera/CameraService.swift`

**改动：**
```swift
// 改前
private func configureSession() {
    sessionQueue.async { [weak self] in
        guard let self = self else { return }
        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }
        self.session.sessionPreset = .vga640x480
        // ...
        self.isConfigured = true
    }
}

// 改后
private func configureSession() {
    sessionQueue.sync { [weak self] in
        guard let self = self else { return }
        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }
        self.session.sessionPreset = .vga640x480
        // ...
        self.isConfigured = true
    }
}
```

**验证：** `swift build` 无错误

---

### Task 2: CameraOverlayView 坐标修正 + 骨骼连线条件放宽

**Objective:** 去掉 x 镜像，只保留 y 翻转；骨骼连线条件从 >= 20 点改为 >= 2 点

**Files:**
- Modify: `Sources/MotionControl/Views/CameraOverlayView.swift`

**改动1：** `visionPointToView` 中 x 不镜像
```swift
// 改前
let x = (1.0 - point.x) * videoRect.width + videoRect.origin.x
// 改后
let x = point.x * videoRect.width + videoRect.origin.x
```

**改动2：** 骨骼连线条件放宽
```swift
// 改前
if handKeypoints.count >= 20 {
// 改后
if handKeypoints.count >= 2 {
```

**验证：** `swift build` 无错误

---

## 验证命令

```bash
cd ~/Desktop/vibe项目/MotionControl
swift build
# 运行后目测点位是否吻合
```
