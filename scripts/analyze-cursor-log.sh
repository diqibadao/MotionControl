#!/bin/bash
# MotionControl 光标质量分析 — 23项指标一键评估
# 用法: ./scripts/analyze-cursor-log.sh <日志文件> [基准文件]
# 基准: v0.5.0-silky

LOG="${1:-/tmp/motioncontrol-v6.log}"
BASELINE_LOG="${2:-}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MotionControl 光标质量分析 (v4.0标准)"
echo "  日志: $LOG"
echo "  基准: v0.5.0-silky"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

grep "CURSOR-ABS" "$LOG" | sed 's/.*hand=(\([^)]*\)).*filter=(\([^)]*\)).*target=(\([^)]*\)).*cursor=(\([^)]*\)).*/\1 \2 \3 \4/' | awk '
BEGIN {
    # 基准值 (v0.5.0-silky)
    B3 = 197; B2 = 34; B4 = 5; B5 = 11; B6 = 5
    B8 = 11.8; B9 = 30.0; B10 = 89; B12 = 77.9
    B15 = 49.9; B16 = 65.6; B18 = 100; B19 = 94
    B20 = 24.1; B22 = 148; B23 = 2
}
{
    split($1,h,","); hx=h[1]; hy=h[2]
    split($2,f,","); fx=f[1]; fy=f[2]
    split($3,t,","); tx=t[1]; ty=t[2]
    split($4,c,","); cx=c[1]; cy=c[2]

    # ── #1 滤波延迟 ──
    f_lag = sqrt((hx-fx)^2 + (hy-fy)^2) * 1920 * 2
    sum1 += f_lag

    gap = sqrt((tx-cx)^2 + (ty-cy)^2)
    sum2 += gap
    if (NR==1 || gap < min2) min2 = gap
    if (gap > max2) max2 = gap
    bucket_gap[int(gap/20)]++

    if (NR>1) {
        t_step = sqrt((tx-prev_tx)^2 + (ty-prev_ty)^2)
        sum_t += t_step
        if (t_step > max_t) max_t = t_step
        bucket_t[int(t_step/50)]++

        # ── #4 方向反转 ──
        if (NR>2 && t_step>5) {
            dot = ((tx-prev_tx)*(prev_tx-prev2_tx) + (ty-prev_ty)*(prev_ty-prev2_ty))
            prev_step = sqrt((prev_tx-prev2_tx)^2 + (prev_ty-prev2_ty)^2)
            if (prev_step>5 && dot/(t_step*prev_step) < -0.7) rev4++
        }
        # ── #5 #6 跳变 ──
        if (t_step > 200) jumps5++
        if (t_step > 500) jumps6++
        count++
    }

    # ── #8 #9 静止抖动 ──
    if (NR>1 && t_step<8) {
        still_n++; still_sx+=cx; still_sy+=cy; still_sqx+=cx*cx; still_sqy+=cy*cy
        if(still_n==1){still_fx=cx;still_fy=cy}
        still_lx=cx;still_ly=cy
    } else if (still_n>=5) {
        mx=still_sx/still_n; my=still_sy/still_n
        j=sqrt(still_sqx/still_n-mx*mx + still_sqy/still_n-my*my)
        sum8+=j; cnt8++
        if(j>max8)max8=j
        exc=sqrt((still_lx-still_fx)^2+(still_ly-still_fy)^2)
        sum9+=exc; cnt9++
        if(exc>max9)max9=exc
        still_n=0;still_sx=0;still_sy=0;still_sqx=0;still_sqy=0
    } else {still_n=0;still_sx=0;still_sy=0;still_sqx=0;still_sqy=0}

    # ── #10 路径效率 ──
    seg_n++; seg_dx+=(NR>1)?tx-prev_tx:0; seg_dy+=(NR>1)?ty-prev_ty:0; seg_len+=t_step
    if(seg_n>=10){
        straight=sqrt(seg_dx*seg_dx+seg_dy*seg_dy)
        if(seg_len>0&&straight>30){sum10+=straight/seg_len;cnt10++}
        seg_n=0;seg_dx=0;seg_dy=0;seg_len=0
    }

    # ── #18 #19 覆盖 ──
    if(tx>maxX||maxX=="")maxX=tx; if(tx<minX||minX=="")minX=tx
    if(ty>maxY||maxY=="")maxY=ty; if(ty<minY||minY=="")minY=ty

    prev2_tx=prev_tx; prev2_ty=prev_ty
    prev_tx=tx; prev_ty=ty
    total=NR
}
END {
    avg1 = sum1/total; avg2 = sum2/count; avg3 = avg1+avg2
    avg_t = sum_t/count
    avg8 = (cnt8>0)?sum8/cnt8:0; avg9 = (cnt9>0)?sum9/cnt9:0
    avg10 = (cnt10>0)?sum10/cnt10*100:0

    xcov = (maxX-minX)/1920*100; ycov = (maxY-minY)/1080*100

    # 步长分布
    p12 = (bucket_t[0]+0)/count*100
    p13 = (bucket_t[1]+0)/count*100
    p14 = 0; for(i=3;i<=25;i++)p14+=bucket_t[i]; p14=p14/count*100

    # T-C滞后分布
    p15 = (bucket_gap[0]+0)/count*100
    p16 = (bucket_gap[0]+bucket_gap[1]+0)/count*100
    p17 = 0; for(i=6;i<=40;i++)p17+=bucket_gap[i]; p17=p17/count*100

    printf "\n┌──────────────────────────────────────────────────────┐\n"
    printf "│  综合判定: "
    worse=0; better=0
    if(avg3>B3)worse++; else better++
    if(rev4>B4)worse++; else better++
    if(jumps6>B6)worse++; else better++
    if(ycov<B19)worse++; else better++
    if(worse>0) printf "⚠️ %d项恶化  ", worse
    else printf "✅ 全部达标  "
    printf "%d项改善                              │\n", better
    printf "└──────────────────────────────────────────────────────┘\n"

    printf "\n  #1 滤波延迟       %5.0f px  (目标<180)\n", avg1
    printf "  #2 T-C滞后        %5.0f px  (基%3.0f, 目标<40)\n", avg2, B2
    printf "  #3 总滞后         %5.0f px  (基%3.0f, 目标<220)\n", avg3, B3
    printf "  #4 方向反转       %5d 次  (基%3d,   目标<5)\n", rev4, B4
    printf "  #5 大跳变>200px   %5d 次  (基%3d,   目标<10)\n", jumps5, B5
    printf "  #6 巨型跳变>500px %5d 次  (基%3d,    目标0)\n", jumps6, B6
    printf "  #7 正交摆动(ODC)  (待实现)\n"
    printf "  #8 抖动半径       %5.1f px  (基%4.1f, 目标<8)\n", avg8, B8
    printf "  #9 最大偏移       %5.1f px  (基%4.1f, 目标<35)\n", avg9, B9
    printf " #10 路径效率       %5.0f %%   (基%3.0f,  目标>85)\n", avg10, B10
    printf " #11 任务轴交叉     (待实现)\n"
    printf " #12 微步0-50px     %5.1f %%   (基%4.1f, 目标>70)\n", p12, B12
    printf " #13 正常50-100px   %5.1f %%   (目标15-30)\n", p13
    printf " #14 大步>150px     %5.1f %%   (目标<3)\n", p14
    printf " #15 紧贴0-20px     %5.1f %%   (基%4.1f, 目标>45)\n", p15, B15
    printf " #16 良好0-40px     %5.1f %%   (基%4.1f, 目标>60)\n", p16, B16
    printf " #17 严重>120px     %5.1f %%   (目标<3)\n", p17
    printf " #18 X覆盖率        %5.0f %%   (基%3.0f,  目标100)\n", xcov, B18
    printf " #19 Y覆盖率        %5.0f %%   (基%3.0f,  目标100)\n", ycov, B19
}'

echo ""
echo "━━━ #20-#23 边缘质量 ━━━"
grep "CURSOR-ABS" "$LOG" | sed 's/.*hand=(\([^)]*\)).*target=(\([^)]*\)).*cursor=(\([^)]*\)).*/\1 \2 \3/' | awk '{
    split($1,h,","); hx=h[1]; hy=h[2]
    split($2,t,","); tx=t[1]; ty=t[2]
    at_edge=(tx<=10||tx>=1910||ty<=10||ty>=1070)
    if(NR>1){
        hdx=hx-prev_hx; hdy=hy-prev_hy
        tdx=tx-prev_tx; tdy=ty-prev_ty
        if(at_edge&&prev_at_edge){
            ef++; eht+=sqrt(hdx*hdx+hdy*hdy)
            if(abs(hdx)>0.005&&abs(tdx)<5){sx++
                if(abs(tdy)>3)sxy++}
        }
        if(prev_at_edge&&!at_edge){
            sum_dz+=eht;dzc++; if(eht>max_dz)max_dz=eht; eht=0}
    }
    prev_hx=hx;prev_hy=hy;prev_at_edge=at_edge
    prev_tx=tx;prev_ty=ty; tf++
    if(at_edge)tef++
}
END{
    printf " #20 边缘死区       %5.1f %%  (基24.1, 目标<8)\n", sum_dz/(dzc+0.001)*100
    printf " #21 边缘帧占比     %5.1f %%  (目标<15)\n", tef/tf*100
    printf " #22 方向错位       %5d/%-5d (基148,  目标<20)\n", sx, ef
    printf " #22 其中只上下走   %5d 次\n", sxy
}
function abs(v){return v<0?-v:v}'

echo ""
echo "━━━ 辅助指标 ━━━"
T=$(grep -c 'hand_detect.*detected=true' "$LOG")
F=$(grep -c 'hand_detect.*detected=false' "$LOG")
echo "  检测率: $(echo "scale=1; $T/($T+$F)*100" | bc)% ($T/$((T+F)))"

grep "hand_detect" "$LOG" | awk -F'[][]' '{print $2}' | awk -F'[: ]' '{
    t=$1*3600+$2*60+$3
    if(NR>1){dt=t-prev_t;sum_dt+=dt;cnt++;if(dt>max_dt)max_dt=dt;if(dt>0.2)drops++}
    prev_t=t
}
END{
    printf " #23 帧丢失>200ms   %5d 次  (基2,     目标0)\n", drops
    printf "  检测帧率: %.0f fps\n", (sum_dt>0)?cnt/sum_dt:0
    printf "  最大帧间隔: %.0f ms (目标<100)\n", max_dt*1000
}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
