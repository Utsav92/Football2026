#!/usr/bin/env python3
"""Normalise tracking data to one format (5 Hz, metres, pitch centre origin).

  python3 Tools/preprocess_tracking.py skillcorner   -> Datasets/tracking/skillcorner_1925299.json.gz
  python3 Tools/preprocess_tracking.py metrica       -> Datasets/tracking/metrica_game1.json.gz   (research only: no licence)

Normalised file:  {meta:{...}, frames:[{t, p, b:[x,y]|null, h:[[id,x,y]..], a:[[id,x,y]..], poss:'h'|'a'|null}]}
Coordinates: x along the pitch (-52.5..52.5), y across (-34..34, up). `meta.dir` gives the +/-1 attacking direction of the HOME team per
period (away is the opposite). Missing observations are dropped (never interpolated across gaps).  Standard library only."""
import csv, gzip, json, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'Datasets', 'raw')
OUT = os.path.join(ROOT, 'Datasets', 'tracking')
L, W = 105.0, 68.0
HZ = 5

def isnum(v):
    return v is not None and not (isinstance(v, float) and math.isnan(v))

def infer_dir(frames, team_key, gk_ids, period):
    """Direction the team attacks (+1/-1) = opposite side of the pitch from its goalkeeper."""
    xs = [x for f in frames if f['p'] == period for pid, x, _ in f[team_key] if pid in gk_ids]
    return 0 if not xs else (1 if sum(xs) / len(xs) < 0 else -1)

def skillcorner(match_id='1925299'):
    base = os.path.join(RAW, 'skillcorner', match_id)
    match = json.load(open(os.path.join(base, f'{match_id}_match.json')))
    team = {}      # tracking player_id -> ('h'|'a', number, role)
    for p in match['players']:
        tid = p.get('id')   # tracking player_id == match.json player 'id' (verified: 22/22 overlap), not 'trackable_object'
        if tid is None: continue
        side = 'h' if p['team_id'] == match['home_team']['id'] else 'a'
        team[tid] = (side, p['number'], p['player_role']['acronym'])
    gk = {i for i, (_, _, r) in team.items() if r == 'GK'}
    frames, detected, total = [], 0, 0
    step = 10 // HZ
    with open(os.path.join(base, f'{match_id}_tracking_extrapolated.jsonl')) as f:
        for n, line in enumerate(f):
            if n % step: continue
            d = json.loads(line)
            if not d['player_data'] or d['period'] is None: continue
            h, a = [], []
            for p in d['player_data']:
                info = team.get(p['player_id'])
                if info is None or not isnum(p.get('x')): continue
                total += 1; detected += bool(p.get('is_detected'))
                (h if info[0] == 'h' else a).append((p['player_id'], round(p['x'], 2), round(p['y'], 2)))
            b = d['ball_data']
            g = d['possession'].get('group')
            frames.append({'t': round(n / 10.0, 1), 'p': d['period'],
                           'b': [round(b['x'], 2), round(b['y'], 2)] if isnum(b.get('x')) else None,
                           'h': h, 'a': a, 'poss': {'home team': 'h', 'away team': 'a'}.get(g)})
    documented = {1: 1 if match['home_team_side'][0] == 'left_to_right' else -1, 2: 1 if match['home_team_side'][1] == 'left_to_right' else -1}
    inferred = {p: infer_dir(frames, 'h', gk & {i for i, v in team.items() if v[0] == 'h'}, p) for p in (1, 2)}
    meta = {'source': 'skillcorner_opendata', 'match_id': match_id, 'hz': HZ, 'pitch': [L, W], 'dir': documented,
            'dir_inferred_from_gk': inferred, 'detected_fraction': round(detected / max(total, 1), 3),
            'license': 'MIT (SkillCorner) - credit SkillCorner', 'players': {str(i): {'team': v[0], 'number': v[1], 'role': v[2]} for i, v in team.items()}}
    return meta, frames

def metrica(game='1'):
    base = os.path.join(RAW, 'metrica', f'Sample_Game_{game}')
    def read(name):
        with open(os.path.join(base, f'Sample_Game_{game}_RawTrackingData_{name}_Team.csv')) as f:
            r = csv.reader(f)
            next(r); jerseys = next(r); header = next(r)
            cols = []
            for i, h in enumerate(header):
                if h.startswith('Player'): cols.append((h, i))
            ball = header.index('Ball')
            rows = {}
            for k, row in enumerate(r):
                if k % (25 // HZ): continue
                per, frame, t = int(row[0]), int(row[1]), float(row[2])
                pl = []
                for pid, i in cols:
                    try: x, y = float(row[i]), float(row[i + 1])
                    except ValueError: continue
                    if isnum(x) and isnum(y): pl.append((pid, round((x - 0.5) * L, 2), round(-(y - 0.5) * W, 2)))
                try: bx, by = float(row[ball]), float(row[ball + 1])
                except ValueError: bx = by = float('nan')
                rows[frame] = (per, t, pl, [round((bx - 0.5) * L, 2), round(-(by - 0.5) * W, 2)] if isnum(bx) else None)
            return rows
    home, away = read('Home'), read('Away')
    frames = []
    for fr in sorted(set(home) & set(away)):
        per, t, hp, b = home[fr]
        frames.append({'t': round(t, 2), 'p': per, 'b': b, 'h': hp, 'a': away[fr][2], 'poss': None})
    # Metrica names the home keeper "Player11" (first column) and the away keeper "Player25"; verify rather than trust:
    # the keeper is the outfield-distant player: use the player with the most extreme mean |x| at period start.
    def keeper(key, period):
        acc = {}
        for f in frames:
            if f['p'] == period:
                for pid, x, _ in f[key]: acc.setdefault(pid, []).append(x)
        return max(acc, key=lambda k: abs(sum(acc[k]) / len(acc[k]))) if acc else None
    dirs = {}
    for p in (1, 2):
        hk = keeper('h', p)
        dirs[p] = infer_dir(frames, 'h', {hk}, p)
    meta = {'source': 'metrica_sample', 'match_id': f'game{game}', 'hz': HZ, 'pitch': [L, W], 'dir': dirs,
            'license': 'NONE declared - research/viewer only, do not redistribute or ship derivatives', 'players': {}}
    return meta, frames

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'skillcorner'
    meta, frames = {'skillcorner': skillcorner, 'metrica': metrica}[which]()
    os.makedirs(OUT, exist_ok=True)
    name = f"{which}_{meta['match_id'] if which == 'skillcorner' else 'game1'}.json.gz"
    with gzip.open(os.path.join(OUT, name), 'wt') as f:
        json.dump({'meta': meta, 'frames': frames}, f, separators=(',', ':'))
    full = [f for f in frames if len(f['h']) >= 10 and len(f['a']) >= 10]
    print(f"{name}: {len(frames)} frames @ {HZ} Hz, {len(full)} with >=10 players per side; dir={meta['dir']}", {k: v for k, v in meta.items() if k.startswith('dir_') or k == 'detected_fraction'})

if __name__ == '__main__':
    main()
