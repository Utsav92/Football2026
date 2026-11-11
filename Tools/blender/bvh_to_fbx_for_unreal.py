"""Import a CMU-derived BVH, add a tiny dummy mesh bound to the root (so Unreal creates a skeletal mesh for IK Rig use) and export FBX
with the same axis/scale settings as export_fbx_for_unreal.py.   Blender -b --python bvh_to_fbx_for_unreal.py -- in.bvh out.fbx clipname"""
import bpy, sys
src, out, clip = sys.argv[sys.argv.index('--') + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.context.scene.unit_settings.system = 'METRIC'; bpy.context.scene.unit_settings.scale_length = 0.01; bpy.context.scene.unit_settings.length_unit = 'CENTIMETERS'
bpy.ops.import_anim.bvh(filepath=src, axis_forward='-Z', axis_up='Y', global_scale=100.0, rotate_mode='NATIVE', use_fps_scale=True, update_scene_fps=False, update_scene_duration=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE'); arm.name = 'cmu_skeleton'
if arm.animation_data and arm.animation_data.action: arm.animation_data.action.name = clip
# dummy mesh weighted to the root bone
bpy.ops.mesh.primitive_cube_add(size=5.0, location=arm.matrix_world @ arm.data.bones[0].head_local)
cube = bpy.context.active_object; cube.name = 'cmu_dummy_mesh'
vg = cube.vertex_groups.new(name=arm.data.bones[0].name); vg.add(list(range(len(cube.data.vertices))), 1.0, 'REPLACE')
mod = cube.modifiers.new('Armature', 'ARMATURE'); mod.object = arm; cube.parent = arm
bpy.ops.object.select_all(action='DESELECT'); cube.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active = arm
fr = arm.animation_data.action.frame_range
bpy.context.scene.frame_start, bpy.context.scene.frame_end = int(fr[0]), int(fr[1])
bpy.ops.export_scene.fbx(filepath=out, use_selection=True, object_types={'ARMATURE', 'MESH'}, add_leaf_bones=False, apply_scale_options='FBX_SCALE_NONE', global_scale=1.0,
    axis_forward='-Y', axis_up='Z', bake_space_transform=False, armature_nodetype='NULL', bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
    bake_anim_force_startend_keying=True, bake_anim_step=1.0, bake_anim_simplify_factor=0.0)
print('EXPORTED', out, 'frames', int(fr[1] - fr[0]) + 1, 'bones', len(arm.data.bones))
