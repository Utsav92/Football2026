import unreal, traceback, os
def log(*a): print("IMPORT", *a, flush=True)
fbx = os.path.join(unreal.Paths.project_dir(), "Import/athlete.fbx")
dest = "/Game/Football/Athlete"
try:
    opts = unreal.FbxImportUI()
    opts.set_editor_property("import_mesh", True)
    opts.set_editor_property("import_as_skeletal", True)
    opts.set_editor_property("import_animations", True)
    opts.set_editor_property("import_materials", True)
    opts.set_editor_property("import_textures", False)
    opts.set_editor_property("create_physics_asset", True)
    opts.set_editor_property("automated_import_should_detect_type", False)
    opts.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_SKELETAL_MESH)
    smd = opts.get_editor_property("skeletal_mesh_import_data")
    smd.set_editor_property("import_morph_targets", False)
    smd.set_editor_property("update_skeleton_reference_pose", False)
    asd = opts.get_editor_property("anim_sequence_import_data")
    log("anim import props:", [p for p in dir(asd) if not p.startswith('_') and not callable(getattr(asd,p,None))][:40])
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", fbx); task.set_editor_property("destination_path", dest)
    task.set_editor_property("automated", True); task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True); task.set_editor_property("options", opts)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    log("imported objects:", [str(o) for o in task.get_editor_property("imported_object_paths")])
except Exception:
    log("EXC", traceback.format_exc().replace("\n"," | "))
for a in unreal.EditorAssetLibrary.list_assets(dest, recursive=True):
    d = unreal.EditorAssetLibrary.find_asset_data(a); log("ASSET", d.asset_class_path.asset_name, a)
