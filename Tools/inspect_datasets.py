#!/usr/bin/env python3
"""Inspect what is actually on disk for each dataset: checksum verification against the manifest + schema/size summary. Standard library only.
  python3 Tools/inspect_datasets.py"""
import gzip, hashlib, json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
man = json.load(open(os.path.join(ROOT, 'Datasets', 'manifest.json')))
bad = 0
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''): h.update(c)
    return h.hexdigest()
for d in man['datasets']:
    files = d.get('files', [])
    status = d.get('status')
    print(f"\n{d['id']:30s} status={status}  licence={str(d.get('license'))[:60]}")
    for f in files:
        p = os.path.join(ROOT, f['path'])
        if not os.path.exists(p): print('   MISSING', f['path']); bad += 1; continue
        ok = sha(p) == f['sha256']
        print(f"   {'ok ' if ok else 'BAD'} {f['bytes']/1e6:8.2f} MB  {f['path']}")
        bad += (not ok)
def tracking(path):
    d = json.load(gzip.open(path, 'rt')); m = d['meta']; fr = d['frames']
    full = sum(1 for f in fr if len(f['h']) >= 10 and len(f['a']) >= 10)
    print(f"  {os.path.basename(path)}: {m['source']} {m['hz']} Hz, {len(fr)} frames ({full} with >=10 players/side), dir={m['dir']}")
print('\nNormalised tracking:')
td = os.path.join(ROOT, 'Datasets', 'tracking')
if os.path.isdir(td):
    for f in sorted(os.listdir(td)):
        if f.endswith('.json.gz'): tracking(os.path.join(td, f))
for name in ('shot_model.json', 'pass_stats.json'):
    p = os.path.join(ROOT, 'Datasets', 'processed', name)
    if os.path.exists(p):
        j = json.load(open(p)); print(f"\n{name}:", {k: j[k] for k in j if k in ('n_shots', 'n_goals', 'intercept', 'weights', 'n_passes', 'mean_length_m', 'forward_fraction_gt3m')})
p = os.path.join(ROOT, 'Datasets', 'motion', 'skillcorner_gait.json')
if os.path.exists(p): j = json.load(open(p)); print('\nmotion/skillcorner_gait.json: gait', j['gait'], '| clips', len(j['clips']))
print('\nRESULT:', 'all checksums verified' if not bad else f'{bad} problems'); sys.exit(1 if bad else 0)
