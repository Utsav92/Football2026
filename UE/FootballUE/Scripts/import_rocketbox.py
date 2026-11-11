import unreal, traceback, os, glob
OUT = "/Users/utsav/Football2026/UE/FootballUE/Saved/py_rbx.txt"; fl = open(OUT, "w")
def log(*a): fl.write(" ".join(str(x) for x in a) + "\n"); fl.flush()
ROOT = os.path.expanduser("~/Football2026/UE/FootballUE/Import/rocketbox_src/rb/Assets/Avatars/Adults")
DEST = "/Game/Football/Rocketbox"; MATS = "/Game/Football/Materials"
NAMES = os.environ.get("RBX_NAMES", "Male_Adult_01,Male_Adult_02,Male_Adult_03,Male_Adult_04,Male_Adult_05,Male_Adult_06,Male_Adult_07,Male_Adult_08,Female_Adult_01").split(",")
tools = unreal.AssetToolsHelpers.get_asset_tools(); L = unreal.MaterialEditingLibrary

def import_tex(path, dest, normal):
    t = unreal.AssetImportTask(); t.set_editor_property("filename", path); t.set_editor_property("destination_path", dest)
    t.set_editor_property("automated", True); t.set_editor_property("replace_existing", True); t.set_editor_property("save", True)
    tools.import_asset_tasks([t])
    objs = t.get_editor_property("imported_object_paths")
    if not objs: return None
    tex = unreal.load_asset(str(objs[0]).split(".")[0])
    if normal: tex.set_editor_property("compression_settings", unreal.TextureCompressionSettings.TC_NORMALMAP); tex.set_editor_property("srgb", False)
    unreal.EditorAssetLibrary.save_loaded_asset(tex); return tex

def make_mi(name, parent, dest, texs):
    full = f"{dest}/{name}"
    if unreal.EditorAssetLibrary.does_asset_exist(full): unreal.EditorAssetLibrary.delete_asset(full)
    mi = tools.create_asset(name, dest, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mi.set_editor_property("parent", unreal.load_asset(f"{MATS}/{parent}"))
    for k, t in texs.items():
        if t: L.set_material_instance_texture_parameter_value(mi, k, t)
    unreal.EditorAssetLibrary.save_loaded_asset(mi); return mi

try:
    first_skel = None
    for nm in NAMES:
        fbx = f"{ROOT}/{nm}/Export/{nm}.fbx"
        if not os.path.exists(fbx): log("missing", fbx); continue
        mpath = f"{DEST}/{nm}/{nm}"
        if not unreal.EditorAssetLibrary.does_asset_exist(mpath):
            ui = unreal.FbxImportUI()
            ui.set_editor_property("import_mesh", True); ui.set_editor_property("import_as_skeletal", True)
            ui.set_editor_property("import_materials", False); ui.set_editor_property("import_textures", False)
            ui.set_editor_property("import_animations", False); ui.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_SKELETAL_MESH)
            ui.skeletal_mesh_import_data.set_editor_property("import_morph_targets", False)
            if first_skel is not None: ui.set_editor_property("skeleton", first_skel)
            task = unreal.AssetImportTask(); task.set_editor_property("filename", fbx); task.set_editor_property("destination_path", f"{DEST}/{nm}")
            task.set_editor_property("automated", True); task.set_editor_property("replace_existing", True); task.set_editor_property("save", True); task.set_editor_property("options", ui)
            tools.import_asset_tasks([task])
        mesh = unreal.load_asset(mpath)
        if not mesh: log("FAILED mesh", nm); continue
        sk = mesh.get_editor_property("skeleton")
        if first_skel is None: first_skel = sk
        log(nm, "skeleton", sk.get_path_name())
        tdir = f"{ROOT}/{nm}/Textures"; td = f"{DEST}/{nm}/Tex"
        pref = os.path.basename(glob.glob(f"{tdir}/*_body_color.tga")[0]).split("_")[0]
        def T(suffix, normal=False):
            p = f"{tdir}/{pref}_{suffix}.tga"
            return import_tex(p, td, normal) if os.path.exists(p) else None
        body = make_mi(f"MI_{nm}_Body", "M_RBX_Body", f"{DEST}/{nm}", {"ColorTex": T("body_color"), "NormalTex": T("body_normal", True)})
        head = make_mi(f"MI_{nm}_Head", "M_RBX_Head", f"{DEST}/{nm}", {"ColorTex": T("head_color"), "NormalTex": T("head_normal", True)})
        hair = make_mi(f"MI_{nm}_Hair", "M_RBX_Hair", f"{DEST}/{nm}", {"ColorTex": T("opacity_color")})
        mats = mesh.get_editor_property("materials"); new = []
        for m in mats:
            s = str(m.material_slot_name).lower(); mi = head if "head" in s else (hair if "opacity" in s else body)
            m.set_editor_property("material_interface", mi); new.append(m)
        mesh.set_editor_property("materials", new); unreal.EditorAssetLibrary.save_loaded_asset(mesh)
        log(nm, "slots", [str(m.material_slot_name) + "->" + m.material_interface.get_name() for m in mesh.get_editor_property("materials")])
except Exception:
    log("EXC", traceback.format_exc())
unreal.EditorAssetLibrary.save_directory(DEST); log("saved")
