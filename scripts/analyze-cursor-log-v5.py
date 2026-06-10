#!/usr/bin/env python3
"""
MotionControl 光标质量分析 v5.0 — 三层数据分析体系
用法: python3 scripts/analyze-cursor-log-v5.py <日志文件> [--replay]

Layer 1: 原始数据质量 — 关键点检测率/抖动/handSide准确率
Layer 2: 算法一致性 — 手→光标方向一致率（分左右手）
Layer 3: 输出质量 — 23项指标 + 分向 + 分手扩展
"""

import re, sys, json, argparse
from collections import defaultdict

LOG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/motioncontrol.log"
IS_REPLAY = "--replay" in sys.argv

# ============================================================
# 基线值 (v0.5.0-silky)
# ============================================================
B = {
    "rev": 5, "jump5": 11, "jump6": 5,
    "jitter": 11.8, "max_excursion": 30.0, "path_eff": 89,
    "micro_step": 77.9, "tight": 49.9, "good": 65.6,
    "xcov": 100, "ycov": 94,
    "edge_dead": 24.1, "dir_misalign": 148, "frame_drop": 2,
}


def parse_log(path):
    """解析日志，返回 keypoints 帧 和 cursor 帧"""
    kp_frames = []  # [{handSide, wrist:(x,y,detected), indexMCP:..., ...}]
    cur_frames = []  # [{handSide, hand:(x,y), target:(x,y), cursor:(x,y)}]

    with open(path) as f:
        for line in f:
            # [KEYPOINTS] handSide=right wrist=0.1,0.2,1 indexMCP=...
            if "[KEYPOINTS]" in line:
                kp = {}
                m = re.search(r"handSide=(\w+)", line)
                kp["handSide"] = m.group(1) if m else "unknown"
                for pt in ["wrist", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]:
                    m = re.search(rf"{pt}=([-\d.]+),([-\d.]+),([-\d.]+)", line)
                    if m:
                        x, y, det = float(m.group(1)), float(m.group(2)), float(m.group(3))
                        kp[pt] = (x, y, det > 0.5)
                    else:
                        kp[pt] = (0, 0, False)
                m = re.search(r"palmCenter=([-\d.]+),([-\d.]+)", line)
                if m:
                    kp["palmCenter"] = (float(m.group(1)), float(m.group(2)))
                kp_frames.append(kp)

            # [CURSOR-ABS] handSide=right hand=(0.5,0.4) target=(960,540) cursor=(950,535)
            if "[CURSOR-ABS]" in line:
                cf = {}
                m = re.search(r"handSide=(\w+)", line)
                cf["handSide"] = m.group(1) if m else "unknown"
                m = re.search(r"hand=\(([^)]+)\)", line)
                if m:
                    x, y = m.group(1).split(",")
                    cf["hand"] = (float(x), float(y))
                m = re.search(r"target=\(([^)]+)\)", line)
                if m:
                    x, y = m.group(1).split(",")
                    cf["target"] = (float(x), float(y))
                m = re.search(r"cursor=\(([^)]+)\)", line)
                if m:
                    x, y = m.group(1).split(",")
                    cf["cursor"] = (float(x), float(y))
                if "hand" in cf and "target" in cf and "cursor" in cf:
                    cur_frames.append(cf)

    return kp_frames, cur_frames


# ============================================================
# Layer 1: 原始数据质量
# ============================================================
def analyze_layer1(kp_frames):
    if not kp_frames:
        return {"note": "无 [KEYPOINTS] 数据 — 回放日志不含关键点信息"}

    pts = ["wrist", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]
    n = len(kp_frames)

    result = {}
    # K1-K5: 各关键点检测率
    for pt in pts:
        det_frames = sum(1 for f in kp_frames if f.get(pt, (0, 0, False))[2])
        result[f"K-{pt}-detection"] = det_frames / n * 100 if n else 0

    # K6-K10: 各关键点抖动 (帧间位移 stddev)
    for pt in pts:
        positions = []
        for f in kp_frames:
            x, y, det = f.get(pt, (0, 0, False))
            if det:
                positions.append((x, y))
        if len(positions) > 1:
            jitters = []
            for i in range(1, len(positions)):
                dx = positions[i][0] - positions[i-1][0]
                dy = positions[i][1] - positions[i-1][1]
                jitters.append((dx*dx + dy*dy)**0.5)
            avg_jitter = sum(jitters) / len(jitters) * 1920  # 归一化→像素
            result[f"K-{pt}-jitter"] = avg_jitter
        else:
            result[f"K-{pt}-jitter"] = 0

    # K11: handSide 准确率
    result["K-handSide-known"] = sum(1 for f in kp_frames if f["handSide"] != "unknown") / n * 100 if n else 0
    result["K-left-pct"] = sum(1 for f in kp_frames if f["handSide"] == "left") / n * 100 if n else 0
    result["K-right-pct"] = sum(1 for f in kp_frames if f["handSide"] == "right") / n * 100 if n else 0

    # K12: wrist 底部检测率 (y > 0.8)
    wrist_bottom = sum(1 for f in kp_frames if f.get("wrist", (0, 0, False))[2] and f["wrist"][1] > 0.8)
    result["K-wrist-bottom-det"] = wrist_bottom / n * 100 if n else 0

    return result


# ============================================================
# Layer 2: 算法一致性
# ============================================================
def analyze_layer2(cur_frames):
    if len(cur_frames) < 2:
        return {"note": "数据不足"}

    def direction_agreement(frames, hand_side=None):
        """计算手→光标 X/Y 方向一致率。
        hand_side=None → 全部帧; 'left'/'right' → 仅该手

        摄像头镜像下，手物理右移→摄像头X↓→offset<0→cursor右移，左右手均同此规律。
        log中 hand与target 在X方向应始终反向（hdx>0 → tdx<0）。
        """
        agree_x = 0
        agree_y = 0
        total_x = 0
        total_y = 0
        for i in range(1, len(frames)):
            hs = frames[i]["handSide"]
            if hand_side and hs != hand_side:
                continue  # 过滤特定手

            hdx = frames[i]["hand"][0] - frames[i-1]["hand"][0]
            hdy = frames[i]["hand"][1] - frames[i-1]["hand"][1]
            tdx = frames[i]["target"][0] - frames[i-1]["target"][0]
            tdy = frames[i]["target"][1] - frames[i-1]["target"][1]

            # X方向: 所有手（含左右手、unknown）统一 — 手与target反向
            # cursorX = screenCX - offsetX * W * G, hand右移→offset>0→cursor左移
            if abs(hdx) >= 0.0005 and abs(tdx) >= 2:
                total_x += 1
                if (hdx > 0 and tdx < 0) or (hdx < 0 and tdx > 0):
                    agree_x += 1

            # Y方向: 所有手同向
            if abs(hdy) >= 0.0005 and abs(tdy) >= 2:
                total_y += 1
                if (hdy > 0 and tdy > 0) or (hdy < 0 and tdy < 0):
                    agree_y += 1

        return agree_x, agree_y, total_x, total_y

    # C1-C2: 整体方向一致率
    ax, ay, nx, ny = direction_agreement(cur_frames)
    # C3: 左手
    lax, lay, lnx, lny = direction_agreement(cur_frames, "left")
    # C4: 右手
    rax, ray, rnx, rny = direction_agreement(cur_frames, "right")

    result = {
        "C1-dir-agree-X": ax / max(nx, 1) * 100,
        "C2-dir-agree-Y": ay / max(ny, 1) * 100,
        "C3-left-agree-X": lax / max(lnx, 1) * 100 if lnx > 10 else None,
        "C4-right-agree-X": rax / max(rnx, 1) * 100 if rnx > 10 else None,
        "C3-left-frames": lnx,
        "C4-right-frames": rnx,
        "C-all-frames": len(cur_frames),
    }

    # C5: chirality 对称性 — 左右手在相同手位移下 target 位移是否对称
    # 简化: 比较左右手的平均 |hand_dx| / |target_dx| 比值
    left_ratios = []
    right_ratios = []
    for i in range(1, len(cur_frames)):
        hdx = cur_frames[i]["hand"][0] - cur_frames[i-1]["hand"][0]
        hdy = cur_frames[i]["hand"][1] - cur_frames[i-1]["hand"][1]
        tdx = cur_frames[i]["target"][0] - cur_frames[i-1]["target"][0]
        tdy = cur_frames[i]["target"][1] - cur_frames[i-1]["target"][1]
        hmag = (hdx*hdx + hdy*hdy)**0.5
        tmag = (tdx*tdx + tdy*tdy)**0.5
        if hmag > 0.002 and tmag > 1:
            ratio = tmag / hmag
            hs = cur_frames[i]["handSide"]
            if hs == "left":
                left_ratios.append(ratio)
            elif hs == "right":
                right_ratios.append(ratio)

    if left_ratios and right_ratios:
        lavg = sum(left_ratios) / len(left_ratios)
        ravg = sum(right_ratios) / len(right_ratios)
        # 对称性 = 1 - |left_avg - right_avg| / max(left_avg, right_avg)
        result["C5-chirality-symmetry"] = (1 - abs(lavg - ravg) / max(lavg, ravg, 1)) * 100
        result["C5-left-ratio"] = lavg
        result["C5-right-ratio"] = ravg
    else:
        result["C5-chirality-symmetry"] = None

    return result


# ============================================================
# Layer 3: 输出质量
# ============================================================
def analyze_layer3(cur_frames):
    if len(cur_frames) < 2:
        return {"note": "数据不足"}

    n = len(cur_frames)
    screen_w, screen_h = 1920, 1080

    # --- 基础指标 ---
    # #1 滤波延迟 (hand→filter距离)
    filter_lags = []
    # #2 T-C滞后 (target→cursor距离)
    tc_gaps = []
    # 步长
    steps = []
    # 静止段
    still_segments = []

    for i, f in enumerate(cur_frames):
        hx, hy = f["hand"]
        tx, ty = f["target"]
        cx, cy = f["cursor"]
        # 滤波延迟直接从 hand - target 推算不够准确, 用 target 位移近似
        # 实际上 replay 和 live 的 filter 值记录方式不同

        gap = ((tx - cx)**2 + (ty - cy)**2)**0.5
        tc_gaps.append(gap)

        if i > 0:
            px, py = cur_frames[i-1]["target"]
            step = ((tx - px)**2 + (ty - py)**2)**0.5
            steps.append(step)

    # 静止段检测: 连续帧 target 位移 < 8px
    still_n = 0
    still_segs = []
    current_seg = []
    for i in range(1, n):
        px, py = cur_frames[i-1]["target"]
        tx, ty = cur_frames[i]["target"]
        step = ((tx - px)**2 + (ty - py)**2)**0.5
        if step < 8:
            current_seg.append(cur_frames[i])
        else:
            if len(current_seg) >= 5:
                still_segs.append(current_seg)
            current_seg = []
    if len(current_seg) >= 5:
        still_segs.append(current_seg)

    # #8 抖动半径, #9 最大偏移
    jitters = []
    excursions = []
    for seg in still_segs:
        if len(seg) < 5:
            continue
        cxs = [f["cursor"][0] for f in seg]
        cys = [f["cursor"][1] for f in seg]
        mx = sum(cxs) / len(cxs)
        my = sum(cys) / len(cys)
        jitter = (sum((x-mx)**2 for x in cxs)/len(cxs) + sum((y-my)**2 for y in cys)/len(cys))**0.5
        jitters.append(jitter)
        exc = ((cxs[-1]-cxs[0])**2 + (cys[-1]-cys[0])**2)**0.5
        excursions.append(exc)

    avg_jitter = sum(jitters) / len(jitters) if jitters else 0
    max_excursion = max(excursions) if excursions else 0

    # #4 方向反转
    reversals = 0
    left_reversals = 0
    right_reversals = 0
    for i in range(2, n):
        px, py = cur_frames[i-2]["target"]
        qx, qy = cur_frames[i-1]["target"]
        tx, ty = cur_frames[i]["target"]
        dx1, dy1 = qx - px, qy - py
        dx2, dy2 = tx - qx, ty - qy
        s1 = (dx1*dx1 + dy1*dy1)**0.5
        s2 = (dx2*dx2 + dy2*dy2)**0.5
        if s1 > 5 and s2 > 5:
            dot = dx1*dx2 + dy1*dy2
            if dot / (s1*s2) < -0.7:
                reversals += 1
                hs = cur_frames[i]["handSide"]
                if hs == "left":
                    left_reversals += 1
                elif hs == "right":
                    right_reversals += 1

    # #5 #6 跳变
    jumps5 = 0
    jumps6 = 0
    for i in range(1, n):
        px, py = cur_frames[i-1]["target"]
        tx, ty = cur_frames[i]["target"]
        step = ((tx - px)**2 + (ty - py)**2)**0.5
        if step > 200:
            jumps5 += 1
        if step > 500:
            jumps6 += 1

    # #10 路径效率
    seg_len = 0
    seg_dx = 0
    seg_dy = 0
    path_effs = []
    seg_n = 0
    for i in range(1, n):
        px, py = cur_frames[i-1]["target"]
        tx, ty = cur_frames[i]["target"]
        step = ((tx - px)**2 + (ty - py)**2)**0.5
        seg_len += step
        seg_dx += tx - px
        seg_dy += ty - py
        seg_n += 1
        if seg_n >= 10:
            straight = (seg_dx*seg_dx + seg_dy*seg_dy)**0.5
            if seg_len > 0 and straight > 30:
                path_effs.append(straight / seg_len)
            seg_len = 0
            seg_dx = 0
            seg_dy = 0
            seg_n = 0
    avg_path_eff = sum(path_effs) / len(path_effs) * 100 if path_effs else 0

    # #12-#14 步长分布
    micro_step = sum(1 for s in steps if s < 50) / len(steps) * 100 if steps else 0
    normal_step = sum(1 for s in steps if 50 <= s < 100) / len(steps) * 100 if steps else 0
    large_step = sum(1 for s in steps if s > 150) / len(steps) * 100 if steps else 0

    # #15-#17 T-C gap 分布
    tight = sum(1 for g in tc_gaps if g < 20) / len(tc_gaps) * 100 if tc_gaps else 0
    good = sum(1 for g in tc_gaps if g < 40) / len(tc_gaps) * 100 if tc_gaps else 0
    severe = sum(1 for g in tc_gaps if g > 120) / len(tc_gaps) * 100 if tc_gaps else 0

    # #18 #19 覆盖率
    txs = [f["target"][0] for f in cur_frames]
    tys = [f["target"][1] for f in cur_frames]
    xcov = (max(txs) - min(txs)) / screen_w * 100 if txs else 0
    ycov = (max(tys) - min(tys)) / screen_h * 100 if tys else 0

    # #19a-d 分向覆盖率（屏幕坐标: y=0顶, y=1080底, x=0左, x=1920右）
    top_gap = min(tys) / screen_h * 100 if tys else 0        # 光标离顶部的距离%
    bottom_gap = (screen_h - max(tys)) / screen_h * 100 if tys else 0  # 光标离底部的距离%
    left_gap = min(txs) / screen_w * 100 if txs else 0
    right_gap = (screen_w - max(txs)) / screen_w * 100 if txs else 0

    # #20 边缘死区 + #20a-d 分向
    edge_hand_dists = []
    edge_dists_top = []
    edge_dists_bottom = []
    edge_dists_left = []
    edge_dists_right = []
    in_edge = False
    edge_hand_total = 0.0

    for i in range(1, n):
        tx, ty = cur_frames[i]["target"]
        hx, hy = cur_frames[i]["hand"]
        px, py = cur_frames[i-1]["target"]
        phx, phy = cur_frames[i-1]["hand"]
        at_edge = tx <= 10 or tx >= screen_w - 10 or ty <= 10 or ty >= screen_h - 10
        prev_at_edge = px <= 10 or px >= screen_w - 10 or py <= 10 or py >= screen_h - 10

        if at_edge and prev_at_edge:
            hdist = ((hx - phx)**2 + (hy - phy)**2)**0.5
            edge_hand_total += hdist
            edge_hand_dists.append(hdist)
            # 分向
            if ty <= 10:
                edge_dists_top.append(hdist)
            if ty >= screen_h - 10:
                edge_dists_bottom.append(hdist)
            if tx <= 10:
                edge_dists_left.append(hdist)
            if tx >= screen_w - 10:
                edge_dists_right.append(hdist)

        if prev_at_edge and not at_edge:
            if edge_hand_total > 0:
                pass  # already accumulated

    # 边缘死区 = 离开边缘时需要的手位移 (归一化)
    edge_dead_zone = sum(edge_hand_dists) / max(len(edge_hand_dists), 1) * 100
    edge_dead_top = sum(edge_dists_top) / max(len(edge_dists_top), 1) * 100 if edge_dists_top else 0
    edge_dead_bottom = sum(edge_dists_bottom) / max(len(edge_dists_bottom), 1) * 100 if edge_dists_bottom else 0
    edge_dead_left = sum(edge_dists_left) / max(len(edge_dists_left), 1) * 100 if edge_dists_left else 0
    edge_dead_right = sum(edge_dists_right) / max(len(edge_dists_right), 1) * 100 if edge_dists_right else 0

    # #21 边缘帧占比
    edge_frames = sum(1 for f in cur_frames
                      if f["target"][0] <= 10 or f["target"][0] >= screen_w - 10
                      or f["target"][1] <= 10 or f["target"][1] >= screen_h - 10)
    edge_pct = edge_frames / n * 100

    # #22 方向错位（手移动但光标不动）— 分左右手
    dir_misalign = 0
    dir_misalign_left = 0
    dir_misalign_right = 0
    dir_misalign_yonly = 0
    edge_total = 0
    for i in range(1, n):
        tx, ty = cur_frames[i]["target"]
        hx, hy = cur_frames[i]["hand"]
        px, py = cur_frames[i-1]["target"]
        phx, phy = cur_frames[i-1]["hand"]
        at_edge = tx <= 10 or tx >= screen_w - 10 or ty <= 10 or ty >= screen_h - 10
        prev_at_edge = px <= 10 or px >= screen_w - 10 or py <= 10 or py >= screen_h - 10

        if at_edge and prev_at_edge:
            edge_total += 1
            hdx = hx - phx
            tdx = tx - px
            tdy = ty - py
            if abs(hdx) > 0.005 and abs(tdx) < 5:
                dir_misalign += 1
                if abs(tdy) > 3:
                    dir_misalign_yonly += 1
                hs = cur_frames[i]["handSide"]
                if hs == "left":
                    dir_misalign_left += 1
                elif hs == "right":
                    dir_misalign_right += 1

    # #23 帧丢失
    frame_drops = 0
    for i in range(1, n):
        step = steps[i-1] if i-1 < len(steps) else 0
        if step > 200:
            frame_drops += 1  # 近似: 大跳变 ≈ 帧丢失导致的跳变

    # T-C lag avg
    avg_tc_lag = sum(tc_gaps) / len(tc_gaps) if tc_gaps else 0
    # Filter lag (approximate: hand→target响应延迟)
    avg_filter_lag = 0
    for i in range(1, n):
        hx, hy = cur_frames[i]["hand"]
        tx, ty = cur_frames[i]["target"]
        # hand→target 距离 / gain → 归一化滞后
        avg_filter_lag += ((hx*1920 - tx)**2 + (hy*1080 - ty)**2)**0.5
    avg_filter_lag = avg_filter_lag / n if n else 0

    return {
        "#1-filter-lag": avg_filter_lag,
        "#2-tc-lag": avg_tc_lag,
        "#3-total-lag": avg_filter_lag + avg_tc_lag,
        "#4-reversals": reversals,
        "#4a-left-reversals": left_reversals,
        "#4b-right-reversals": right_reversals,
        "#5-jumps200": jumps5,
        "#6-jumps500": jumps6,
        "#8-jitter-radius": avg_jitter,
        "#9-max-excursion": max_excursion,
        "#10-path-efficiency": avg_path_eff,
        "#12-micro-step": micro_step,
        "#13-normal-step": normal_step,
        "#14-large-step": large_step,
        "#15-tight": tight,
        "#16-good": good,
        "#17-severe": severe,
        "#18-xcov": xcov,
        "#19-ycov": ycov,
        "#19a-top-cov": top_gap,
        "#19b-bottom-cov": bottom_gap,
        "#19c-left-cov": left_gap,
        "#19d-right-cov": right_gap,
        "#20-edge-dead": edge_dead_zone,
        "#20a-edge-dead-top": edge_dead_top,
        "#20b-edge-dead-bottom": edge_dead_bottom,
        "#20c-edge-dead-left": edge_dead_left,
        "#20d-edge-dead-right": edge_dead_right,
        "#21-edge-pct": edge_pct,
        "#22-dir-misalign": f"{dir_misalign}/{edge_total}",
        "#22a-left-misalign": dir_misalign_left,
        "#22b-right-misalign": dir_misalign_right,
        "#22-yonly": dir_misalign_yonly,
        "#23-frame-drops": frame_drops,
        "frames": n,
    }


# ============================================================
# 综合判定 + 输出
# ============================================================
def judge(l2, l3):
    issues = []
    ok = []

    # Layer 2 判定
    if l2.get("C1-dir-agree-X", 100) < 85:
        issues.append(f"C1 手-光标X方向一致率 {l2['C1-dir-agree-X']:.0f}% (目标>85%)")
    else:
        ok.append(f"C1 {l2.get('C1-dir-agree-X', 0):.0f}%")
    if l2.get("C2-dir-agree-Y", 100) < 85:
        issues.append(f"C2 手-光标Y方向一致率 {l2['C2-dir-agree-Y']:.0f}% (目标>85%)")
    else:
        ok.append(f"C2 {l2.get('C2-dir-agree-Y', 0):.0f}%")

    # 左手一致性 — 关键!
    c3 = l2.get("C3-left-agree-X")
    if c3 is not None and c3 < 70:
        issues.append(f"⚠️ C3 左手方向一致率 {c3:.0f}% — 可能chirality反转!")
    elif c3 is not None:
        ok.append(f"C3左手 {c3:.0f}%")

    c4 = l2.get("C4-right-agree-X")
    if c4 is not None and c4 < 70:
        issues.append(f"⚠️ C4 右手方向一致率 {c4:.0f}% — 可能chirality反转!")
    elif c4 is not None:
        ok.append(f"C4右手 {c4:.0f}%")

    # chirality 对称性
    c5 = l2.get("C5-chirality-symmetry")
    if c5 is not None and c5 < 70:
        issues.append(f"⚠️ C5 chirality对称性 {c5:.0f}% — 左右手不对称!")
    elif c5 is not None:
        ok.append(f"C5对称 {c5:.0f}%")

    # Layer 3 判定
    if l3.get("#3-total-lag", 0) > 220:
        issues.append(f"#3 总滞后 {l3['#3-total-lag']:.0f}px")
    if l3.get("#4-reversals", 0) > B["rev"]:
        issues.append(f"#4 方向反转 {l3['#4-reversals']}次")
    if l3.get("#5-jumps200", 0) > B["jump5"]:
        issues.append(f"#5 大跳变 {l3['#5-jumps200']}次")
    if l3.get("#6-jumps500", 0) > B["jump6"]:
        issues.append(f"#6 巨型跳变 {l3['#6-jumps500']}次")
    if l3.get("#20-edge-dead", 0) > 8:
        issues.append(f"#20 边缘死区 {l3['#20-edge-dead']:.1f}% (目标<8%)")

    # 分向死区判定
    for edge, name in [("top", "上"), ("bottom", "下"), ("left", "左"), ("right", "右")]:
        val = l3.get(f"#20a-edge-dead-{edge}", 0)
        if val > 10:
            issues.append(f"#20{chr(ord('a')+['top','bottom','left','right'].index(edge))} {name}边缘死区 {val:.1f}%")

    return issues, ok


def print_report(l1, l2, l3, path):
    issues, ok = judge(l2, l3)

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  MotionControl 光标质量分析 v5.0 — 三层数据体系")
    print(f"  日志: {path}")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # ── 综合判定 ──
    if issues:
        print(f"\n┌──────────────────────────────────────────────────────┐")
        print(f"│  ⚠️ {len(issues)}项问题   {len(ok)}项正常                              │")
        for iss in issues:
            print(f"│  • {iss}")
        print(f"└──────────────────────────────────────────────────────┘")
    else:
        print(f"\n┌──────────────────────────────────────────────────────┐")
        print(f"│  ✅ 全部 {len(ok)}项达标                                         │")
        print(f"└──────────────────────────────────────────────────────┘")

    # ── Layer 1 ──
    print("\n━━━ Layer 1: 原始数据质量 ━━━")
    if "note" in l1:
        print(f"  ⚠️ {l1['note']}")
    else:
        print(f"  关键点检测率:")
        pts = ["wrist", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]
        for pt in pts:
            det = l1.get(f"K-{pt}-detection", 0)
            jit = l1.get(f"K-{pt}-jitter", 0)
            bar = "█" * int(det / 5) + "░" * (20 - int(det / 5))
            print(f"    {pt:<12} 检测率 {det:5.1f}% {bar}  抖动 {jit:4.1f}px")
        print(f"  handSide已知率: {l1.get('K-handSide-known', 0):.0f}%")
        print(f"  左手占比: {l1.get('K-left-pct', 0):.0f}%  右手占比: {l1.get('K-right-pct', 0):.0f}%")
        print(f"  wrist底部检测率(y>0.8): {l1.get('K-wrist-bottom-det', 0):.1f}%")

    # ── Layer 2 ──
    print("\n━━━ Layer 2: 算法一致性 ━━━")
    if "note" in l2:
        print(f"  ⚠️ {l2['note']}")
    else:
        c1 = l2.get("C1-dir-agree-X", 0)
        c2 = l2.get("C2-dir-agree-Y", 0)
        c3 = l2.get("C3-left-agree-X")
        c4 = l2.get("C4-right-agree-X")
        c5 = l2.get("C5-chirality-symmetry")

        def status(v, t): return "✅" if v and v >= t else "⚠️" if v else "—"
        print(f"  C1  手→光标 X方向一致:  {c1:5.1f}% {status(c1,85)} (目标>85%)")
        print(f"  C2  手→光标 Y方向一致:  {c2:5.1f}% {status(c2,85)} (目标>85%)")
        if c3 is not None:
            print(f"  C3  左手 X方向一致:     {c3:5.1f}% {status(c3,70)} (n={l2.get('C3-left-frames',0)})  ⚠️<70%=反转")
        if c4 is not None:
            print(f"  C4  右手 X方向一致:     {c4:5.1f}% {status(c4,70)} (n={l2.get('C4-right-frames',0)})")
        if c5 is not None:
            print(f"  C5  chirality对称性:    {c5:5.1f}% {status(c5,70)} (L={l2.get('C5-left-ratio',0):.0f} R={l2.get('C5-right-ratio',0):.0f})")

    # ── Layer 3 ──
    print("\n━━━ Layer 3: 输出质量 ━━━")
    if "note" in l3:
        print(f"  ⚠️ {l3['note']}")
    else:
        # 核心指标
        rows = [
            ("#1  滤波延迟", "px", "#1-filter-lag", 180, "<"),
            ("#2  T-C滞后", "px", "#2-tc-lag", 40, "<"),
            ("#3  总滞后", "px", "#3-total-lag", 220, "<"),
            ("#4  方向反转", "次", "#4-reversals", B["rev"], "<"),
            ("#4a  左手方向反转", "次", "#4a-left-reversals", None, None),
            ("#4b  右手方向反转", "次", "#4b-right-reversals", None, None),
            ("#5  大跳变>200px", "次", "#5-jumps200", B["jump5"], "<"),
            ("#6  巨型跳变>500px", "次", "#6-jumps500", B["jump6"], "<"),
            ("#8  抖动半径", "px", "#8-jitter-radius", 8, "<"),
            ("#9  最大偏移", "px", "#9-max-excursion", 35, "<"),
            ("#10 路径效率", "%", "#10-path-efficiency", 85, ">"),
            ("#12 微步0-50px", "%", "#12-micro-step", 70, ">"),
            ("#13 正常50-100px", "%", "#13-normal-step", None, None),
            ("#14 大步>150px", "%", "#14-large-step", 3, "<"),
            ("#15 紧贴0-20px", "%", "#15-tight", 45, ">"),
            ("#16 良好0-40px", "%", "#16-good", 60, ">"),
            ("#17 严重>120px", "%", "#17-severe", 3, "<"),
        ]
        for label, unit, key, target, direction in rows:
            val = l3.get(key, 0)
            if isinstance(val, float):
                s = f"  {label:<18} {val:6.1f} {unit}"
            else:
                s = f"  {label:<18} {val:>6} {unit}"
            if target is not None:
                if direction == "<":
                    ok_flag = val < target if isinstance(val, (int, float)) else True
                else:
                    ok_flag = val > target if isinstance(val, (int, float)) else True
                s += f"  {'✅' if ok_flag else '⚠️'} (目标{direction}{target})"
            print(s)

        # 覆盖率
        print("\n  ── 覆盖率 ──")
        for key, label in [("xcov", "X"), ("ycov", "Y"), ("top-cov", "顶部未达"),
                           ("bottom-cov", "底部未达"), ("left-cov", "左侧未达"), ("right-cov", "右侧未达")]:
            val = l3.get(f"#18-{key}" if key in ("xcov", "ycov") else f"#19a-{key}" if "a" not in key else f"#19{chr(ord('a')+['top-cov','bottom-cov','left-cov','right-cov'].index(key))}-{key}", 0)
            # Fix keys
            pass

        # 简化输出覆盖率
        xc = l3.get("#18-xcov", 0)
        yc = l3.get("#19-ycov", 0)
        tc = l3.get("#19a-top-cov", 0)
        bc = l3.get("#19b-bottom-cov", 0)
        lc = l3.get("#19c-left-cov", 0)
        rc = l3.get("#19d-right-cov", 0)
        print(f"  #18 X覆盖率: {xc:5.0f}% (目标100%)  {'✅' if xc >= 95 else '⚠️'}")
        print(f"  #19 Y覆盖率: {yc:5.0f}% (目标100%)  {'✅' if yc >= 95 else '⚠️'}")
        print(f"  #19a 顶部未达: {tc:4.0f}%  #19b 底部未达: {bc:4.0f}%")
        print(f"  #19c 左侧未达: {lc:4.0f}%  #19d 右侧未达: {rc:4.0f}%")

        # 边缘质量
        print("\n  ── 边缘质量 ──")
        ed = l3.get("#20-edge-dead", 0)
        print(f"  #20 边缘死区: {ed:5.1f}% (目标<8%)  {'✅' if ed < 8 else '⚠️'}")
        et = l3.get("#20a-edge-dead-top", 0)
        eb = l3.get("#20b-edge-dead-bottom", 0)
        el = l3.get("#20c-edge-dead-left", 0)
        er = l3.get("#20d-edge-dead-right", 0)
        print(f"  #20a-d 分向: 上{et:4.1f}%  下{eb:4.1f}%  左{el:4.1f}%  右{er:4.1f}%")
        ep = l3.get("#21-edge-pct", 0)
        print(f"  #21 边缘帧占比: {ep:4.1f}% (目标<15%)  {'✅' if ep < 15 else '⚠️'}")
        dm = l3.get("#22-dir-misalign", "0/0")
        dml = l3.get("#22a-left-misalign", 0)
        dmr = l3.get("#22b-right-misalign", 0)
        print(f"  #22 方向错位: {dm}  左手:{dml}  右手:{dmr}  (目标<20)")

    # ── 问题检测报告 ──
    print("\n━━━ 问题检测报告 ━━━")
    detected = []

    # 问题1: 手腕影响底部
    bc = l3.get("#19b-bottom-cov", 0)
    eb_val = l3.get("#20b-edge-dead-bottom", 0)
    wrist_det = l1.get("K-wrist-detection", 0) if "note" not in l1 else None
    if bc > 20 or eb_val > 10:
        detected.append(
            f"🔴 问题1 检测到: 底部触达受限 (底部未达{bc:.0f}%, 下边缘死区{eb_val:.1f}%)"
            + (f" | 根因: wrist检测率{wrist_det:.0f}%" if wrist_det and wrist_det < 90 else "")
        )
    elif wrist_det and wrist_det < 80:
        detected.append(
            f"🟡 问题1 预警: wrist检测率仅{wrist_det:.0f}%，可能影响底部触达"
        )

    # 问题2: 左手方向
    c3 = l2.get("C3-left-agree-X")
    if c3 is not None and c3 < 70:
        detected.append(
            f"🔴 问题2 检测到: 左手方向可能反转! C3一致率仅{c3:.0f}%"
            + (f", 左手反转{l3.get('#4a-left-reversals',0)}次" if l3.get("#4a-left-reversals", 0) > 0 else "")
        )
    elif c3 is not None and c3 < 85:
        detected.append(f"🟡 问题2 预警: 左手一致率{c3:.0f}%偏低")
    elif c3 is not None:
        detected.append(f"🟢 问题2 未检测到: 左手一致率{c3:.0f}%正常")

    # 问题3: 边缘粘连
    ed_val = l3.get("#20-edge-dead", 0)
    ep_val = l3.get("#21-edge-pct", 0)
    if ed_val > 10:
        edges = []
        if l3.get("#20a-edge-dead-top", 0) > 10: edges.append("上")
        if l3.get("#20b-edge-dead-bottom", 0) > 10: edges.append("下")
        if l3.get("#20c-edge-dead-left", 0) > 10: edges.append("左")
        if l3.get("#20d-edge-dead-right", 0) > 10: edges.append("右")
        detected.append(
            f"🔴 问题3 检测到: 边缘粘连 (死区{ed_val:.1f}%, 帧占比{ep_val:.1f}%)"
            + (f" | 粘连边: {','.join(edges)}" if edges else "")
        )
    else:
        detected.append(f"🟢 问题3 未检测到: 边缘死区{ed_val:.1f}%达标")

    for d in detected:
        print(f"  {d}")

    print(f"\n  总帧数: {l3.get('frames', 0)}")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("log", nargs="?", default=LOG)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--replay", action="store_true")
    args = parser.parse_args()

    log_path = args.log
    print(f"解析日志: {log_path} ...", file=sys.stderr)
    kp_frames, cur_frames = parse_log(log_path)
    print(f"  [KEYPOINTS] {len(kp_frames)}  [CURSOR-ABS] {len(cur_frames)}", file=sys.stderr)

    l1 = analyze_layer1(kp_frames)
    l2 = analyze_layer2(cur_frames)
    l3 = analyze_layer3(cur_frames)

    if args.json:
        # PECF 桥接: 输出全部指标为 current_run.json 格式
        def r(v, default=0): return round(v, 1) if v is not None else default
        result = {}

        # ── L2: 算法一致性 (7项) ──
        result["dir_agree_x"] = r(l2.get("C1-dir-agree-X", 0))
        result["dir_agree_y"] = r(l2.get("C2-dir-agree-Y", 0))
        result["left_dir_agree"] = r(l2.get("C3-left-agree-X")) if l2.get("C3-left-agree-X") is not None else None
        result["right_dir_agree"] = r(l2.get("C4-right-agree-X")) if l2.get("C4-right-agree-X") is not None else None
        result["chirality_symmetry"] = r(l2.get("C5-chirality-symmetry", None), default=None) or 100.0

        # ── L3: 输出质量 ──
        # 延迟
        result["filter_lag"] = r(l3.get("#1-filter-lag", 0))
        result["tc_lag"] = r(l3.get("#2-tc-lag", 0))
        result["total_lag"] = r(l3.get("#3-total-lag", 0))
        # 方向反转
        result["reversals"] = r(l3.get("#4-reversals", 0))
        result["left_reversals"] = r(l3.get("#4a-left-reversals", 0))
        result["right_reversals"] = r(l3.get("#4b-right-reversals", 0))
        # 跳变
        result["jumps200"] = r(l3.get("#5-jumps200", 0))
        result["jumps500"] = r(l3.get("#6-jumps500", 0))
        # 稳定性
        result["jitter_radius"] = r(l3.get("#8-jitter-radius", 0))
        result["max_excursion"] = r(l3.get("#9-max-excursion", 0))
        # 路径效率
        result["path_efficiency"] = r(l3.get("#10-path-efficiency", 0))
        # 步长分布
        result["micro_step"] = r(l3.get("#12-micro-step", 0))
        result["normal_step"] = r(l3.get("#13-normal-step", 0))
        result["large_step"] = r(l3.get("#14-large-step", 0))
        # T-C 分布
        result["tc_tight"] = r(l3.get("#15-tight", 0))
        result["tc_good"] = r(l3.get("#16-good", 0))
        result["tc_severe"] = r(l3.get("#17-severe", 0))
        # 覆盖率
        result["x_coverage"] = r(l3.get("#18-xcov", 0))
        result["y_coverage"] = r(l3.get("#19-ycov", 0))
        result["top_coverage_gap"] = r(l3.get("#19a-top-cov", 0))
        result["bottom_coverage_gap"] = r(l3.get("#19b-bottom-cov", 0))
        result["left_coverage_gap"] = r(l3.get("#19c-left-cov", 0))
        result["right_coverage_gap"] = r(l3.get("#19d-right-cov", 0))
        # 边缘质量
        result["edge_dead_zone"] = r(l3.get("#20-edge-dead", 0))
        result["edge_frame_pct"] = r(l3.get("#21-edge-pct", 0))
        # 方向错位
        dm = l3.get("#22-dir-misalign", "0/0")
        dm_num = int(str(dm).split("/")[0]) if "/" in str(dm) else 0
        result["dir_misalign"] = dm_num
        result["left_misalign"] = r(l3.get("#22a-left-misalign", 0))
        result["right_misalign"] = r(l3.get("#22b-right-misalign", 0))
        result["yonly_misalign"] = r(l3.get("#22-yonly", 0))
        # 帧丢失
        result["frame_drops"] = r(l3.get("#23-frame-drops", 0))

        # 元数据 + Layer 1
        result["frames"] = int(r(l2.get("C-all-frames", len(cur_frames))))
        result["keypoints"] = len(kp_frames)
        kp_detections = []
        for pt in ["wrist", "indexMCP", "middleMCP", "ringMCP", "littleMCP"]:
            kp_detections.append({"joint": pt, "detection": r(l1.get(f"K-{pt}-detection", 0)), "jitter": r(l1.get(f"K-{pt}-jitter", 0))})
        result["kp_detections"] = kp_detections
        result["handside_known"] = r(l1.get("K-handSide-known", 0))
        result["left_pct"] = r(l1.get("K-left-pct", 0))
        result["right_pct"] = r(l1.get("K-right-pct", 0))
        result["wrist_bottom_det"] = r(l1.get("K-wrist-bottom-det", 0))
        # 边缘死区分向
        result["edge_dead_top"] = r(l3.get("#20a-edge-dead-top", 0))
        result["edge_dead_bottom"] = r(l3.get("#20b-edge-dead-bottom", 0))
        result["edge_dead_left"] = r(l3.get("#20c-edge-dead-left", 0))
        result["edge_dead_right"] = r(l3.get("#20d-edge-dead-right", 0))
        # 问题检测
        problems = []
        c1 = l2.get("C1-dir-agree-X", 0)
        if c1 and c1 < 85: problems.append({"level": "🟡", "no": "C1", "desc": f"X方向一致率 {c1:.0f}% (目标>85%)"})
        c2 = l2.get("C2-dir-agree-Y", 0)
        if c2 and c2 < 85: problems.append({"level": "🟡", "no": "C2", "desc": f"Y方向一致率 {c2:.0f}% (目标>85%)"})
        c5 = l2.get("C5-chirality-symmetry", 100)
        if c5 and c5 < 75: problems.append({"level": "🔴", "no": "C5", "desc": f"chirality对称性 {c5:.0f}% — 左右手不对称"})
        edz = l3.get("#20-edge-dead", 0)
        if edz and edz > 8: problems.append({"level": "🔴", "no": "#20", "desc": f"边缘死区 {edz:.1f}% (目标<8%)"})
        j5 = l3.get("#5-jumps200", 0)
        if j5 and j5 > 11: problems.append({"level": "🟡", "no": "#5", "desc": f"大跳变 {int(j5)}次 (目标<11)"})
        j6 = l3.get("#6-jumps500", 0)
        if j6 and j6 > 5: problems.append({"level": "🔴", "no": "#6", "desc": f"巨型跳变 {int(j6)}次 (目标<5)"})
        result["problems"] = problems

        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print_report(l1, l2, l3, log_path)
