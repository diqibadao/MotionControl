# MotionControl AGENTS.md

> 项目级开发规范，继承自 `codex-inspired-workflow` skill

---

## 1. 新项目初始化检查清单（Gate 0）

每次新项目开工前，必须依次执行：

```bash
# [0.1] Git root 检查
check-git-root

# [0.2] Swift 版本检测
check-swift-compat

# [0.3] 类型重复检测（有代码后）
check-type-duplicates
```

若 Git root ≠ 项目目录：
```bash
cd {project_dir} && git init && git add -A && git commit -m "init: project"
```

## 2. Aider 指令规范

### 指令三要素
每条 Aider 指令必须包含：
1. **输入源** — 具体类型名（如 `HandPoseResult`）
2. **输出物** — 具体结构体（如 `GestureEvent`）
3. **一句逻辑** — 算法概述（如"距离阈值 < pinchThreshold 判断 GRAB"）

### 指令长度
- 单条 ≤ 200 字符（防安全扫描拦截）
- 超过则用 `--batch` 模式自动拆分
- 或写 `tasks.yaml` 用 `--manifest` 执行

### 命令过长无法一次写入的解决方案

当需要创建 10+ 文件时，**不使用单条 Aider 指令**：

```
❌ 错误做法：一条指令创建 17 个文件
   → 安全拦截 + Aider 上下文溢出 + 部分文件丢失

✅ 正确做法：
   1. 写 tasks.yaml，每个 task = 1-3 个文件
   2. python3 aider-runner.py --manifest tasks.yaml --workdir .
   3. 自动逐个执行，编译验证
```

## 3. 编译错误处理流程

```bash
# 1. 先分类汇总
swift-audit

# 2. 按类别批量修（一条指令修一类）
#    PUBLIC  → sed -i '' 's/public //g' Sources/**/*.swift
#    API     → Aider --message "修复 API... --file X.swift"
#    TYPE    → Aider --message "修复类型... --file Y.swift"

# 3. 修完一类 build 一次
# 4. 重复直到零错误
```

## 4. Aider 运行后验证

每次 Aider 运行后：
```bash
# 验证文件在正确路径
python3 aider-runner.py --message "..." --verify --files A.swift
# 或手动：
find Sources -name "*.swift" -newer Package.swift
```

## 5. 工具链故障降级预案（按优先级执行）

**第一步：修工具（先修工具，不绕路）**
```bash
# 路径问题 → 检查 git root
check-git-root

# 安全拦截 → 拆成短指令
python3 aider-runner.py --batch --message "..." 

# 文件写错 → 确认后再重试
python3 aider-runner.py --message "..." --verify
```

**第二步：重试（换方式）**
```bash
# 换 manifest 模式
python3 aider-runner.py --manifest tasks.yaml --workdir .

# 换模型
python3 aider-runner.py --model deepseek/deepseek-v3 --message "..."
```

**第三步：报告（工具修不好时）**
当以上两步都失败后：
1. 记录失败原因（什么工具、什么错误、尝试了什么）
2. 报告用户等待指示
3. 用户同意后才能直接修编译错误

**第四步：获准后直接修（有限制）**
仅限：
- 删除 public 关键字
- 改属性名（points → normalizedPoints）
- 类型转换（NSNumber → Float）
- 修正参数名

禁止：
- 写新逻辑、改架构、改接口设计
- 创建新文件
- 修改功能逻辑

反面教材：2026-05-27 MotionControl，Aider 路径问题未修工具直接 execute_code 改源码。

## 6. 类型定义集中管理

- 被 2+ 文件引用的基础类型（enum/struct）→ 放在 `Config/Types.swift`
- 执行 `check-type-duplicates` 检测重复

---

## 7. 🔄 自进化机制

每次开发任务完成后，执行自进化检查：

```bash
# 自进化检查流程
after_task_complete() {
    # 1. 检查是否有"新发现的问题"
    #    - 编译过程中遇到了哪些预期外的错误？
    #    - 有没有工具链行为导致返工？
    #    - 有没有规范没覆盖到的场景？
    
    # 2. 对比已有规范
    #    - 这个问题 AGENTS.md 提到过吗？
    #    - 如果提到 → 是我没遵守，还是规范写得不够清楚？
    #    - 如果没提到 → 应该加进去
    
    # 3. 更新规范
    #    - 新规范 → 追加到 AGENTS.md 对应章节
    #    - 新脚本 → 放到 ~/.hermes/profiles/xiaoming/scripts/
    #    - 提交更新说明
    
    # 4. 更新记忆
    #    将教训写入 memory（持久化，跨会话可用）
}
```

### Gate 5 审查增强 — 事件追溯必查项

每次 Gate 5 审查必须逐项检查：

```
□ 每个处理函数都有 EventLogger 日志？
□ 日志包含 IN/OUT 关键字段？
□ 日志包含处理耗时？
□ 跨模块调用能串联（frame_id / request_id）？
□ 无敏感信息泄露？
□ 信息量足够重现处理过程？
```

### 自进化触发条件

| 场景 | 动作 |
|------|------|
| 遇到 AGENTS.md 没覆盖的坑 | 追加到 AGENTS.md + 创建 fix 脚本 |
| 相同的坑踩两次 | 创建 pre-commit hook 机械式拦截 |
| 工具链行为异常 | 更新工具配置或创建 wrapper 脚本 |
| 用户纠正 | 立刻更新规范并记录 |

### 自进化检查清单（Gate 8 强制项） — 2026-05-27 修订

每次开发任务完成后的自进化检查，**必须逐项执行**：

```
□ 1. AGENTS.md 更新
   是否有新踩的坑、新发现的规范漏洞？ → 追加到对应章节
   
□ 2. README.md 更新
   功能清单是否与代码状态一致？（✓/✗）
   项目结构是否匹配文件系统？
   
□ 3. Docs/ 目录更新
   需求文档（01-需求文档.md）是否反映最新功能？
   架构文档（02-架构设计.md）是否反映最新架构？
   
□ 4. .hermes/plans/ 归档
   本轮需求文档 + 实施计划是否已保存到 .hermes/plans/？

□ 5. Skill 沉淀（可选）
   是否有可复用的工作流沉淀为 skill？

□ 6. 记忆更新
   是否有跨会话有用的教训写入 memory？
```

```bash
# 发现新问题 → 一键固化
echo "发现: Git root != workdir 导致文件写错" >> /tmp/lessons.txt
echo "规范: 已追加 Gate 0 检查清单" >> /tmp/lessons.txt
echo "脚本: 已创建 check-git-root && aider-runner.py --verify" >> /tmp/lessons.txt

# 下次开发时自动加载 lessons
cat /tmp/lessons.txt 2>/dev/null | while read line; do
    echo "📖 经验: $line"
done
```

---

## 8. AVFoundation sessionQueue 配置陷阱（2026-05-27 新增）

### 场景
`CameraService.configureSession()` 中将所有 session 操作放入 `sessionQueue.async` 中执行，但 `start()` 方法异步调用后立即检查 `session.isRunning` 并调用 `session.startRunning()`。

### 根因
```swift
// ❌ 错误：async 立即返回，isConfigured 在闭包中设置，但 start() 已往下执行
func configureSession() {
    sessionQueue.async { [weak self] in
        // ... 配置操作 ...
        self.isConfigured = true  // 太晚了
    }
}

func start() {
    if !isConfigured { configureSession() }  // 异步返回，isConfigured 仍为 false
    if !session.isRunning { session.startRunning() }  // 此时 session 还未配置
}
```

### 正确做法
```swift
// ✅ 正确：sync 确保配置同步完成
func configureSession() {
    sessionQueue.sync { [weak self] in
        guard let self = self else { return }
        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }
        // ... 配置操作 ...
        self.isConfigured = true
    }
}
```

### 铁律
AVCaptureSession 的 `beginConfiguration()` / `commitConfiguration()` 之间的所有操作，要么全在 `sessionQueue.sync` 中同步执行，要么用回调/信号量确保 start 等待配置完成。**绝对不能** async 后立即 startRunning。

---

## 9. Vision 坐标映射规范（2026-05-27 新增）

### Vision 坐标系
- `VNHumanHandPoseObservation.recognizedPoints(.all)` 返回归一化坐标 (0~1)
- 坐标系：`(0,0) = 左下角`，`(1,1) = 右上角`（图像坐标系，y 轴向上）
- `AVCaptureVideoPreviewLayer` 显示时自动处理镜像和旋转

### NSView 坐标系
- `(0,0) = 左上角`，`(width,height) = 右下角`（y 轴向下）
- `isFlipped = true` 保持左上角为原点

### 正确坐标转换
```swift
func visionPointToView(_ point: CGPoint, videoRect: CGRect) -> CGPoint {
    // Vision x 直接映射（不需要镜像，previewLayer 已自动处理）
    let x = point.x * videoRect.width + videoRect.origin.x
    // Vision y 向上 → NSView y 向下，需要翻转
    let y = (1.0 - point.y) * videoRect.height + videoRect.origin.y
    return CGPoint(x: x, y: y)
}
```

### 画面比例计算
```swift
// 摄像头 VGA 640×480 (4:3)，.resizeAspect 显示
let cameraAspect: CGFloat = 640.0 / 480.0
let viewAspect = bounds.width / bounds.height
let videoRect: CGRect
if viewAspect > cameraAspect {
    // 视图更宽 → 左右黑边
    let videoHeight = bounds.height
    let videoWidth = videoHeight * cameraAspect
    let xOffset = (bounds.width - videoWidth) / 2
    videoRect = CGRect(x: xOffset, y: 0, width: videoWidth, height: videoHeight)
} else {
    // 视图更高 → 上下黑边
    let videoWidth = bounds.width
    let videoHeight = videoWidth / cameraAspect
    let yOffset = (bounds.height - videoHeight) / 2
    videoRect = CGRect(x: 0, y: yOffset, width: videoWidth, height: videoHeight)
}
```

### 铁律
- **不要**做 x 镜像（`1.0 - point.x`）—— 那是 MediaPipe 浏览器方案的做法，Vision 不需要
- **必须**做 y 翻转（`1.0 - point.y`）—— Vision y 向上 vs NSView y 向下
- **必须**考虑画面比例（videoRect）—— 否则坐标落在黑边区域
