import unreal, os, traceback
def log(*a): print("MOCAP", *a, flush=True)
dest = "/Game/Football/Mocap"; proj = unreal.Paths.project_dir()
def run(fbx, skeleton=None, mesh=True):
    opts = unreal.FbxImportUI()
    opts.set_editor_property("import_mesh", mesh); opts.set_editor_property("import_as_skeletal", True)
    opts.set_editor_property("import_animations", True); opts.set_editor_property("import_materials", False); opts.set_editor_property("import_textures", False)
    opts.set_editor_property("create_physics_asset", False); opts.set_editor_property("automated_import_should_detect_type", False)
    opts.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_SKELETAL_MESH)
    if skeleton: opts.set_editor_property("skeleton", skeleton)
    t = unreal.AssetImportTask(); t.set_editor_property("filename", os.path.join(proj, fbx)); t.set_editor_property("destination_path", dest)
    t.set_editor_property("automated", True); t.set_editor_property("replace_existing", True); t.set_editor_property("save", True); t.set_editor_property("options", opts)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t]); return [str(p) for p in t.get_editor_property("imported_object_paths")]
try:
    log("first:", run("Import/mocap/cmu_kick_01.fbx"))
    sk = unreal.load_asset(dest + "/cmu_kick_01_Skeleton")
    for c in ("02", "03", "05", "06"): log("anim", c, run(f"Import/mocap/cmu_kick_{c}.fbx", skeleton=sk, mesh=False))
    for a in unreal.EditorAssetLibrary.list_assets(dest):
        d = unreal.EditorAssetLibrary.find_asset_data(a); extra = ""
        if str(d.asset_class_path.asset_name) == "AnimSequence":
            q = unreal.load_asset(a); extra = f"len {q.get_editor_property('sequence_length'):.3f}s frames {q.get_editor_property('number_of_sampled_frames')}"
        log("have", d.asset_class_path.asset_name, a, extra)
except Exception: log("EXC", traceback.format_exc().replace("\n"," | "))
