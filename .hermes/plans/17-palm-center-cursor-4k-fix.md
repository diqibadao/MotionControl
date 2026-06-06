# 17-手掌几何中心光标 + 4K屏幕灵敏度归一化

> 日期：2026-06-06
> 状态：✅ 已确认

## 问题

1. **食指指尖方案不可用**：外接 4K 摄像头角度导致手指被压缩，识别为握拳（indexExt < 0.07）；伸直食指也疲劳
2. **4K 屏幕灵敏度失控**：`raw × screenSize × sensitivity` 公式在 4K 屏上等效灵敏度 7.8x，光标乱飞
3. **手势误触**：测试时 swipeUp/swipeDown/leftClick 等手势不断触发桌面操作

## 方案

### 1. 几何中心替代指尖
- 使用 `HandPoseResult.palmCenter`（手腕 + 4 个 MCP 均值），SRM 2025 论文方案
- 去掉手指伸展检测（`fingerExtension`），改为手部置信度 > 0.15 即激活
- 任意手势均可，不累、角度不敏感、更稳定（文献 95% vs 指尖 61%）

### 2. 屏幕分辨率归一化
- `CursorController.updateWithDelta` 中 `screenSize.width/height` → 参考分辨率 `1920×1080`
- 效果：4K 屏等效灵敏度从 7.8x → 3.0x，内置屏微调（3.0 → 3.9）

### 3. 手势映射临时禁用
- `onGesture` 回调第一行 `return`，纯光标测试模式

## 改动文件

| 文件 | 级别 | 改动 |
|------|:--:|------|
| `CursorController.swift` | P-PARAM | 参考分辨率归一化 |
| `MotionControlApp.swift` | P-LOGIC | palmCenter 跟踪 + 手势禁用 |

## 数据流

```
摄像头帧 → HandPoseDetector → HandPoseResult
  ↓ palmCenter（手腕+MCP均值）
  ↓ updateWithDelta（参考分辨率 1920×1080）
  ↓ computeCursor（磁吸+边界）
  ↓ CGWarpMouseCursorPosition → 系统光标
```

## 验证

- [x] swift build 通过
- [x] 手掌自然放置即可控制光标（无需伸手指）
- [ ] 光标线性度测试（需用户确认）
- [ ] 4K 屏灵敏度测试（需用户确认）
