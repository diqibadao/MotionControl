#!/bin/bash
# MotionControl 门禁系统安装脚本
# 安装 pre-commit hook + 配置 aider-runner

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "📦 安装 MotionControl 门禁系统"
echo "   项目目录: $PROJECT_DIR"

# 1. 安装 pre-commit hook
echo ""
echo "1️⃣  安装 pre-commit hook..."
HOOK_SRC="$PROJECT_DIR/scripts/pre-commit.sh"
HOOK_DST="$PROJECT_DIR/.git/hooks/pre-commit"

if [ -f "$HOOK_DST" ]; then
    echo "   备份旧 hook 到 $HOOK_DST.bak"
    cp "$HOOK_DST" "$HOOK_DST.bak"
fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "   ✅ pre-commit hook 已安装: $HOOK_DST"

# 2. 检查 PERMISSIONS.md 是否存在
echo ""
echo "2️⃣  检查 PERMISSIONS.md..."
if [ -f "$PROJECT_DIR/PERMISSIONS.md" ]; then
    echo "   ✅ PERMISSIONS.md 存在"
else
    echo "   ❌ PERMISSIONS.md 不存在！请先创建"
    exit 1
fi

# 3. 检查 aider-runner 并提醒修改
echo ""
echo "3️⃣  检查 aider-runner..."
RUNNER_PATH="$HOME/.hermes/bin/aider-runner.py"
if [ -f "$RUNNER_PATH" ]; then
    echo "   ⚠️  aider-runner.py 需要手动添加 plan 检查逻辑"
    echo "   请在 run_aider() 调用前加入:"
    echo ""
    echo "   ┌─────────────────────────────────────────────┐"
    echo "   │ # === 门禁检查 ===                          │"
    echo "   │ if args.manifest:                           │"
    echo "   │     # manifest 模式走批量，暂不检查         │"
    echo "   │     pass                                    │"
    echo "   │ elif not check_plan_confirmed(workdir):     │"
    echo "   │     sys.exit(1)                             │"
    echo "   │ # === 门禁结束 ===                          │"
    echo "   └─────────────────────────────────────────────┘"
    echo ""
    echo "   同时添加 check_plan_confirmed() 函数到文件末尾"
else
    echo "   ❌ 未找到 aider-runner.py"
    echo "   路径: $RUNNER_PATH"
fi

echo ""
echo "✅ 门禁系统安装完成"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  使用说明"
echo ""
echo "  P-PARAM 修改: 直接调 Aider"
echo "  P-LOGIC 修改: 先生成 plan → 展示给用户 → 加 ✅ → 调 Aider"
echo "  P-ARCH 修改: 同上 + ASCII 流程图"
echo "  P-BLOCKED: 不能碰"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
