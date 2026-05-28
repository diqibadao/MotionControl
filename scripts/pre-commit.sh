#!/bin/bash
# MotionControl pre-commit hook
# 门禁第二层：检查改动的文件是否符合权限规则

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PLANS_DIR=".hermes/plans"
PERMISSIONS_FILE="PERMISSIONS.md"

# 获取当前暂存区中改动的 .swift 文件
CHANGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$')

if [ -z "$CHANGED_FILES" ]; then
    # 没有改动 .swift 文件，放行（可能只改了 md/json/plist）
    exit 0
fi

# 检查是否有已确认的 plan
LATEST_PLAN=$(ls -t $PLANS_DIR/*.md 2>/dev/null | head -1)
PLAN_CONFIRMED=false

if [ -n "$LATEST_PLAN" ] && grep -q "✅ 已确认" "$LATEST_PLAN" 2>/dev/null; then
    PLAN_CONFIRMED=true
fi

# 逐文件检查权限
HAS_BLOCKED=false
HAS_ARCH=false
HAS_LOGIC=false
ALL_PARAM=true

while IFS= read -r file; do
    # 检查是否是 P-BLOCKED
    if grep -q "^-\s*$file$" "$PERMISSIONS_FILE" 2>/dev/null || \
       echo "$file" | grep -qF "$(grep 'P-BLOCKED' -A 20 "$PERMISSIONS_FILE" | grep '^-' | sed 's/^- //')"; then
        echo -e "${RED}[BLOCKED]${NC} $file 被禁止修改"
        HAS_BLOCKED=true
        continue
    fi

    # 检查是否需要 P-ARCH 流程
    if grep -q "P-ARCH" "$PERMISSIONS_FILE" 2>/dev/null; then
        ARCH_PATTERNS=$(grep 'P-ARCH' -A 20 "$PERMISSIONS_FILE" | grep '^-' | sed 's/^- //')
        for pattern in "$ARCH_PATTERNS"; do
            if echo "$file" | grep -qE "$pattern" 2>/dev/null; then
                HAS_ARCH=true
                ALL_PARAM=false
                break
            fi
        done
    fi

    # 检查是否是 P-LOGIC 级
    if grep -q "P-LOGIC" "$PERMISSIONS_FILE" 2>/dev/null; then
        LOGIC_PATTERNS=$(grep 'P-LOGIC' -A 20 "$PERMISSIONS_FILE" | tail -n +3 | grep '^-' | sed 's/^- //')
        while IFS= read -r pattern; do
            if [ -z "$pattern" ]; then continue; fi
            # 处理通配符
            case "$file" in
                $pattern) HAS_LOGIC=true; ALL_PARAM=false; break ;;
            esac
        done <<< "$LOGIC_PATTERNS"
    fi
done <<< "$CHANGED_FILES"

# 执行门禁
if [ "$HAS_BLOCKED" = true ]; then
    echo -e "${RED}❌ 提交被拒绝：包含 P-BLOCKED 级文件的修改${NC}"
    echo "   如需修改请先联系项目维护者调整 PERMISSIONS.md"
    exit 1
fi

if [ "$HAS_ARCH" = true ] && [ "$PLAN_CONFIRMED" != true ]; then
    echo -e "${RED}❌ 提交被拒绝：包含 P-ARCH 级文件的修改，但 plan 未确认${NC}"
    echo "   请先生成 plan（含 ASCII 流程图）并让用户确认"
    exit 1
fi

if [ "$HAS_LOGIC" = true ] || [ "$HAS_ARCH" = true ]; then
    if [ "$PLAN_CONFIRMED" != true ]; then
        echo -e "${RED}❌ 提交被拒绝：包含 P-LOGIC/P-ARCH 级文件的修改，但 plan 未确认${NC}"
        echo "   最新 plan: $LATEST_PLAN"
        if [ -n "$LATEST_PLAN" ]; then
            echo "   请在 plan 中添加 ✅ 已确认 标记"
        else
            echo "   请先生成 plan"
        fi
        exit 1
    fi
fi

if [ "$ALL_PARAM" = true ]; then
    echo -e "${GREEN}✅ 参数级修改，通过${NC}"
fi

echo -e "${GREEN}✅ 权限检查通过${NC}"
exit 0
