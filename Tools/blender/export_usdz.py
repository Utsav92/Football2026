"""Export the current/opened scene to USDZ with the project's standard settings (Y-up, -Z forward, metres, skeleton + skinned meshes).
  Blender -b <file.blend|fbx> --python Tools/blender/export_usdz.py -- out.usdz [--animation]"""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.usd_export(filepath=argv[0], export_animation='--animation' in argv, export_armatures=True, export_meshes=True, export_materials=True,
                      generate_preview_surface=True, export_uvmaps=False, export_normals=True, convert_orientation=True,
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', root_prim_path='/Player',
                      convert_scene_units='METERS', xform_op_mode='TRS', triangulate_meshes=True)
print('EXPORTED', argv[0])
