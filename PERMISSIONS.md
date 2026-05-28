# MotionControl 代码权限清单

> 本文件由项目维护者管理，不允许小明修改。
> 修改本文件等于修改门禁规则，必须走 P-ARCH 流程。

---

## P-PARAM（参数级，无需plan）

改默认值、阈值、灵敏度、颜色、配置常量。

- `Sources/MotionControl/Config/GestureConfig.swift` — 默认值/阈值/参数
- `Sources/MotionControl/Detection/GestureAnalyzer.swift` — 检测阈值常量
- `Sources/MotionControl/Control/CursorController.swift` — 平滑因子/死区阈值

## P-LOGIC（逻辑级，需plan）

改 if/else、循环、算法逻辑、回调处理。

- `Sources/MotionControl/App/MotionControlApp.swift`
- `Sources/MotionControl/Detection/GestureAnalyzer.swift`（手势识别逻辑）
- `Sources/MotionControl/Control/CursorController.swift`（光标融合逻辑）
- `Sources/MotionControl/Detection/DetectionPipeline.swift`
- `Sources/MotionControl/Detection/GazeEstimator.swift`
- `Sources/MotionControl/Control/MouseController.swift`
- `Sources/MotionControl/Views/*.swift`

## P-ARCH（架构级，需plan+流程图）

新增文件、改接口/协议、改类结构、改架构设计。

- 新增 `.swift` 文件
- 修改 `protocol` / `struct` / `class` 定义
- 修改函数签名
- 修改 `import` 依赖

## P-BLOCKED（禁止级）

永远不允许修改。

- `Sources/MotionControl/Camera/CameraService.swift`
- `Sources/MotionControl/Voice/*.swift`
- `Sources/MotionControl/Config/ConfigManager.swift`
- `Sources/MotionControl/App/EventLogger.swift`
- `Sources/MotionControl/App/SystemState.swift`
- `.hermes/plans/*.md`（历史 plan 只读）
- `PERMISSIONS.md`（本文件）
