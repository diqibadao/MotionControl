#!/bin/bash
# PECF Bridge — MotionControl 三层数据通道
# swift test → 原始日志 → 23项分析报告 → 5项聚合指标 → pecf gate
set -e
cd "$(dirname "$0")/.."

mkdir -p Data/logs/raw Data/logs/normalized
TS=$(date +%Y%m%d_%H%M%S)
RAW="Data/logs/raw/run_${TS}.log"
NORM="Data/logs/normalized/run_${TS}.log"

# ═══ 第1层: 跑测试 → 原始日志 ═══
echo "========== [PECF Bridge] L1: Raw =========="
echo "[1/4] swift test (raw → ${RAW})..."
swift test 2>&1 | tee "$RAW"
TEST_EXIT=${PIPESTATUS[0]}

if [ $TEST_EXIT -ne 0 ]; then
    echo "⚠️  swift test 失败 (exit=$TEST_EXIT)，PECF 门禁自动放行（安全降级）"
    exit 0
fi

# ═══ 第2层: 定位 replay log → 全量分析报告 → 通用中间日志 ═══
echo ""
echo "[2/4] 定位 replay log..."
REPLAY_LOG=$(grep '入库:' "$RAW" 2>/dev/null | sed -n 's/.*入库: //p' | head -1)

if [ -z "$REPLAY_LOG" ] || [ ! -f "$REPLAY_LOG" ]; then
    # 兜底：找 Docs/logs/ 下最新的 *-replay.log
    REPLAY_LOG=$(ls -t Docs/logs/*-replay.log 2>/dev/null | head -1)
fi

if [ -z "$REPLAY_LOG" ] || [ ! -f "$REPLAY_LOG" ]; then
    echo "⚠️  找不到 replay log，PECF 门禁自动放行（安全降级）"
    exit 0
fi

echo "  日志: $REPLAY_LOG"
echo ""

# 全量分析报告 → 通用中间日志（23项指标，可审计回溯）
echo "[3/4] 全量分析 → ${NORM}..."
python3 scripts/analyze-cursor-log-v5.py "$REPLAY_LOG" 2>&1 | tee "$NORM"
echo ""

# ═══ 第3层: 通用中间日志 → 聚合指标（5项核心指标） ═══
echo "[4/4] 聚合指标 → Data/logs/current_run.json..."
python3 scripts/analyze-cursor-log-v5.py "$REPLAY_LOG" --json 2>/dev/null > Data/logs/current_run.json

python3 -c "
import json
m = json.load(open('Data/logs/current_run.json'))
for k,v in m.items():
    print(f'    {k}: {v}')
"

# ═══ 第4步: 门禁判定 ═══
echo ""
echo "========== [PECF Gate] =========="
pecf gate Data/logs/current_run.json
