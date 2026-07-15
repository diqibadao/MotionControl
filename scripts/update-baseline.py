#!/usr/bin/env python3
"""从 --json 输出更新 current_run.json（保留各指标历史最优值）"""
import json, os, subprocess, sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HIGHER = {'dir_agree_x','dir_agree_y','left_dir_agree','right_dir_agree',
          'chirality_symmetry','path_efficiency','micro_step','tc_tight','tc_good',
          'normal_step'}
LOWER  = {'filter_lag','tc_lag','total_lag','reversals','jumps200','jumps500',
          'jitter_radius','max_excursion','large_step','tc_severe',
          'edge_dead_zone','edge_frame_pct','dir_misalign','frame_drops'}
NEAR0  = {'top_coverage_gap','bottom_coverage_gap','left_coverage_gap','right_coverage_gap',
          'x_coverage','y_coverage'}
SKIP   = {'frames','keypoints','kp_detections','problems','left_reversals','right_reversals',
          'left_misalign','right_misalign','yonly_misalign','handside_known','left_pct',
          'right_pct','wrist_bottom_det','edge_dead_top','edge_dead_bottom',
          'edge_dead_left','edge_dead_right'}

if __name__ == '__main__':
    raw_dir = f'{PROJ}/Data/logs/raw'
    logs = sorted([f for f in os.listdir(raw_dir) if f.endswith('.log')])
    log_file = sys.argv[1] if len(sys.argv) > 1 else (f'{raw_dir}/{logs[-1]}' if logs else None)
    if not log_file: print('❌ 无日志'); sys.exit(1)

    script = f'{PROJ}/scripts/analyze-cursor-log-v5.py'
    new = json.loads(subprocess.run(['python3', script, log_file, '--json'], capture_output=True, text=True).stdout)
    print(f'📊 {new.get("frames",0)} 帧, {new.get("keypoints",0)} KP')

    base_path = f'{PROJ}/Data/logs/current_run.json'
    old = json.load(open(base_path)) if os.path.exists(base_path) else {}

    merged = {}
    changes = []
    for k in sorted(set(list(old.keys()) + list(new.keys()))):
        if k in SKIP: continue
        ov = old.get(k); nv = new.get(k)
        if ov is None: merged[k] = nv; continue
        if nv is None or nv == ov: merged[k] = ov; continue

        if k in HIGHER and nv > ov: merged[k] = nv; changes.append(f'{k}: {ov}→{nv} ↑')
        elif k in LOWER and nv < ov: merged[k] = nv; changes.append(f'{k}: {ov}→{nv} ↓')
        elif k in NEAR0 and abs(nv) < abs(ov): merged[k] = nv; changes.append(f'{k}: {ov}→{nv}')
        else: merged[k] = ov

    for k in new:
        if k in SKIP and k not in merged:
            merged[k] = new[k]

    print(f'🟢 {len(changes)} 项刷新:')
    for c in changes: print(f'  {c}')

    with open(base_path, 'w') as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)

    history_path = f'{PROJ}/Data/baselines/history.jsonl'
    new['_date'] = log_file.split('run_')[1].replace('.log','') if 'run_' in log_file else ''
    with open(history_path, 'a') as f:
        f.write(json.dumps(new, ensure_ascii=False) + '\n')

    print(f'✅ baseline ({len(merged)}项) + history')
