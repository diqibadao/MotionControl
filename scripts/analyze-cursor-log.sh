#!/bin/bash
# 光标跟手质量分析脚本 — 基准指标体系
# 用法: ./scripts/analyze-cursor-log.sh <日志文件路径>
# 输出: 10 项指标 + 与基准对比

LOG="${1:-/tmp/motioncontrol-v4.log}"
BASELINE_FILTER_LAG=261
BASELINE_TC_GAP=67
BASELINE_TOTAL_LAG=328
BASELINE_STEP_AVG=64
BASELINE_REVERSALS=8
BASELINE_Y_MIN=93
BASELINE_Y_MAX=1080

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  光标跟手质量分析报告"
echo "  日志: $LOG"
echo "  基准: v0.3.0-baseline"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 提取 CURSOR-ABS 数据
grep "CURSOR-ABS" "$LOG" | sed 's/.*hand=(\([^)]*\)).*filter=(\([^)]*\)).*target=(\([^)]*\)).*cursor=(\([^)]*\)).*/\1 \2 \3 \4/' | awk -v BL=$BASELINE_FILTER_LAG -v BT=$BASELINE_TC_GAP -v BTL=$BASELINE_TOTAL_LAG -v BS=$BASELINE_STEP_AVG -v BR=$BASELINE_REVERSALS -v BYN=$BASELINE_Y_MIN -v BYX=$BASELINE_Y_MAX '
function pct(v, base) { return (base > 0) ? (v - base) / base * 100 : 0 }

{
    split($1,h,","); hx=h[1]; hy=h[2]
    split($2,f,","); fx=f[1]; fy=f[2]
    split($3,t,","); tx=t[1]; ty=t[2]
    split($4,c,","); cx=c[1]; cy=c[2]

    # A. 响应性 — 滤波延迟
    f_lag = sqrt((hx-fx)^2 + (hy-fy)^2) * 1920 * 2  # 换算 px
    sum_fl += f_lag
    if (f_lag > max_fl) max_fl = f_lag

    # B. 响应性 — T-C 滞后
    gap = sqrt((tx-cx)^2 + (ty-cy)^2)
    sum_g += gap
    if (gap > max_g) max_g = gap
    if (NR==1 || gap < min_g) min_g = gap
    bucket_g[int(gap/20)]++

    # C. 平滑度 — 步长分布
    if (NR>1) {
        t_step = sqrt((tx-prev_tx)^2 + (ty-prev_ty)^2)
        sum_ts += t_step
        if (t_step > max_ts) max_ts = t_step
        bucket_ts[int(t_step/50)]++

        # D. 方向反转
        if (NR>2 && t_step>5) {
            dot = ((tx-prev_tx)*(prev_tx-prev2_tx) + (ty-prev_ty)*(prev_ty-prev2_ty))
            prev_step = sqrt((prev_tx-prev2_tx)^2 + (prev_ty-prev2_ty)^2)
            if (prev_step>5 && dot/(t_step*prev_step) < -0.7) rev++
        }

        # E. 跳变计数
        if (t_step > 200) jumps_200++
        if (t_step > 500) jumps_500++
        count++
    }

    # F. 覆盖范围
    if (tx > max_x) max_x = tx
    if (tx < min_x || min_x == "") min_x = tx
    if (ty > max_y) max_y = ty
    if (ty < min_y || min_y == "") min_y = ty

    prev2_tx=prev_tx; prev2_ty=prev_ty
    prev_tx=tx; prev_ty=ty
    total=NR
}
END {
    # ── 指标计算 ──
    avg_fl = sum_fl / total
    avg_g  = sum_g / count
    total_lag = avg_fl + avg_g
    avg_ts = sum_ts / count

    # ── 评分（100分制）──
    score = 100
    # 总滞后: 每超基准10px扣1分
    if (total_lag > BTL) score -= (total_lag - BTL) / 10
    else score += (BTL - total_lag) / 20  # 改善加分
    # 跳变: 每次>200px扣2分, >500px扣5分
    score -= jumps_200 * 2
    score -= jumps_500 * 5
    # 反转: 每次扣3分
    if (rev > BR) score -= (rev - BR) * 3

    if (score > 100) score = 100
    if (score < 0) score = 0

    printf "\n"
    printf "┌─────────────────────────────────────────┐\n"
    printf "│  综合评分: %3.0f/100                        │\n", score
    printf "└─────────────────────────────────────────┘\n\n"

    printf "━━━ A. 响应性（越低越好）━━━\n"
    printf "  %-20s %7.0f px  (基准 %d, %+.0f)\n", "1€ Filter 延迟", avg_fl, BL, avg_fl-BL
    printf "  %-20s %7.0f px  (基准 %d, %+.0f)\n", "T-C 滞后", avg_g, BT, avg_g-BT
    printf "  %-20s %7.0f px  (基准 %d, %+.0f)\n", "总滞后", total_lag, BTL, total_lag-BTL

    printf "\n━━━ B. 平滑度（越低越好）━━━\n"
    printf "  %-20s %7.0f px  (基准 %d, %+.0f)\n", "Target 步长 avg", avg_ts, BS, avg_ts-BS
    printf "  %-20s %5d 次     (基准 %d, %+d)\n", "方向反转", rev, BR, rev-BR
    printf "  %-20s %5d 次     (>200px)\n", "大跳变", jumps_200
    printf "  %-20s %5d 次     (>500px)\n", "巨型跳变", jumps_500

    printf "\n━━━ C. 步长分布 ━━━\n"
    for (i=0; i<=10; i++) {
        n = bucket_ts[i]
        if (n > 0) {
            bar = ""
            p = n / count * 100
            for (j=0; j<p/2; j++) bar = bar "█"
            printf "  %3d-%3dpx: %4d (%4.1f%%) %s\n", i*50, (i+1)*50, n, p, bar
        }
    }

    printf "\n━━━ D. T-C 滞后分布 ━━━\n"
    for (i=0; i<=6; i++) {
        n = bucket_g[i]
        if (n > 0) {
            p = n / count * 100
            bar = ""
            for (j=0; j<p/3; j++) bar = bar "█"
            printf "  %3d-%3dpx: %4d (%4.1f%%) %s\n", i*20, (i+1)*20, n, p, bar
        }
    }

    printf "\n━━━ E. 覆盖范围 ━━━\n"
    printf "  X: %.0f ~ %.0f  (全屏=0~1920)\n", min_x, max_x
    printf "  Y: %.0f ~ %.0f  (基准=%d~%d)\n", min_y, max_y, BYN, BYX
    printf "  X 覆盖率: %.0f%%   Y 覆盖率: %.0f%%\n", (max_x-min_x)/1920*100, (max_y-min_y)/1080*100
}'

echo ""
echo "━━━ F. 检测质量 ━━━"
echo "  检测到手: $(grep -c 'hand_detect.*detected=true' "$LOG") 次"
echo "  未检测到: $(grep -c 'hand_detect.*detected=false' "$LOG") 次"
T=$(grep -c 'hand_detect.*detected=true' "$LOG")
F=$(grep -c 'hand_detect.*detected=false' "$LOG")
echo "  检测率: $(echo "scale=1; $T/($T+$F)*100" | bc)%"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
