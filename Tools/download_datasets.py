#!/usr/bin/env python3
"""Downloads ONLY legally accessible dataset files into Datasets/raw/ and records checksums in Datasets/manifest.json.

  python3 Tools/download_datasets.py list
  python3 Tools/download_datasets.py fetch skillcorner_opendata
  python3 Tools/download_datasets.py fetch wyscout_public [--full]
  python3 Tools/download_datasets.py fetch metrica_sample
  python3 Tools/download_datasets.py fetch statsbomb_open --acknowledge-research-only --registered

Gated / paid resources (SportsMOT, AMASS, WorldPose, SoccerNet*, Fab, MetaHuman, Mixamo) are never fetched:
the tool prints how to obtain them legitimately. Raw data is kept in Datasets/raw (git-ignored), separate from game assets.
Standard library only."""
import argparse, datetime, hashlib, json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'Datasets', 'raw')
MANIFEST = os.path.join(ROOT, 'Datasets', 'manifest.json')
UA = {'User-Agent': 'Football2026-dataset-tool/1.0'}

SC = 'https://raw.githubusercontent.com/SkillCorner/opendata/master/'
SC_LFS = 'https://media.githubusercontent.com/media/SkillCorner/opendata/master/'
MET = 'https://raw.githubusercontent.com/metrica-sports/sample-data/master/data/Sample_Game_1/'
SB = 'https://raw.githubusercontent.com/statsbomb/open-data/master/data/'
FIG = 'https://api.figshare.com/v2/articles/%d'

GATED = {
    'sportsmot': 'Sign up at CodaLab and accept the SportsMOT competition terms (CC BY-NC 4.0, non-commercial, no redistribution): https://codalab.lisn.upsaclay.fr/competitions/12424',
    'amass': 'Register and accept the non-commercial licence at https://amass.is.tue.mpg.de/ . Commercial use requires ps-license@tue.mpg.de.',
    'worldpose': 'Submit the academic data-request form linked from https://eth-ait.github.io/WorldPoseDataset/ . Footage needs a separate FIFA agreement.',
    'soccernet_gar': 'Request access on https://huggingface.co/datasets/OpenSportsLab/SoccerNet-GAR (manual approval) and read the terms before using.',
    'soccernet': 'Sign the SoccerNet NDA at https://www.soccer-net.org/data for video; annotations via the SoccerNet pip package.',
    'fab_realistic_soccer_player': 'Purchase (Professional tier for commercial use) at https://www.fab.com/listings/a16d362e-0f6c-4163-b30e-033cecbae652 then run Tools/import_character.py on the download.',
    'metahuman': 'Use the MetaHuman app / Unreal Engine under the Unreal Engine EULA (https://www.metahuman.com/download); read the current EULA regarding AI training and third-party components.',
    'mixamo': 'Download clips manually at https://www.mixamo.com/ with your Adobe ID (FBX, no skin / 30 fps); then run Tools/retarget_animations.py. Raw clips must not be redistributed standalone.',
}

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

def get(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print('  have', os.path.relpath(dest, ROOT)); return dest
    print('  GET ', url)
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r, open(dest + '.part', 'wb') as f:
        total = 0
        while True:
            b = r.read(1 << 20)
            if not b: break
            f.write(b); total += len(b)
    os.replace(dest + '.part', dest)
    print('       %.1f MB' % (total / 1e6))
    return dest

def figshare_files(article_id, names=None):
    req = urllib.request.Request(FIG % article_id, headers=UA)
    meta = json.load(urllib.request.urlopen(req, timeout=60))
    lic = meta.get('license', {}).get('name')
    out = [(f['name'], f['download_url']) for f in meta['files'] if not names or f['name'] in names]
    return lic, out

def plan(ds, args):
    """Returns (list[(url, relative_dest)], notes)."""
    if ds == 'skillcorner_opendata':
        m = '1925299'
        base = 'skillcorner/'
        files = [(SC + 'data/matches.json', base + 'matches.json'), (SC + 'LICENSE', base + 'LICENSE'),
                 (SC + f'data/matches/{m}/{m}_match.json', base + f'{m}/{m}_match.json'),
                 (SC_LFS + f'data/matches/{m}/{m}_tracking_extrapolated.jsonl', base + f'{m}/{m}_tracking_extrapolated.jsonl'),
                 (SC + f'data/matches/{m}/{m}_phases_of_play.csv', base + f'{m}/{m}_phases_of_play.csv'),
                 (SC + 'data/bodypose/README.md', base + 'bodypose/README.md'),
                 (SC + 'data/bodypose/sample_1925299_phase406.jsonl.gz', base + 'bodypose/sample_1925299_phase406.jsonl.gz')]
        return files, 'MIT licence; please credit SkillCorner.'
    if ds == 'metrica_sample':
        b = 'metrica/Sample_Game_1/'
        names = ['Sample_Game_1_RawEventsData.csv', 'Sample_Game_1_RawTrackingData_Home_Team.csv', 'Sample_Game_1_RawTrackingData_Away_Team.csv']
        return [(MET + n, b + n) for n in names], 'NO licence declared: research/viewer use only; do not redistribute or ship derivatives.'
    if ds == 'wyscout_public':
        files = []
        for aid, names in [(7770422, None), (7765196, None), (7770599, None if args.full else [])]:
            if names == []: continue
            lic, fs = figshare_files(aid, names)
            assert lic == 'CC BY 4.0', f'unexpected licence {lic} for figshare article {aid}'
            files += [(u, 'wyscout/' + n) for n, u in fs]
        return files, 'CC BY 4.0: attribute Pappalardo et al., Scientific Data 6:236 (2019).'
    if ds == 'statsbomb_open':
        if not (args.acknowledge_research_only and args.registered):
            sys.exit('StatsBomb: the Public Data User Agreement forbids commercial use and redistribution, and asks users to register '
                     '(statsbomb.com/resource-centre). Re-run with --registered --acknowledge-research-only to confirm both.')
        return [(SB + 'competitions.json', 'statsbomb/competitions.json'), (SB + 'matches/43/106.json', 'statsbomb/matches_43_106.json'),
                (SB + 'events/3869685.json', 'statsbomb/events_3869685.json'), (SB + 'lineups/3869685.json', 'statsbomb/lineups_3869685.json')], \
               'RESEARCH ONLY: nothing derived from this may ship in the game.'
    return None, None

def update_manifest(ds, files, notes):
    m = json.load(open(MANIFEST))
    for d in m['datasets']:
        if d['id'] == ds:
            d['status'] = 'downloaded'
            d['download_date'] = datetime.date.today().isoformat()
            d['files'] = [{'path': 'Datasets/raw/' + rel, 'bytes': os.path.getsize(os.path.join(RAW, rel)),
                           'sha256': sha256(os.path.join(RAW, rel))} for _, rel in files]
            d['download_notes'] = notes
    json.dump(m, open(MANIFEST, 'w'), indent=2); open(MANIFEST, 'a').write('\n')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['list', 'fetch'])
    ap.add_argument('dataset', nargs='?')
    ap.add_argument('--full', action='store_true', help='wyscout: also fetch the 77 MB events archive')
    ap.add_argument('--acknowledge-research-only', action='store_true')
    ap.add_argument('--registered', action='store_true')
    a = ap.parse_args()
    m = json.load(open(MANIFEST))
    if a.cmd == 'list':
        for d in m['datasets']:
            print(f"{d['id']:32s} access={d.get('access','?'):24s} status={d.get('status')}")
        return
    if a.dataset in GATED:
        print(f'{a.dataset} is gated or paid and is never auto-downloaded.\n  -> {GATED[a.dataset]}'); sys.exit(2)
    files, notes = plan(a.dataset, a)
    if files is None:
        sys.exit(f'unknown dataset {a.dataset}')
    print(a.dataset, '-', notes)
    for url, rel in files:
        get(url, os.path.join(RAW, rel))
    update_manifest(a.dataset, files, notes)
    print('manifest updated')

if __name__ == '__main__':
    main()
