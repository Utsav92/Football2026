import unreal, os, traceback
def log(*a): print("LOCO", *a, flush=True)
D = "/Game/Football/Mocap"; proj = unreal.Paths.project_dir(); names = ["walk_35_01", "jog_35_17", "jog_35_23"]
try:
    sk = unreal.load_asset(D + "/cmu_kick_01_Skeleton"); cmu_mesh = unreal.load_asset(D + "/cmu_kick_01"); ath_mesh = unreal.load_asset("/Game/Football/Athlete/athlete")
    for n in names:
        opts = unreal.FbxImportUI(); opts.set_editor_property("import_mesh", False); opts.set_editor_property("import_as_skeletal", True)
        opts.set_editor_property("import_animations", True); opts.set_editor_property("import_materials", False); opts.set_editor_property("import_textures", False)
        opts.set_editor_property("automated_import_should_detect_type", False); opts.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_SKELETAL_MESH); opts.set_editor_property("skeleton", sk)
        t = unreal.AssetImportTask(); t.set_editor_property("filename", os.path.join(proj, f"Import/loco/cmu_loco_{n}.fbx")); t.set_editor_property("destination_path", D)
        t.set_editor_property("automated", True); t.set_editor_property("replace_existing", True); t.set_editor_property("save", True); t.set_editor_property("options", opts)
        unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t]); log("imported", n, [str(p) for p in t.get_editor_property("imported_object_paths")])
    unreal.EditorAssetLibrary.save_directory(D); log('saved (retarget happens in retarget_mocap.py, same session as rig setup)')
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
