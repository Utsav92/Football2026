import unreal, traceback, sys
OUT = unreal.Paths.project_saved_dir() + "py_mh_make.txt"
f = open(OUT, "w")
def log(*a): f.write(" ".join(str(x) for x in a) + "\n"); f.flush()
SKINS = [(0.15,0.75),(0.35,0.55),(0.5,0.45),(0.65,0.35),(0.8,0.25),(0.9,0.15)]
N = int(unreal.SystemLibrary.get_command_line().split("-mhn=")[1].split()[0]) if "-mhn=" in unreal.SystemLibrary.get_command_line() else 1
try:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    sub = unreal.get_editor_subsystem(unreal.MetaHumanCharacterEditorSubsystem)
    for i in range(N):
        name = f"MHP_{i+1:02d}"
        path = "/Game/Football/Characters"
        ch = unreal.load_asset(f"{path}/{name}") or tools.create_asset(name, path, unreal.MetaHumanCharacter, unreal.MetaHumanCharacterFactoryNew())
        log("asset", name, ch)
        if not sub.try_add_object_to_edit(ch): log("cannot edit", name); continue
        try:
            ss = unreal.MetaHumanCharacterSkinSettings()
            ss.skin.u, ss.skin.v = SKINS[i % 6]
            ss.skin.face_texture_index = i % 6; ss.skin.body_texture_index = i % 6
            ss.skin.show_top_underwear = False
            ss.texture_material_overrides.enable_texture_overrides = False
            ch.preview_material_type = unreal.MetaHumanCharacterSkinPreviewMaterial.EDITABLE
            sub.commit_skin_settings(ch, ss); log("skin ok")
            ap = unreal.MetaHumanCharacterAutoRiggingRequestParams(); ap.blocking = True; ap.report_progress = False
            ap.rig_type = unreal.MetaHumanRigType.JOINTS_ONLY
            sub.request_auto_rigging(ch, ap); log("rig requested")
            tp = unreal.MetaHumanCharacterTextureRequestParams(); tp.blocking = True; tp.report_progress = False
            sub.request_texture_sources(ch, tp)
            log("hires", ch.has_high_resolution_textures, "can_build", sub.can_build_meta_human(ch))
            if sub.can_build_meta_human(ch):
                bp = unreal.MetaHumanCharacterEditorBuildParameters()
                bp.pipeline_type = unreal.MetaHumanDefaultPipelineType.OPTIMIZED
                bp.pipeline_quality = unreal.MetaHumanQualityLevel.MEDIUM
                bp.absolute_build_path = "/Game/MetaHumans"; bp.common_folder_path = "/Game/MetaHumans/Common"
                bp.enable_wardrobe_item_validation = False
                sub.build_meta_human(ch, bp); log("built", name)
        finally:
            if sub.is_object_added_for_editing(ch): sub.remove_object_to_edit(ch)
            unreal.EditorAssetLibrary.save_asset(f"{path}/{name}")
except Exception:
    log("EXC", traceback.format_exc())
log("DONE")
