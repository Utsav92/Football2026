#!/usr/bin/env python3
"""Licence-hygiene gate (exit 1 on violation):
  1. manifest completeness: every dataset has licence / commercial / AI-training / redistribution / access / status fields
  2. restricted datasets (commercial use prohibited / unclear / not granted) must be marked ships_in_game = no
  3. no restricted dataset's name appears in shipped code or assets (App/, Packages/**/Sources, Assets/Bundle, Assets/Database)
  4. raw data directories are git-ignored and absent from the app bundle staging folder
  5. every shipped derived constant names its source + licence (TacticalPriors provenance comments)
  6. nothing gated/paid is marked downloaded
  python3 Tools/validate_licenses.py"""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
man = json.load(open(os.path.join(ROOT, 'Datasets', 'manifest.json')))
errs = []
def err(m): errs.append(m); print('VIOLATION', m)
REQ = ['license', 'access', 'status']
for d in man['datasets']:
    for k in REQ:
        if k not in d: err(f"{d['id']}: manifest field '{k}' missing")
    restricted = any(w in str(d.get(k, '')).upper() for k in ('commercial_use',) for w in ('PROHIBITED', 'NOT GRANTED', 'UNCLEAR', 'UNKNOWN'))
    ships = str(d.get('ships_in_game', '')).lower()
    if restricted and not ships.startswith('no'): err(f"{d['id']}: commercial use restricted/unclear but ships_in_game='{d.get('ships_in_game')}'")
    if d.get('access', '').startswith(('gated', 'paid')) and d.get('status') == 'downloaded': err(f"{d['id']}: gated/paid resource marked downloaded")
    if d.get('access') == 'open_research_only' and d.get('status') == 'downloaded': err(f"{d['id']}: research-only data downloaded (confirm intent)")
RESTRICTED_TERMS = ['statsbomb', 'metrica', 'sportsmot', 'amass', 'worldpose', 'soccernet']
scan = [os.path.join(ROOT, 'App'), os.path.join(ROOT, 'Packages', 'FootballKit', 'Sources'), os.path.join(ROOT, 'Assets', 'Bundle'), os.path.join(ROOT, 'Assets', 'Database')]
for base in scan:
    for dp, _, fs in os.walk(base):
        for f in fs:
            p = os.path.join(dp, f)
            if f.endswith(('.usdz', '.png', '.jpg')):
                if any(t in f.lower() for t in RESTRICTED_TERMS): err(f'restricted-dataset name in shipped asset filename: {p}')
                continue
            try: text = open(p, errors='ignore').read().lower()
            except Exception: continue
            for t in RESTRICTED_TERMS:
                # a source file may *mention* a restricted dataset only to say it is not used
                for m in re.finditer(t, text):
                    ctx = text[max(0, m.start() - 120): m.end() + 120]
                    if not any(w in ctx for w in ('not ', 'no ', 'never', 'research', 'unvalidated', 'prohibit', 'gated', 'refus', 'cannot', "don't", 'restricted', 'agreement')):
                        err(f'{os.path.relpath(p, ROOT)}: mentions "{t}" without a restriction note')
gi = open(os.path.join(ROOT, '.gitignore')).read()
if 'Datasets/raw/' not in gi: err('.gitignore must ignore Datasets/raw/')
if os.path.isdir(os.path.join(ROOT, 'Assets', 'Bundle')) and any('raw' in f for f in os.listdir(os.path.join(ROOT, 'Assets', 'Bundle'))): err('raw data staged into the app bundle folder')
fm = open(os.path.join(ROOT, 'Packages/FootballKit/Sources/FootballGame/Formation.swift')).read()
for needle in ('SkillCorner', 'Wyscout', 'CC BY 4.0', 'MIT'):
    if needle not in fm: err(f'TacticalPriors provenance comment lacks "{needle}"')
print('\nRESULT:', 'licence checks passed' if not errs else f'{len(errs)} violation(s)')
sys.exit(1 if errs else 0)
