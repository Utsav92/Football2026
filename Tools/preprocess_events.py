#!/usr/bin/env python3
"""Normalise football event data and derive interpretable heuristics. Standard library only.

  python3 Tools/preprocess_events.py wyscout        # shot model + pass statistics from the CC BY 4.0 Wyscout public dataset
  python3 Tools/preprocess_events.py statsbomb --selftest   # parser check against a SYNTHETIC fixture (real StatsBomb data is research-only)

Normalised event taxonomy (Datasets/events/taxonomy.json): PASS, SHOT, DUEL, TACKLE, INTERCEPTION, CLEARANCE, FOUL, OFFSIDE,
SET_PIECE, SAVE, CARRY, OTHER. Pitch coordinates are converted to metres with the attacking goal at x=105 (x 0..105, y 0..68).
Outputs (Datasets/processed/): shot_model.json (logistic xG fit + calibration table), pass_stats.json.
Attribution (Wyscout): Pappalardo et al., Scientific Data 6:236 (2019), CC BY 4.0."""
import json, math, os, sys, zipfile
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'Datasets', 'raw')
PROC = os.path.join(ROOT, 'Datasets', 'processed')
EVENTS = os.path.join(ROOT, 'Datasets', 'events')
L, W, GOAL_W = 105.0, 68.0, 7.32

TAXONOMY = {
    'wyscout': {'Pass': 'PASS', 'Shot': 'SHOT', 'Duel': 'DUEL', 'Foul': 'FOUL', 'Free Kick': 'SET_PIECE', 'Offside': 'OFFSIDE',
                'Save attempt': 'SAVE', 'Goalkeeper leaving line': 'OTHER', 'Interruption': 'OTHER', 'Others on the ball': 'OTHER'},
    'wyscout_sub': {'Clearance': 'CLEARANCE', 'Ground defending duel': 'TACKLE', 'Air duel': 'DUEL', 'Ground attacking duel': 'DUEL',
                    'Touch': 'OTHER', 'Acceleration': 'CARRY'},
    'statsbomb': {'Pass': 'PASS', 'Shot': 'SHOT', 'Duel': 'DUEL', 'Interception': 'INTERCEPTION', 'Clearance': 'CLEARANCE',
                  'Foul Committed': 'FOUL', 'Offside': 'OFFSIDE', 'Goal Keeper': 'SAVE', 'Carry': 'CARRY', 'Dribble': 'DUEL',
                  'Block': 'OTHER', 'Ball Receipt*': 'OTHER', 'Ball Recovery': 'INTERCEPTION'},
}

def shot_features(x100, y100):
    """x100, y100: Wyscout 0..100 coordinates (attack towards x=100)."""
    x, y = x100 / 100 * L, y100 / 100 * W
    dx, dy = L - x, y - W / 2
    dist = math.hypot(dx, dy)
    # angle subtended by the posts (standard xG geometry)
    a = math.atan2(GOAL_W * dx, dx * dx + dy * dy - (GOAL_W / 2) ** 2)
    if a < 0: a += math.pi
    return dist, a

def fit_logistic(X, y, iters=400, lr=0.4, l2=1e-4):
    n, d = len(X), len(X[0])
    mu = [sum(r[j] for r in X) / n for j in range(d)]
    sd = [math.sqrt(sum((r[j] - mu[j]) ** 2 for r in X) / n) or 1 for j in range(d)]
    Z = [[(r[j] - mu[j]) / sd[j] for j in range(d)] for r in X]
    w = [0.0] * d; b = math.log(sum(y) / (n - sum(y)))
    for it in range(iters):
        gw = [0.0] * d; gb = 0.0
        for z, t in zip(Z, y):
            p = 1 / (1 + math.exp(-(b + sum(wi * zi for wi, zi in zip(w, z)))))
            e = p - t; gb += e
            for j in range(d): gw[j] += e * z[j]
        b -= lr * gb / n
        for j in range(d): w[j] -= lr * (gw[j] / n + l2 * w[j])
    # convert standardised weights back to raw features
    raw_w = [w[j] / sd[j] for j in range(d)]
    raw_b = b - sum(w[j] * mu[j] / sd[j] for j in range(d))
    return raw_b, raw_w

def wyscout():
    z = zipfile.ZipFile(os.path.join(RAW, 'wyscout', 'events.zip'))
    X, Y, rows = [], [], []
    passes = defaultdict(lambda: [0, 0]); fwd = [0, 0]; lens = []; counts = defaultdict(int)
    for name in sorted(n for n in z.namelist() if n.endswith('.json')):
        print(' reading', name, flush=True)
        ev = json.load(z.open(name))
        for e in ev:
            en, sub = e['eventName'], e.get('subEventName', '')
            norm = TAXONOMY['wyscout_sub'].get(sub) or TAXONOMY['wyscout'].get(en, 'OTHER')
            counts[norm] += 1
            pos = e.get('positions') or []
            tags = {t['id'] for t in e.get('tags', [])}
            if en == 'Shot' and pos:
                d, a = shot_features(pos[0]['x'], pos[0]['y'])
                head = 1.0 if 403 in tags else 0.0
                goal = 1 if 101 in tags else 0
                X.append([d, a, head]); Y.append(goal); rows.append((d, goal, head))
            elif en == 'Pass' and len(pos) >= 2 and sub in ('Simple pass', 'High pass', 'Smart pass', 'Launch', 'Cross', 'Hand pass', 'Head pass'):
                x0, y0, x1, y1 = pos[0]['x'] / 100 * L, pos[0]['y'] / 100 * W, pos[1]['x'] / 100 * L, pos[1]['y'] / 100 * W
                length = math.hypot(x1 - x0, y1 - y0)
                ok = 1801 in tags
                band = min(int(length // 10), 5)
                passes[(sub, band)][0] += 1; passes[(sub, band)][1] += ok
                lens.append(length); fwd[0] += 1; fwd[1] += (x1 - x0) > 3
    print(' events by normalised type:', dict(counts))
    print(' shots:', len(Y), 'goals:', sum(Y))
    b, w = fit_logistic(X, Y)
    # Calibration by distance band
    bins = defaultdict(lambda: [0, 0, 0.0])
    for (d, g, h), x in zip(rows, X):
        k = min(int(d // 4), 9)
        p = 1 / (1 + math.exp(-(b + w[0] * x[0] + w[1] * x[1] + w[2] * x[2])))
        bins[k][0] += 1; bins[k][1] += g; bins[k][2] += p
    cal = [{'dist_m': f'{k*4}-{k*4+4}', 'shots': n, 'goal_rate': round(g / n, 4), 'model_mean_xg': round(sp / n, 4)} for k, (n, g, sp) in sorted(bins.items())]
    model = {'source': 'wyscout_public (CC BY 4.0, Pappalardo et al. 2019)', 'n_shots': len(Y), 'n_goals': sum(Y), 'excludes': 'penalties and free kicks (separate Wyscout events)',
             'features': ['distance_m', 'goal_angle_rad', 'is_header'], 'intercept': round(b, 5), 'weights': [round(v, 5) for v in w],
             'formula': 'xg = 1/(1+exp(-(intercept + w0*dist + w1*angle + w2*header)))', 'calibration': cal}
    pstats = {'n_passes': fwd[0], 'mean_length_m': round(sum(lens) / len(lens), 2), 'forward_fraction_gt3m': round(fwd[1] / fwd[0], 3),
              'accuracy_by_type_and_length_band_10m': {f'{k[0]}|{k[1]*10}-{k[1]*10+10}m': {'n': v[0], 'accuracy': round(v[1] / v[0], 3)} for k, v in sorted(passes.items()) if v[0] > 200},
              'source': model['source']}
    os.makedirs(PROC, exist_ok=True); os.makedirs(EVENTS, exist_ok=True)
    json.dump(model, open(os.path.join(PROC, 'shot_model.json'), 'w'), indent=1)
    json.dump(pstats, open(os.path.join(PROC, 'pass_stats.json'), 'w'), indent=1)
    json.dump(TAXONOMY, open(os.path.join(EVENTS, 'taxonomy.json'), 'w'), indent=1)
    print('shot model: intercept %.4f weights %s' % (b, model['weights']))
    for c in cal: print('  ', c)
    print('pass stats: mean length %.1f m, forward %.1f%%' % (pstats['mean_length_m'], 100 * pstats['forward_fraction_gt3m']))

# ---- StatsBomb: parser only (schema per public documentation). NOT validated on real files in this repo. ----
def parse_statsbomb_events(events):
    """Yield normalised events from a StatsBomb event list. Pitch is 120x80 yards-ish units -> metres, attack towards x=105."""
    for e in events:
        t = e['type']['name']
        norm = TAXONOMY['statsbomb'].get(t, 'OTHER')
        loc = e.get('location')
        out = {'type': norm, 'team': e.get('team', {}).get('name'), 'minute': e.get('minute'), 'second': e.get('second')}
        if loc: out['x'], out['y'] = loc[0] / 120 * L, loc[1] / 80 * W
        if norm == 'PASS':
            p = e['pass']; el = p['end_location']
            out.update(end_x=el[0] / 120 * L, end_y=el[1] / 80 * W, length=p.get('length'), complete='outcome' not in p)
        if norm == 'SHOT':
            s = e['shot']; out.update(xg=s.get('statsbomb_xg'), goal=s['outcome']['name'] == 'Goal')
        yield out

def statsbomb_selftest():
    fixture = [  # SYNTHETIC, written from the public schema documentation; not StatsBomb data
        {'type': {'name': 'Pass'}, 'team': {'name': 'A'}, 'minute': 1, 'second': 2, 'location': [60, 40],
         'pass': {'end_location': [80, 30], 'length': 23.3}},
        {'type': {'name': 'Shot'}, 'team': {'name': 'A'}, 'minute': 5, 'second': 0, 'location': [108, 40],
         'shot': {'statsbomb_xg': 0.31, 'outcome': {'name': 'Goal'}}},
        {'type': {'name': 'Interception'}, 'team': {'name': 'B'}, 'minute': 6, 'second': 0, 'location': [30, 10]}]
    out = list(parse_statsbomb_events(fixture))
    assert [o['type'] for o in out] == ['PASS', 'SHOT', 'INTERCEPTION'], out
    assert abs(out[0]['end_x'] - 70.0) < 1e-6 and out[1]['goal'] is True and out[0]['complete'] is True
    print('statsbomb parser selftest OK (synthetic fixture; unvalidated on real StatsBomb files)')

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'wyscout'
    if which == 'wyscout': wyscout()
    elif which == 'statsbomb':
        if '--selftest' in sys.argv: statsbomb_selftest()
        else: sys.exit('Real StatsBomb files are research-only (no commercial use); see Datasets/LICENSE_AUDIT.md')
