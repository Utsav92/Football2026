#!/usr/bin/env python3
"""Embed a clip of normalised tracking into a standalone HTML replay (Datasets/processed/tactical_viewer.html).
  python3 Tools/build_viewer.py [tracking.json.gz] [start_seconds=1410] [length_seconds=120]
Defaults to the SkillCorner (MIT) match so the output is safe to share with credit. Do not embed Metrica (no licence)."""
import gzip, json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Datasets/tracking/skillcorner_1925299.json.gz')
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 1410
dur = float(sys.argv[3]) if len(sys.argv) > 3 else 120
d = json.load(gzip.open(src, 'rt'))
frames = [f for f in d['frames'] if f['p'] == 1 and t0 <= f['t'] < t0 + dur and len(f['h']) >= 10 and len(f['a']) >= 10]
d['frames'] = frames
html = open(os.path.join(ROOT, 'Tools/tactical_viewer.template.html')).read().replace('/*DATA*/null', json.dumps(d, separators=(',', ':')))
out = os.path.join(ROOT, 'Datasets/processed/tactical_viewer.html')
open(out, 'w').write(html)
print(f'wrote {os.path.relpath(out, ROOT)}: {len(frames)} frames ({dur:.0f}s) from {d["meta"]["source"]}, {len(html)/1e3:.0f} KB')
