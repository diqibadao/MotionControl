# Gate 2 Plan — 固定原点（去掉动态校准）

**日期**：2026-06-10
**分支**：feat/frame-loss-guard
**触发**：动态原点校准导致映射歪斜，"拉不回来"

---

## 问题

原点在手刚出现 0.5 秒内取均值，手从左边伸进来 → 原点歪到 0.08 → 整个映射偏移 → 手正常活动全压在左边缘外。

## 参考

Leap Motion InteractionBox、Ultraleap TouchFree、MediaPipe Hands 全线产品：用固定交互区，不动态校准原点。

## 改动

| 文件 | 改动 |
|------|------|
| `CursorController.swift` | 去掉 `calibrationState`、`originAccumulator`、`startCalibration()`、`accumulateOrigin()`，origin 改为常量 `(0.5, 0.4)` |
| `MotionControlApp.swift` | 去掉校准流程（startCalibration/accumulateOrigin/calibrationState 相关调用） |
| `MotionControlTests.swift` | 去掉校准相关测试，更新为固定原点 |

## 不碰

- 1€ 滤波器参数
- 三区增益
- gain 系数

## 新映射

```
handCenter − (0.5, 0.4) = offset
offset × 屏幕宽 × gain = 位移量
屏幕中心 ± 位移量 = 光标位置
→ clamp [0, 屏幕宽] × [0, 屏幕高]
```

手在画面中间 → 光标在屏幕中间。映射永远不变。

## 验证

1. `swift build` + `swift test` 通过
2. `swift run` 启动，手测试 30s
3. 跑 `analyze --json` + `update-baseline` + `generate-report`
4. PECF 对比 baseline
