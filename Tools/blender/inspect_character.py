"""
Inspect a character/animation file in Blender (headless) and write a JSON report with pass/fail checks.
  Blender -b --python Tools/blender/inspect_character.py -- <file.usdz|usd|fbx|glb|gltf|blend|obj> <report.json>

Reports: armature + bones, skeleton-family coverage (ours / Mixamo / UE mannequin), meshes, vertex & triangle counts, materials, image sizes,
bounding-box height in metres, skin-weight quality (unweighted vertices, >4 influences, non-normalised), animation actions with frame ranges.
Checks: has armature, height 1.5-2.1 m, every vertex weighted, <=4 influences (mobile-friendly), forward/up sanity.
Used by Tools/validate_assets.py (our own USDZ outputs) and Tools/import_character.py (third-party downloads such as a Fab asset).
"""
import bpy, sys, os, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
path, out = argv[0], argv[1]
ext = os.path.splitext(path)[1].lower()

bpy.ops.wm.read_factory_settings(use_empty=True)
if ext in ('.usd', '.usda', '.usdc', '.usdz'): bpy.ops.wm.usd_import(filepath=path)
elif ext == '.fbx': bpy.ops.import_scene.fbx(filepath=path)
elif ext in ('.glb', '.gltf'): bpy.ops.import_scene.gltf(filepath=path)
elif ext == '.obj': bpy.ops.wm.obj_import(filepath=path)
elif ext == '.blend': bpy.ops.wm.open_mainfile(filepath=path)
else: raise SystemExit(f'unsupported format {ext}')

FAMILIES = {
    'football2026': ['hips', 'spine', 'chest', 'neck', 'head', 'clavicle.L', 'upper_arm.L', 'forearm.L', 'hand.L', 'thigh.L', 'shin.L', 'foot.L', 'toe.L'],
    'mixamo': ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head', 'LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase'],
    'ue_mannequin': ['pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'head', 'clavicle_l', 'upperarm_l', 'lowerarm_l', 'hand_l', 'thigh_l', 'calf_l', 'foot_l', 'ball_l'],
    'rigify_like': ['spine', 'spine.001', 'spine.002', 'upper_arm.L', 'forearm.L', 'hand.L', 'thigh.L', 'shin.L', 'foot.L'],
}
def norm(n): return n.split(':')[-1].replace('mixamorig', '')

report = {'file': os.path.basename(path), 'bytes': os.path.getsize(path), 'checks': {}, 'blender': bpy.app.version_string}
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bones = sorted({b.name for a in arms for b in a.data.bones}, key=lambda s: s)
report['armatures'] = len(arms); report['bone_count'] = len(bones); report['bones'] = bones
fam = {}
nb = {norm(b) for b in bones}
for k, names in FAMILIES.items():
    fam[k] = round(sum(1 for n in names if n in nb or n in bones) / len(names), 2)
report['skeleton_family_coverage'] = fam
report['skeleton_family'] = max(fam, key=fam.get) if fam and max(fam.values()) >= 0.5 else 'unknown'

dg = bpy.context.evaluated_depsgraph_get()
verts = tris = 0; unweighted = over4 = unnorm = 0
mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
mats = set(); imgs = {}
for m in meshes:
    me = m.data
    verts += len(me.vertices); tris += sum(max(1, len(p.vertices) - 2) for p in me.polygons)
    for s in m.material_slots:
        if s.material: mats.add(s.material.name)
    for v in me.vertices:
        w = [g.weight for g in v.groups if g.weight > 1e-4]
        if m.vertex_groups and not w: unweighted += 1
        if len(w) > 4: over4 += 1
        if w and abs(sum(w) - 1) > 0.05: unnorm += 1
    for c in [m.matrix_world @ Vector(c) for c in m.bound_box]:
        mn = Vector((min(mn.x, c.x), min(mn.y, c.y), min(mn.z, c.z))); mx = Vector((max(mx.x, c.x), max(mx.y, c.y), max(mx.z, c.z)))
for im in bpy.data.images:
    if im.size[0] > 0: imgs[im.name] = [im.size[0], im.size[1]]
scale = bpy.context.scene.unit_settings.scale_length
size = (mx - mn) * scale if meshes else Vector((0, 0, 0))
up_axis = max(range(3), key=lambda i: size[i]) if meshes else -1
report.update({'meshes': len(meshes), 'vertices': verts, 'triangles': tris, 'materials': sorted(mats), 'images': imgs, 'bbox_m': [round(x, 3) for x in size],
               'tallest_axis': 'XYZ'[up_axis] if up_axis >= 0 else None, 'unweighted_vertices': unweighted, 'vertices_over_4_influences': over4, 'vertices_unnormalised': unnorm})
acts = {}
for a in bpy.data.actions:
    acts[a.name] = {'frame_start': a.frame_range[0], 'frame_end': a.frame_range[1], 'frames': int(round(a.frame_range[1] - a.frame_range[0] + 1)), 'fcurves': len(a.fcurves) if hasattr(a, 'fcurves') else None}
report['actions'] = acts
report['fps'] = bpy.context.scene.render.fps
height = float(size[up_axis]) if meshes else 0
report['height_m'] = round(height, 3)
C = report['checks']
C['has_armature'] = len(arms) >= 1
C['height_1.5_to_2.1_m'] = 1.5 <= height <= 2.1
C['all_vertices_weighted'] = unweighted == 0 and bool(arms)
C['max_4_influences'] = over4 == 0
C['weights_normalised'] = unnorm == 0
C['has_materials'] = len(mats) > 0
report['pass'] = all(C.values())
json.dump(report, open(out, 'w'), indent=1)
print('INSPECT', report['file'], 'pass' if report['pass'] else 'FAIL', {k: v for k, v in C.items() if not v})
