# MotionControl 修复二需求文档

> 项目路径: ~/Desktop/vibe项目/MotionControl/

---

## 问题一：实时状态显示位置错误

### 当前状态
状态信息在独立 StatusPanelView 中，位于摄像头画面下方。

### 目标
状态信息叠加在 **摄像头画面左上角**（半透明背景），不再有独立的状态面板。

### 实现方案
1. 在 `ContentView` 的 ZStack 中，在 `CameraPreviewView` 和 `CameraOverlayView` 之上叠加一个半透明文字层
2. 显示内容：FPS、手势名称、置信度、嘴型、注视
3. 字体：`.caption`，半透明黑色背景（`.background(.black.opacity(0.5))`）
4. 位置：ZStack 顶部，左对齐

### 视觉效果
```
┌──────────────────────────┐
│ █ FPS: 29.5              │  ← 半透黑底白字
│ █ 手势: PINCH  0.92      │
│ █ 嘴型: closed           │
│                          │
│    [摄像头画面]           │
│    • • • (识别点位)       │
└──────────────────────────┘
```

---

## 问题二：识别点位坐标不准确

### 根因分析

**坐标系统差异**：
- **Vision 坐标系**：normalizedPoints 中 (0,0) = 左下角, (1,1) = 右上角（图像坐标系，y 轴向上）
- **NSView 坐标系**：(0,0) = 左上角, (width,height) = 右下角（屏幕坐标系，y 轴向下）
- **当前 OverlayNSView 直接 `y = point.y * bounds.height`**，没有做 y 轴翻转，也不考虑画面裁剪

**画面裁剪问题**：
- `CameraPreviewView` 使用 `videoGravity = .resizeAspectFill` → 画面被缩放并裁剪居中
- 摄像头 VGA 640×480（4:3），但预览视图宽高比可能 ≠ 4:3
- 坐标直接乘 bounds.width/height 会落在画面之外的区域

### 修复方案

**方案一（推荐）：改用 `.resizeAspect` + 手动计算画面区域**

1. 将 `videoGravity` 改为 `.resizeAspect`（保留完整画面，黑边填充）
2. 在 `OverlayNSView.draw()` 中计算画面在视图中的实际位置：
   ```
   画面宽高比 = 640/480 = 4:3
   缩放比例 = min(bounds.width / 640, bounds.height / 480)
   画面宽 = 640 * scale, 画面高 = 480 * scale
   偏移 x = (bounds.width - 画面宽) / 2
   偏移 y = (bounds.height - 画面高) / 2
   ```
3. 坐标转换：
   ```
   显示 x = visionX * 画面宽 + 偏移 x
   显示 y = (1.0 - visionY) * 画面高 + 偏移 y  // 翻转 y
   ```

### 字段级别

| 变量 | 类型 | 说明 |
|------|------|------|
| `cameraAspect` | `CGFloat` | 640.0/480.0 = 4:3 |
| `scale` | `CGFloat` | 画面缩放比 |
| `videoRect` | `CGRect` | 画面在视图中的实际矩形 |
| `isFlippedY` | 计算 | visionY → 1.0 - visionY |

### 验证方法
1. 张开手掌 → 点位应准确落在手指尖位置
2. 人脸检测 → 点位应准确落在眼睑、嘴唇、轮廓
3. 不同窗口大小 → 点位始终跟随画面位置

---

## 改动文件清单

| 文件 | 改动 |
|------|------|
| `CameraOverlayView.swift` | 修复坐标映射（y轴翻转 + aspect计算） |
| `CameraPreviewView.swift` | videoGravity 改为 .resizeAspect |
| `MotionControlApp.swift` | ZStack 中添加状态文字叠加层，去掉原有 StatusPanelView |
| `StatusPanelView.swift` | 可选删除（被文字叠加层替代） |

---

## 依赖关系

- 两个问题互不依赖，可以一次完成
