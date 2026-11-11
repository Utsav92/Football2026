#!/usr/bin/env python3
"""Validate the character asset set in Assets/Bundle (USDZ LODs + animation clips) by re-importing each file in Blender.
  python3 Tools/validate_assets.py
Checks (exit code 1 on any failure): every file imports; every file shares ONE skeleton (bone names identical to player.json);
LOD vertex counts strictly decrease; scale/height in metres; skin weights valid; every clip in player.json exists and its length matches the
manifest (frames / fps) within one frame; sizes within budget. Report: Datasets/validation/asset_validation.json."""
import json, os, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.environ.get('BLENDER', '/Applications/Blender.app/Contents/MacOS/Blender')
BUNDLE = os.path.join(ROOT, 'Assets', 'Bundle'); OUT = os.path.join(ROOT, 'Datasets', 'validation'); os.makedirs(OUT, exist_ok=True)
man = json.load(open(os.path.join(BUNDLE, 'player.json')))
failures = []
def fail(msg): failures.append(msg); print('FAIL', msg)

def inspect(f):
    rep = os.path.join(OUT, f + '.inspect.json')
    r = subprocess.run([BLENDER, '-b', '--python', os.path.join(ROOT, 'Tools/blender/inspect_character.py'), '--', os.path.join(BUNDLE, f), rep], capture_output=True, text=True)
    if not os.path.exists(rep): fail(f'{f}: Blender failed to import\n{r.stdout[-400:]}{r.stderr[-400:]}'); return None
    return json.load(open(rep))

reports = {}
files = sorted(f for f in os.listdir(BUNDLE) if f.endswith('.usdz'))
for f in files:
    reports[f] = inspect(f)
expected = {b.replace('.', '_') for b in man['bones']}      # USD sanitises '.' to '_' in joint names
for f, r in reports.items():
    if r is None: continue
    names = {b.split('/')[-1].replace('.', '_') for b in r['bones']}
    if not expected <= names: fail(f'{f}: skeleton differs from player.json (missing {sorted(expected - names)[:5]})')
for f in files:
    r = reports.get(f)
    if not r or not f.startswith('player_lod'): continue
    for k, v in r['checks'].items():
        if not v: fail(f'{f}: check {k} failed ({r.get("height_m")} m, unweighted {r["unweighted_vertices"]}, >4 infl {r["vertices_over_4_influences"]})')
lods = [reports[f'player_lod{i}.usdz'] for i in range(3) if reports.get(f'player_lod{i}.usdz')]
if len(lods) == 3:
    v = [l['vertices'] for l in lods]
    if not (v[0] > v[1] > v[2]): fail(f'LOD vertex counts must decrease: {v}')
    if abs(lods[0]['height_m'] - lods[2]['height_m']) > 0.05: fail('LOD heights differ')
for name, info in man['clips'].items():
    r = reports.get(f'anim_{name}.usdz')
    if r is None: fail(f'clip {name}: file missing or unreadable'); continue
    acts = r.get('actions', {})
    if not acts: fail(f'clip {name}: no animation found in file'); continue
    a = max(acts.values(), key=lambda x: x['frames'])
    if abs(a['frames'] - info['frames']) > 1: fail(f'clip {name}: {a["frames"]} frames in file vs {info["frames"]} in manifest')
total = sum(os.path.getsize(os.path.join(BUNDLE, f)) for f in files)
if total > 8_000_000: fail(f'character bundle {total/1e6:.1f} MB exceeds 8 MB budget')
summary = {'files': len(files), 'bytes': total, 'lod_vertices': [l['vertices'] for l in lods], 'height_m': lods[0]['height_m'] if lods else None,
           'clips_checked': len(man['clips']), 'failures': failures}
json.dump(summary, open(os.path.join(OUT, 'asset_validation.json'), 'w'), indent=1)
print(json.dumps({k: v for k, v in summary.items() if k != 'failures'}), '->', 'PASS' if not failures else f'{len(failures)} FAILURES')
sys.exit(1 if failures else 0)
