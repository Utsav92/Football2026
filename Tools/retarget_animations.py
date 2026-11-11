#!/usr/bin/env python3
"""Retarget an animation clip (Mixamo FBX, UE-mannequin FBX, ...) onto the Football 2026 skeleton and export a game clip.
  python3 Tools/retarget_animations.py --source run.fbx --map mixamo --name run --out Assets/Characters/out
  python3 Tools/retarget_animations.py --selftest

Method (Blender): import the source armature, add COPY_ROTATION constraints (world space) from the source bones to our bones, bake the visual
result to keyframes, remove constraints, export `anim_<name>.usdz` with the standard settings. World-space rotation copy is correct when the two
rest poses are similar (A-pose vs A-pose); T-pose -> A-pose sources need a rest-pose correction, which is NOT implemented. Root motion is
stripped (the game drives position). Only appropriately licensed clips may be retargeted: Mixamo clips must be downloaded by you under your own
Adobe ID and must not be redistributed standalone.
Self-test: builds a synthetic Mixamo-named armature with a known animation, retargets it and verifies keyframes land on our bones."""
import os, subprocess, sys
ROOT = os.path.dirname(os.path.abspath(__file__)).rsplit('/Tools', 1)[0]
BLENDER = os.environ.get('BLENDER', '/Applications/Blender.app/Contents/MacOS/Blender')
BLEND = os.path.join(ROOT, 'Assets/Characters/out/player.blend')
args = sys.argv[1:]
if not args: sys.exit(__doc__)
inner = os.path.join(ROOT, 'Tools/blender/_retarget_inner.py')
r = subprocess.run([BLENDER, '-b', BLEND, '--python', inner, '--'] + args, capture_output=True, text=True)
print('\n'.join(l for l in r.stdout.splitlines() if l.startswith(('RETARGET', 'EXPORTED', 'SELFTEST', 'Error', 'Traceback'))) or r.stdout[-800:], r.stderr[-600:] if r.returncode else '')
sys.exit(r.returncode)
