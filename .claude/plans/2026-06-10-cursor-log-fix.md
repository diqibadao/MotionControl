# Gate 2 Plan — 光标日志自动落盘 + 分析管道修复

**日期**：2026-06-10
**分支**：feat/frame-loss-guard
**触发**：测试数据丢失，根因 `EventLogger` 只 `print()` 不写文件

---

## 问题

1. `EventLogger.log()` 仅 stdout，APP 关掉数据就没了
2. `CURSOR-ABS` 日志在 `#if DEBUG` 里用 `print()`，不进 EventLogger
3. 分析脚本 `analyze-cursor-log-v5.py` 依赖 `[CURSOR-ABS]` 和 `[KEYPOINTS]` 行

## 改动清单（4 文件）

| 文件 | 改动 | 影响 |
|------|------|------|
| `EventLogger.swift` | 加 `startLogFile()`/`stopLogFile()`，自动写 `Data/logs/raw/run_*.log` | 所有日志落盘 |
| `MotionControlApp.swift` | `onAppear` 调 `startLogFile()`，`onDisappear` 调 `stopLogFile()` | 自动启停 |
| `PermissionManager.swift` | Speech 检查加 Bundle 判断，CLI 模式跳过（避免 TCC SIGABRT） | 修复启动崩溃 |
| `CursorController.swift` | `CURSOR-ABS` print → EventLogger.log() | 分析脚本能读到 |
| `Package.swift` | 加 `swiftSettings: [.define("DEBUG")]` + linkerSettings 嵌入 Info.plist | Debug 日志 + 隐私权限 |

## 不碰

- 手势/光标核心逻辑（`HandPoseDetector`、`CursorController.updateWithAbsolutePosition`）
- 测试文件（已有改动不在 scope）

## 验证

1. `swift build` 通过
2. `swift run` → 用户用手控制光标 30s
3. 日志文件 `Data/logs/raw/run_*.log` 非空，含 `CURSOR-ABS` 行 ≥ 100
4. `python3 scripts/analyze-cursor-log-v5.py <日志>` 输出 23 项指标
5. 对比 baseline `Data/baselines/history.jsonl`

## 风险

- TCC 权限在 rebuild 后可能重置 → PermissionManager 已修复（跳过 CLI 模式的 Speech 检查）
