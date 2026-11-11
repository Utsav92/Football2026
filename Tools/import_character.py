#!/usr/bin/env python3
"""Validate a third-party character (e.g. a Fab "Realistic Soccer Player - Rigged" download) BEFORE it enters the pipeline.
  python3 Tools/import_character.py <file.fbx|glb|blend|usdz> --license-confirmed "Fab Professional licence, order #..." [--name hero]
  python3 Tools/import_character.py --selftest        # runs the same checks on our own FBX export to prove the FBX path works

Does NOT download or buy anything. It refuses to run without a recorded licence statement (kept in Datasets/characters/<name>.license.txt).
Output: Datasets/characters/<name>.report.json (skeleton family, vertex/triangle counts, textures, height, skin-weight quality, checks) and
the recommended next step (retarget map for Tools/retarget_animations.py when the skeleton is Mixamo-like)."""
import json, os, subprocess, sys
ROOT = os.path.dirname(os.path.abspath(__file__)).rsplit('/Tools', 1)[0]
BLENDER = os.environ.get('BLENDER', '/Applications/Blender.app/Contents/MacOS/Blender')
OUT = os.path.join(ROOT, 'Datasets', 'characters'); os.makedirs(OUT, exist_ok=True)

def inspect(path, name):
    rep = os.path.join(OUT, name + '.report.json')
    r = subprocess.run([BLENDER, '-b', '--python', os.path.join(ROOT, 'Tools/blender/inspect_character.py'), '--', path, rep], capture_output=True, text=True)
    if not os.path.exists(rep): sys.exit('Blender could not import the file:\n' + r.stdout[-600:] + r.stderr[-600:])
    return json.load(open(rep))

def advise(rep):
    print(f"\n{rep['file']}: skeleton family = {rep['skeleton_family']} {rep['skeleton_family_coverage']}")
    print(f"  {rep['bone_count']} bones, {rep['meshes']} meshes, {rep['vertices']} verts / {rep['triangles']} tris, height {rep['height_m']} m, {len(rep['actions'])} actions")
    print(f"  textures: { {k: v for k, v in list(rep['images'].items())[:6]} }")
    for k, v in rep['checks'].items(): print(f"  [{'ok' if v else 'FAIL'}] {k}")
    fam = rep['skeleton_family']
    if rep['triangles'] > 60000: print('  ! very heavy for 22 on-pitch players: generate LODs (Tools/blender/make_football_player.py shows the decimate+weight-prune recipe)')
    if any(max(s) > 2048 for s in rep['images'].values()): print('  ! textures above 2048 px: downscale for gameplay LOD (usdz_downscale_size)')
    print({'mixamo': '  next: python3 Tools/retarget_animations.py --map mixamo ...', 'football2026': '  next: already compatible with the game skeleton',
           'ue_mannequin': '  next: UE mannequin names detected: add a bone map and retarget (Tools/retarget_animations.py --map ue)'}.get(fam, '  next: unknown skeleton: author a bone map before retargeting'))

if '--selftest' in sys.argv:
    fbx = os.path.join(OUT, 'selftest_player.fbx')
    subprocess.run([BLENDER, '-b', os.path.join(ROOT, 'Assets/Characters/out/player.blend'), '--python-expr',
                    f"import bpy; bpy.ops.export_scene.fbx(filepath='{fbx}', add_leaf_bones=False, bake_anim=False)"], capture_output=True)
    rep = inspect(fbx, 'selftest_player'); advise(rep)
    sys.exit(0 if rep['pass'] else 1)

if len(sys.argv) < 2 or sys.argv[1].startswith('--'): sys.exit(__doc__)
path = sys.argv[1]
if '--license-confirmed' not in sys.argv: sys.exit('Refusing: pass --license-confirmed "<where/under which licence you obtained this file>".')
lic = sys.argv[sys.argv.index('--license-confirmed') + 1]
name = sys.argv[sys.argv.index('--name') + 1] if '--name' in sys.argv else os.path.splitext(os.path.basename(path))[0]
open(os.path.join(OUT, name + '.license.txt'), 'w').write(lic + '\n')
rep = inspect(path, name); advise(rep)
sys.exit(0 if rep['pass'] else 1)
