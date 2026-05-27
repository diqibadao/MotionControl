# MotionControl 运行时问题修复计划

> 来源：App 日志分析（2026-05-27 实际运行）

---

## 问题清单

### P0 — 功能不工作

| # | 问题 | 表现 | 根因 | 修复方案 |
|---|------|------|------|---------|
| 1 | 张开五指无反应 | 日志只有 pinch/none，无 openPalm | GestureAnalyzer 阈值太低（openPalmThreshold=100 像素但手在画面中距离>200px） | 阈值翻倍：openPalmThreshold=200, pinchThreshold=80 |
| 2 | 人脸全部检测失败 | face_detect detected=false 持续 | 分辨率太高导致人脸检测超时 | 降分辨率后自动恢复 |
| 3 | 每帧检测 3-10 秒 | hand_detect duration=3000~10000ms | ①分辨率 1920×1080 太高 ②每帧都检测 | ① CameraService preset 改为 .vga640x480 ② DetectionPipeline 每 5 帧检测一次（手部+人脸同帧） |

### P1 — 性能/精度

| # | 问题 | 修复 |
|---|------|------|
| 4 | 手势误识别为 doublePinch | 双击窗口 500ms 太宽，缩到 300ms |
| 5 | 挥手（SWIPE）没实现 | velocity 始终 .zero，无跨帧追踪 |
| 6 | 手势识别置信度 0.0 | 距离计算用了归一化坐标但阈值是像素值，匹配后置信度会正常 |

---

## 修复执行顺序

```bash
# 1. CameraService.swift — 分辨率改为 640×480
# 2. DetectionPipeline.swift — 每 5 帧检测 + 关人脸
# 3. GestureAnalyzer.swift — 阈值翻倍 + 双击窗口缩到 300ms
```

## 验证方式

```bash
cd ~/Desktop/vibe项目/MotionControl
swift build && .build/debug/MotionControl
# 看日志：hand_detect duration < 200ms, gesture=openPalm 出现
```
