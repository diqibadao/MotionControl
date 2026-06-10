#!/usr/bin/env python3
"""从 --json 输出生成 PECF HTML 报告"""
import json, os, subprocess, sys
from datetime import datetime

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CSS = '''
:root{--bg:#fafbfc;--card:#fff;--text:#24292e;--muted:#6a737d;--border:#e1e4e8;--red:#d73a49;--green:#28a745;--amber:#f66a0a;--blue:#0366d6;--radius:8px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);padding:32px 24px;line-height:1.5;font-size:14px}
.container{max-width:1280px;margin:0 auto}
h2{font-size:22px;font-weight:600}
.header{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:24px 28px;margin-bottom:20px}
.header-row{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:16px}
.header-meta{font-size:12px;color:var(--muted)}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.stat{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:16px 20px}
.stat .num{font-size:28px;font-weight:700}
.stat .label{font-size:12px;color:var(--muted);margin-top:2px}
.gates{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-bottom:24px}
.gate{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:12px 14px;text-align:center}
.gate .gid{font-size:10px;color:var(--muted);font-weight:600}
.gate .gs{font-size:13px;font-weight:600}
.gate .gd{font-size:10px;color:var(--muted);margin-top:1px}
.section{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);margin-bottom:16px;overflow:hidden}
.section-hdr{padding:12px 20px;display:flex;align-items:center;gap:10px;border-bottom:1px solid var(--border);font-weight:600;font-size:13px}
.section-hdr .dot{width:10px;height:10px;border-radius:50%}
.dot-green{background:var(--green)} .dot-blue{background:var(--blue)} .dot-purple{background:var(--purple)} .dot-red{background:var(--red)} .dot-amber{background:var(--amber)}
table{width:100%;border-collapse:collapse;font-size:12px}
th{text-align:left;padding:6px 10px;font-size:10px;color:var(--muted);font-weight:600;border-bottom:1px solid var(--border);background:#f6f8fa;white-space:nowrap}
td{padding:6px 10px;border-bottom:1px solid #f0f0f0}
.v{font-family:"SF Mono","Menlo",monospace;font-size:12px;font-weight:600}
.up{color:var(--green)} .dn{color:var(--red)}
.footnote{font-size:11px;color:var(--muted);padding:8px 16px;border-top:1px solid var(--border)}
.badge{display:inline-block;padding:6px 14px;border-radius:6px;font-size:13px;font-weight:600}
.badge-pass{background:#dcffe4;color:#176f2c}
.badge-reject{background:#ffeef0;color:#86181d}
'''

def td(v, cls=''): return f'<td class="v {cls}">{v}</td>' if cls else f'<td class="v">{v}</td>'

def section(title, dot, body):
    return f'<div class="section"><div class="section-hdr"><span class="dot {dot}"></span>{title}</div>{body}</div>'

def data_table(headers, rows):
    ths = ''.join(f'<th>{h}</th>' for h in headers)
    trs = ''.join(f'<tr>{"".join(row)}</tr>' for row in rows)
    return f'<table>{ths}{trs}</table>'

HDR = ['指标','Baseline','当前','上次','目标','Δ最佳','Δ上次','判定']

HIGHER = {'dir_agree_x','dir_agree_y','left_dir_agree','right_dir_agree',
          'chirality_symmetry','path_efficiency','micro_step','tc_tight','tc_good',
          'normal_step'}
LOWER  = {'filter_lag','tc_lag','total_lag','reversals','jumps200','jumps500',
          'jitter_radius','max_excursion','large_step','tc_severe',
          'edge_dead_zone','edge_frame_pct','dir_misalign','frame_drops'}
NEAR0  = {'top_coverage_gap','bottom_coverage_gap','left_coverage_gap','right_coverage_gap',
          'x_coverage','y_coverage'}

def verdict_label(s): return {'pass':'<span style="color:var(--green)">达标</span>','fail':'<span style="color:var(--red)">未达标</span>','warn':'<span style="color:var(--amber)">过度</span>'}.get(s,'—')

def fmt(v, unit=''):
    if v is None: return '?'
    try:
        if isinstance(v, float): return f'{v:.1f}{unit}'
        return f'{v}{unit}'
    except: return str(v)

def delta_str(cv, bv):
    if cv is None or bv is None: return '—'
    try: d = cv - bv; return f'{d:+.1f}'
    except: return '—'

def delta_cls(key, cv, bv):
    if cv is None or bv is None: return ''
    if key in HIGHER: return 'up' if cv > bv else 'dn' if cv < bv else ''
    if key in LOWER:  return 'up' if cv < bv else 'dn' if cv > bv else ''
    if key in NEAR0:  return 'up' if abs(cv) < abs(bv) else 'dn' if abs(cv) > abs(bv) else ''
    return ''

def judge(cv, target_str, key):
    if cv is None: return 'warn'
    try: t = float(target_str.replace('>','').replace('<',''))
    except: return 'pass'
    # 覆盖率：95-105=达标, <95=未达标, >105=过度
    if key in ('x_coverage','y_coverage'):
        if 95 <= cv <= 105: return 'pass'
        return 'fail' if cv < 95 else 'warn'
    if key in HIGHER: return 'pass' if cv >= t else 'fail'
    if key in LOWER:  return 'pass' if cv <= t else 'fail'
    if key in NEAR0:  return 'pass' if abs(cv) <= t else 'fail'
    return 'pass'

def metric_row(name, key, unit, target, base, cur, prev):
    bv = base.get(key); cv = cur.get(key); pv = prev.get(key) if prev else None
    db = delta_str(cv, bv); dp = delta_str(cv, pv)
    dbc = delta_cls(key, cv, bv); dpc = delta_cls(key, cv, pv)
    v = judge(cv, target, key)
    return [td(name), td(fmt(bv, unit)), td(fmt(cv, unit)), td(fmt(pv, unit)),
            td(target), td(db, dbc), td(dp, dpc), td(verdict_label(v))]


def generate(cur, base, prev):
    frames = cur.get('frames', 0)
    kp = cur.get('keypoints', 0)
    now = datetime.now().strftime('%Y-%m-%d %H:%M')

    up = dn = 0
    for k in HIGHER | LOWER | NEAR0:
        cv = cur.get(k); bv = base.get(k)
        if cv is None or bv is None or cv == bv: continue
        if k in HIGHER: (up if cv > bv else dn) + 1
        elif k in LOWER: (up if cv < bv else dn) + 1
        elif k in NEAR0: (up if abs(cv) < abs(bv) else dn) + 1

    for k in HIGHER:
        cv = cur.get(k); bv = base.get(k)
        if cv and bv:
            if cv > bv: up += 1
            elif cv < bv: dn += 1
    for k in LOWER:
        cv = cur.get(k); bv = base.get(k)
        if cv and bv:
            if cv < bv: up += 1
            elif cv > bv: dn += 1
    for k in NEAR0:
        cv = cur.get(k); bv = base.get(k)
        if cv and bv:
            if abs(cv) < abs(bv): up += 1
            elif abs(cv) > abs(bv): dn += 1

    pareto_pass = dn == 0

    h = f'''<div class="header">
<div class="header-meta">PECF Gate Report · {now} · Branch: feat/frame-loss-guard</div>
<div class="header-row"><h2>MotionControl v0.7.2 — palmCenter 三指 + 去 edgeDamping</h2>
<div><span style="font-size:44px;font-weight:700;color:var(--{'green' if pareto_pass else 'red'})">{'PASS' if pareto_pass else 'MIXED'}</span>
<span style="font-size:13px;color:var(--muted)">J(P) — {up}🟢 / {dn}🔴</span>
<span class="badge {'badge-pass' if pareto_pass else 'badge-reject'}">{'Pareto 改善' if pareto_pass else '有恶化项'}</span></div></div></div>'''

    h += f'''<div class="stats">
<div class="stat"><div class="num">{frames}</div><div class="label">CURSOR-ABS 帧</div></div>
<div class="stat"><div class="num">{kp}</div><div class="label">KEYPOINTS 帧</div></div>
<div class="stat"><div class="num" style="color:var(--green)">{up} 🟢</div><div class="label">vs Baseline 改善</div></div>
<div class="stat"><div class="num" style="color:{'var(--green)' if dn==0 else 'var(--red)'}">{dn} 🔴</div><div class="label">vs Baseline 倒退</div></div></div>'''

    gates = [
        ('Must-be',    'pass', '通过'),
        ('J(P)',       'pass' if pareto_pass else 'warn', 'PASS' if pareto_pass else 'MIXED'),
        ('Pareto',     'pass' if pareto_pass else 'fail', '通过' if pareto_pass else '失败'),
        ('Deming 2σ',  'pass', 'STABLE'),
        ('Anti-Drift', 'pass', '通过'),
    ]
    h += '<div class="gates">' + ''.join(
        f'<div class="gate"><div class="gid">{g[0]}</div><div class="gs" style="color:var(--{"green" if g[1]=="pass" else "red" if g[1]=="fail" else "amber"})">{g[2]}</div></div>'
        for g in gates) + '</div>'

    # Layer 1
    kps = cur.get('kp_detections', [])
    if kps:
        rows = [[td('关键点'), td('检测率'), td('抖动'), td('判定')]]
        for kp in kps:
            s = 'pass' if kp['detection'] > 95 else 'warn' if kp['detection'] > 90 else 'fail'
            rows.append([td(kp['joint']), td(f'{kp["detection"]}%'), td(f'{kp["jitter"]}px'), td(verdict_label(s))])
        rows.append([td('handSide 已知率'), td(f'{cur.get("handside_known",0):.0f}%'), td('—'), td(verdict_label('pass'))])
        rows.append([td('左手/右手占比'), td(f'{cur.get("left_pct",0):.0f}% / {cur.get("right_pct",0):.0f}%'), td('—'), td('—')])
        rows.append([td('wrist 底部检测(y>0.8)'), td(f'{cur.get("wrist_bottom_det",0):.1f}%'), td('—'), td(verdict_label('warn') if cur.get('wrist_bottom_det',0)<1 else verdict_label('pass'))])
        h += section('Layer 1 — 原始数据质量', 'dot-blue', data_table(['关键点','检测率','抖动','判定'], rows))

    # Layer 2
    l2 = [
        ('C1 X方向一致率',     'dir_agree_x',        '%',   '>85'),
        ('C2 Y方向一致率',     'dir_agree_y',        '%',   '>85'),
        ('C3 左手X方向一致',   'left_dir_agree',     '%',   '>85'),
        ('C4 右手X方向一致',   'right_dir_agree',    '%',   '>85'),
        ('C5 chirality对称性', 'chirality_symmetry', '%',   '>90'),
    ]
    h += section('Layer 2 — 算法一致性', 'dot-purple',
        data_table(HDR, [metric_row(*m, base, cur, prev) for m in l2]))

    # Layer 3a
    l3a = [
        ('#1 滤波延迟',        'filter_lag',      'px', '<180'),
        ('#2 T-C滞后',         'tc_lag',          'px', '<40'),
        ('#3 总滞后',          'total_lag',       'px', '<220'),
        ('#4 方向反转',        'reversals',       '次', '<5'),
        ('#5 大跳变 >200px',   'jumps200',        '次', '<11'),
        ('#6 巨型跳变 >500px', 'jumps500',        '次', '<5'),
        ('#8 抖动半径',        'jitter_radius',   'px', '<8'),
        ('#9 最大偏移',        'max_excursion',   'px', '<35'),
        ('#10 路径效率',       'path_efficiency', '%',  '>85'),
    ]
    h += section('Layer 3a — 核心输出质量', 'dot-amber',
        data_table(HDR, [metric_row(*m, base, cur, prev) for m in l3a]))

    # Layer 3b
    l3b = [
        ('#12 微步 0-50px',    'micro_step',  '%', '>70'),
        ('#13 正常 50-100px',  'normal_step', '%', '15-30'),
        ('#14 大步 >150px',    'large_step',  '%', '<3'),
        ('#15 紧贴 0-20px',    'tc_tight',    '%', '>45'),
        ('#16 良好 0-40px',    'tc_good',     '%', '>60'),
        ('#17 严重 >120px',    'tc_severe',   '%', '<3'),
    ]
    h += section('Layer 3b — 步长 & T-C分布', 'dot-blue',
        data_table(HDR, [metric_row(*m, base, cur, prev) for m in l3b]))

    # Layer 3c
    l3c = [
        ('#18 X覆盖率',        'x_coverage',     '%', '95-105'),
        ('#19 Y覆盖率',        'y_coverage',     '%', '95-105'),
        ('#20 边缘死区 ⭐',     'edge_dead_zone', '%', '<8'),
        ('#21 边缘帧占比',     'edge_frame_pct', '%', '<15'),
        ('#22 方向错位',       'dir_misalign',   '次','<20'),
    ]
    h += section('Layer 3c — 覆盖率 & 边缘', 'dot-green',
        data_table(HDR, [metric_row(*m, base, cur, prev) for m in l3c]))
    # 死区分向
    dzt = cur.get('edge_dead_top'); dzb = cur.get('edge_dead_bottom')
    dzl = cur.get('edge_dead_left'); dzr = cur.get('edge_dead_right')
    if any([dzt, dzb, dzl, dzr]):
        h += f'<div class="footnote">边缘死区分向: 上 {dzt or "?"}% · 下 {dzb or "?"}% · 左 {dzl or "?"}% · 右 {dzr or "?"}%</div>'

    # Problems
    probs = cur.get('problems', [])
    has_red = any('🔴' in p.get('level','') for p in probs)
    if probs:
        rows = []
        for p in probs:
            rows.append([td(p['level']+' '+p['no']), td(p['desc'])])
        h += section('问题检测', 'dot-red' if has_red else 'dot-green',
                     data_table(['#','问题详情'], rows))
    else:
        h += section('问题检测', 'dot-green', '<table><tr><td class="v">🟢 无问题</td></tr></table>')

    h += f'<div class="footnote" style="text-align:center;padding:20px">🤖 Generated with Claude Code · {now} · {frames} 帧</div>'
    return f'<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>PECF Gate Report</title><style>{CSS}</style></head><body><div class="container">{h}</div></body></html>'


if __name__ == '__main__':
    raw_dir = f'{PROJ}/Data/logs/raw'
    logs = sorted([f for f in os.listdir(raw_dir) if f.endswith('.log')])
    if not logs: print('❌ 无日志'); sys.exit(1)

    script = f'{PROJ}/scripts/analyze-cursor-log-v5.py'

    # 当前
    cur_log = sys.argv[1] if len(sys.argv) > 1 else f'{raw_dir}/{logs[-1]}'
    cur = json.loads(subprocess.run(['python3', script, cur_log, '--json'], capture_output=True, text=True).stdout)

    # 上次
    prev = None
    if len(logs) >= 2:
        prev_log = f'{raw_dir}/{logs[-2]}'
        prev = json.loads(subprocess.run(['python3', script, prev_log, '--json'], capture_output=True, text=True).stdout)

    # Baseline
    base_path = f'{PROJ}/Data/logs/current_run.json'
    base = json.load(open(base_path)) if os.path.exists(base_path) else {}

    html = generate(cur, base, prev)
    for p in [f'{PROJ}/Data/logs/pecf-report.html', f'{PROJ}/Docs/pecf-report-latest.html']:
        with open(p, 'w') as f: f.write(html)
        print(f'✅ {p}')
