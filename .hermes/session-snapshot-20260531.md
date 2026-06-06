# MotionControl 会话快照 — 2026-05-31 23:10

## 已完成改动

| 改动 | 文件 | 效果 |
|------|------|------|
| Delta 灵敏度 | CursorController.swift | 指尖位移→光标 |
| 速度基加速曲线 | CursorController.swift | vel<50→0.4x, <200→1x, ≥200→1~4x |
| Velocity EMA (α=0.3) | CursorController.swift | 去抖动 |
| 方向一致性检查 | CursorController.swift | rawV×smoothV≤0时清零，防画十字漂移 |
| 非对称灵敏度 | CursorController.swift | 右/下 1.5x（右手配置 isRightHanded） |
| 固定 dt = 1/30 | CursorController.swift | velocity 不受帧间隔抖动影响 |
| 60fps 补帧 | CursorController.swift + MotionControlApp.swift | displayVelocityX/Y 暴露 + Timer 16ms |
| 激活阈值收紧 | MotionControlApp.swift | indexExt>0.15, otherLow<0.15 |
| 去 %2 跳帧 | DetectionPipeline.swift | 全帧处理 |
| 面部姿态隔帧 | FaceMeshDetector.swift | faceRects 每15帧跑一次+缓存 |
| Dock 磁吸 | UIElementScanner.swift | scanDock() |
| 灵敏度 24→3 | GestureConfig.swift | 配合加速曲线 |
| 注视偏移禁用 | CursorController.swift | 纯手指控制，保留下巴 |

## 已知未解决问题

**【P0】串行队列瓶颈** — 手部检测和面部检测在同一个 serial queue 上。face detect 每帧等 GPU 5秒，锁住 hand detect，实际 hand 帧率 ~0.2fps。修复：拆 handQueue + faceQueue 两个队列。

**【P1】face_detect 总时长 5秒** — 不是模型慢（perform 只要 5ms），是 VNImageRequestHandler.init 在队列堆积时因 pixel buffer GPU 锁等待。拆队列后应消失。

## 待办（下回继续）

1. 拆 handQueue / faceQueue 两个独立队列
2. 验证 30fps hand detection 可达
3. 调参（加速曲线阈值、EMA alpha）
4. 头部手部融合（模式C）

## git 记录

```
d1c7643 fix: 去掉跳帧和sub-pixel，收紧手势激活阈值
e89cfa2 feat: 新增60fps补帧定时器并暴露平滑速度属性
5194b00 feat: 添加子像素累积与方向一致性检查以优化光标平滑
dc8276f feat: 添加左右手配置以支持非对称灵敏度方向
2c96479 feat: 为光标移动添加方向感知的非对称灵敏度
...
```
