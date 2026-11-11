import bpy, sys, os, math
from mathutils import Vector, Euler
a = sys.argv[sys.argv.index('--') + 1:]
def fcurves(act):
    """Action F-curves for both the legacy API and Blender 5's layered actions."""
    if hasattr(act, 'fcurves'): return list(act.fcurves)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for slot in act.slots:
                cb = strip.channelbag(slot)
                if cb: out += list(cb.fcurves)
    return out
def opt(n, d=None): return a[a.index(n) + 1] if n in a else d
MAPS = {
  'mixamo': {'hips': 'Hips', 'spine': 'Spine', 'chest': 'Spine2', 'neck': 'Neck', 'head': 'Head', 'clavicle.L': 'LeftShoulder', 'upper_arm.L': 'LeftArm', 'forearm.L': 'LeftForeArm', 'hand.L': 'LeftHand',
             'thigh.L': 'LeftUpLeg', 'shin.L': 'LeftLeg', 'foot.L': 'LeftFoot', 'toe.L': 'LeftToeBase', 'clavicle.R': 'RightShoulder', 'upper_arm.R': 'RightArm', 'forearm.R': 'RightForeArm',
             'hand.R': 'RightHand', 'thigh.R': 'RightUpLeg', 'shin.R': 'RightLeg', 'foot.R': 'RightFoot', 'toe.R': 'RightToeBase'},
  'ue': {'hips': 'pelvis', 'spine': 'spine_01', 'chest': 'spine_03', 'neck': 'neck_01', 'head': 'head', 'clavicle.L': 'clavicle_l', 'upper_arm.L': 'upperarm_l', 'forearm.L': 'lowerarm_l', 'hand.L': 'hand_l',
         'thigh.L': 'thigh_l', 'shin.L': 'calf_l', 'foot.L': 'foot_l', 'toe.L': 'ball_l', 'clavicle.R': 'clavicle_r', 'upper_arm.R': 'upperarm_r', 'forearm.R': 'lowerarm_r', 'hand.R': 'hand_r',
         'thigh.R': 'thigh_r', 'shin.R': 'calf_r', 'foot.R': 'foot_r', 'toe.R': 'ball_r'}}

dst = bpy.data.objects['skeleton']
selftest = '--selftest' in a
if selftest:
    mp = MAPS['mixamo']
    arm = bpy.data.armatures.new('src'); src = bpy.data.objects.new('src', arm); bpy.context.scene.collection.objects.link(src)
    bpy.context.view_layer.objects.active = src; bpy.ops.object.mode_set(mode='EDIT')
    for ours, theirs in mp.items():
        h, t = dst.data.bones[ours].head_local.copy(), dst.data.bones[ours].tail_local.copy()
        b = arm.edit_bones.new('mixamorig:' + theirs); b.head, b.tail = h, t
    bpy.ops.object.mode_set(mode='OBJECT')
    src.animation_data_create(); act = bpy.data.actions.new('synthetic'); src.animation_data.action = act
    pb = src.pose.bones['mixamorig:LeftUpLeg']; pb.rotation_mode = 'XYZ'
    for f in range(1, 21): pb.rotation_euler = Euler((math.radians(40) * math.sin(f / 20 * 2 * math.pi), 0, 0)); pb.keyframe_insert('rotation_euler', frame=f)
    name, mapname, outdir = 'selftest', 'mixamo', '/tmp'
else:
    bpy.ops.import_scene.fbx(filepath=opt('--source'))
    src = [o for o in bpy.data.objects if o.type == 'ARMATURE' and o != dst][0]
    name, mapname, outdir = opt('--name', 'clip'), opt('--map', 'mixamo'), opt('--out', '.')
mp = MAPS[mapname]
names = {b.name.split(':')[-1]: b.name for b in src.data.bones}
rng = src.animation_data.action.frame_range
for ours, theirs in mp.items():
    if theirs not in names: continue
    if ours == 'hips': continue                         # root motion stripped
    c = dst.pose.bones[ours].constraints.new('COPY_ROTATION'); c.target = src; c.subtarget = names[theirs]
    c.target_space = 'WORLD'; c.owner_space = 'WORLD'
bpy.context.view_layer.objects.active = dst; dst.select_set(True)
bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.select_all(action='SELECT')
bpy.ops.nla.bake(frame_start=int(rng[0]), frame_end=int(rng[1]), only_selected=True, visual_keying=True, clear_constraints=True, bake_types={'POSE'})
bpy.ops.object.mode_set(mode='OBJECT')
act = dst.animation_data.action; act.name = name
keyed = {fc.data_path.split('"')[1] for fc in fcurves(act) if 'pose.bones' in fc.data_path}
print('RETARGET', name, 'frames', int(rng[0]), int(rng[1]), 'bones keyed:', len(keyed))
if selftest:
    ok = 'thigh.L' in keyed and any(fc.data_path.endswith('rotation_quaternion') and 'thigh.L' in fc.data_path and max(k.co[1] for k in fc.keyframe_points) - min(k.co[1] for k in fc.keyframe_points) > 0.05 for fc in fcurves(act))
    print('SELFTEST', 'PASS' if ok else 'FAIL', '- left thigh animation transferred onto our skeleton')
    sys.exit(0 if ok else 3)
bpy.context.scene.frame_start, bpy.context.scene.frame_end = int(rng[0]), int(rng[1])
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.usd_export(filepath=os.path.join(outdir, f'anim_{name}.usdz'), export_animation=True, export_armatures=True, export_meshes=True, export_materials=True, generate_preview_surface=True,
                      convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', root_prim_path='/Player', xform_op_mode='TRS', triangulate_meshes=True)
print('EXPORTED', os.path.join(outdir, f'anim_{name}.usdz'))
