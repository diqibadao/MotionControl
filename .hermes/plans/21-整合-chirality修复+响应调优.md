# 21-整合 chirality 修复 + 响应调优

> 日期：2026-06-06 | 状态：实施中 | 基准：feat/tune-responsiveness (v0.3.1)

## 来源

- `feat/tune-responsiveness`：1€ Filter + lerp 调优（保留）
- `fix/cursor-jump-4in1`：chirality 修复（挑着拿）

## 拿什么

| 文件 | 拿 | 不拿 |
|------|------|------|
| `CursorController.swift` | import AppKit, chirality 去翻转, currentPosition 初始化, debug print 增强 | 200px clamp, 非线性增益, 旧 filter 参数 |
| `HandPoseDetector.swift` | chirality 滞后锁（3帧投票） | — |
| `Tests/` | 更新左手测试 + 新增滞后锁测试 | maxTargetJump 测试（无 clamp 了） |

## 不改的（保留调优成果）

- 1€ Filter: fcMin=1.5, beta=0.05 ✅
- 120Hz lerp: 0.65 ✅
- 固定 gain=2.0（无非线性增益）✅

## 预期效果

- ✅ 左手方向正确
- ✅ chirality 不翻转
- ✅ 首帧不跳 (0,0)
- ✅ 跟手感与基准版一致
- ✅ 总滞后 ~240px

## 验证

- [ ] swift build
- [ ] swift test 全部通过
- [ ] 右手跟手
- [ ] 左手不反向
- [ ] 无 chirality 镜像跳变
