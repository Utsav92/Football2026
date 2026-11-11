#!/usr/bin/env python3
"""Team-shape analytics on normalised tracking (real or simulated). Standard library only.

  python3 Tools/analyze_formations.py Datasets/tracking/skillcorner_1925299.json.gz            -> Datasets/processed/tactical_priors_skillcorner_1925299.json
  python3 Tools/analyze_formations.py Datasets/synthetic/sim_tracking.json.gz --compare Datasets/processed/tactical_priors_skillcorner_1925299.json

Per team-frame (attack-normalised so every team attacks +x; keeper removed as the deepest player):
  defensive line (mean x of 4 deepest outfielders), centroid, length/width (10th-90th pct spread), convex-hull area,
  mean nearest-teammate spacing, line gaps. Aggregated by possession state and ball zone; plus linear fits of team shape vs ball x.
Formation reconstruction: 1-D k-means (k=3) of outfield x per 12 s window, modal string."""
import gzip, json, math, os, sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROC = os.path.join(ROOT, 'Datasets', 'processed')

def hull_area(pts):
    pts = sorted(set(pts))
    if len(pts) < 3: return 0.0
    def cross(o, a, b): return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    h = lo[:-1] + up[:-1]
    return abs(sum(h[i][0]*h[(i+1) % len(h)][1] - h[(i+1) % len(h)][0]*h[i][1] for i in range(len(h)))) / 2

def pct(v, q):
    v = sorted(v); i = q * (len(v) - 1); lo = int(math.floor(i)); hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (i - lo)

def kmeans3(xs, iters=20):
    xs = sorted(xs); c = [xs[1], xs[len(xs)//2], xs[-2]]
    for _ in range(iters):
        g = [[], [], []]
        for x in xs: g[min(range(3), key=lambda k: abs(x - c[k]))].append(x)
        n = [sum(a)/len(a) if a else c[k] for k, a in enumerate(g)]
        if n == c: break
        c = n
    return [len(a) for a in g], c

def linfit(xs, ys):
    n = len(xs)
    if n < 10: return None
    mx, my = sum(xs)/n, sum(ys)/n
    sxx = sum((x-mx)**2 for x in xs); sxy = sum((x-mx)*(y-my) for x, y in zip(xs, ys)); syy = sum((y-my)**2 for y in ys)
    if sxx == 0 or syy == 0: return None
    b = sxy / sxx
    return {'intercept': round(my - b*mx, 3), 'slope': round(b, 4), 'r2': round(sxy*sxy/(sxx*syy), 3), 'n': n}

def team_frame(players, direction, ball):
    pts = [((x*direction), (y*direction)) for _, x, y in players]
    if len(pts) < 10: return None
    pts.sort()
    out = pts[1:]                                    # drop the deepest player = keeper
    if len(out) > 10: out = out[:10]
    xs = [p[0] for p in out]; ys = [p[1] for p in out]
    near = []
    for i, p in enumerate(out):
        near.append(min(math.hypot(p[0]-q[0], p[1]-q[1]) for j, q in enumerate(out) if j != i))
    return {'def_line': sum(xs[:4]) / 4, 'centroid_x': sum(xs)/len(xs), 'centroid_y': sum(ys)/len(ys),
            'length': pct(xs, .9) - pct(xs, .1), 'width': pct(ys, .9) - pct(ys, .1),
            'area': hull_area(out), 'spacing': sum(near)/len(near), 'last_man': xs[0], 'xs': xs}

def possession(f, direction_h):
    if f.get('poss'): return f['poss']
    if not f['b']: return None
    bx, by = f['b']; best = (3.0, None)
    for side in ('h', 'a'):
        for _, x, y in f[side]:
            d = math.hypot(x-bx, y-by)
            if d < best[0]: best = (d, side)
    return best[1]

def zone(bx):
    return 'own_third' if bx < -17.5 else ('middle_third' if bx < 17.5 else 'final_third')

def analyse(path):
    d = json.load(gzip.open(path, 'rt') if path.endswith('.gz') else open(path))
    meta, frames = d['meta'], d['frames']
    dirs = {int(k): v for k, v in meta['dir'].items()}
    agg = defaultdict(lambda: defaultdict(list))
    fit_x = defaultdict(lambda: ([], [], []))        # state -> (ball_x', def_line, centroid)
    win = defaultdict(list)
    for f in frames:
        if not f['b'] or len(f['h']) < 10 or len(f['a']) < 10: continue
        ph = possession(f, dirs[f['p']])
        for side in ('h', 'a'):
            direction = dirs[f['p']] * (1 if side == 'h' else -1)
            tf = team_frame(f[side], direction, f['b'])
            if not tf: continue
            bx = f['b'][0] * direction
            state = 'unknown' if ph is None else ('in_possession' if ph == side else 'out_of_possession')
            for key in ('def_line', 'centroid_x', 'length', 'width', 'area', 'spacing'):
                agg[(state, zone(bx))][key].append(tf[key])
                agg[(state, 'all')][key].append(tf[key])
            bxs, dl, cx = fit_x[state]
            bxs.append(bx); dl.append(tf['def_line']); cx.append(tf['centroid_x'])
            if state == 'out_of_possession' and bx < 0:
                win[(side, f['p'], int(f['t'] // 12))].append(tf['xs'])
    shape = {}
    for (state, z), m in sorted(agg.items()):
        shape[f'{state}/{z}'] = {k: {'mean': round(sum(v)/len(v), 2), 'std': round(math.sqrt(sum((a-sum(v)/len(v))**2 for a in v)/len(v)), 2)} for k, v in m.items()}
        shape[f'{state}/{z}']['n'] = len(m['def_line'])
    fits = {state: {'def_line_vs_ball_x': linfit(b, dl), 'centroid_vs_ball_x': linfit(b, cx)} for state, (b, dl, cx) in fit_x.items()}
    forms = Counter()
    for xs_list in win.values():
        allx = [x for xs in xs_list for x in xs]
        if len(xs_list) < 30: continue
        counts, _ = kmeans3([x for xs in xs_list[::5] for x in xs])
        forms['-'.join(str(round(c / len(xs_list[::5]))) for c in counts)] += 1
    return {'source': meta['source'], 'match_id': meta['match_id'], 'license': meta['license'], 'frames_used': sum(len(v['def_line']) for k, v in agg.items() if k[1] == 'all'),
            'shape': shape, 'fits': fits, 'formation_windows': dict(forms.most_common(8))}

def compare(a, b):
    print(f"{'metric':44s} {'A: ' + a['source']:>26s} {'B: ' + b['source']:>26s}")
    for state in ('in_possession/all', 'out_of_possession/all', 'out_of_possession/own_third', 'out_of_possession/final_third'):
        for k in ('def_line', 'length', 'width', 'area', 'spacing'):
            try: print(f"{state + ' ' + k:44s} {a['shape'][state][k]['mean']:26.1f} {b['shape'][state][k]['mean']:26.1f}")
            except KeyError: pass
    for st in ('in_possession', 'out_of_possession'):
        fa, fb = a['fits'].get(st, {}).get('def_line_vs_ball_x'), b['fits'].get(st, {}).get('def_line_vs_ball_x')
        if fa and fb: print(f"{st + ' def_line slope vs ball x':44s} {fa['slope']:26.3f} {fb['slope']:26.3f}")

if __name__ == '__main__':
    path = sys.argv[1]
    res = analyse(path)
    os.makedirs(PROC, exist_ok=True)
    out = os.path.join(PROC, 'tactical_priors_' + os.path.basename(path).replace('.json.gz', '').replace('.json', '') + '.json')
    json.dump(res, open(out, 'w'), indent=1)
    print('wrote', os.path.relpath(out, ROOT), '| frames used', res['frames_used'])
    if '--compare' in sys.argv:
        compare(res, json.load(open(sys.argv[sys.argv.index('--compare') + 1])))
