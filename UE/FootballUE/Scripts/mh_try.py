import unreal, traceback
def log(*a): print("MHTRY", *a)
try:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    fac = unreal.MetaHumanCharacterFactoryNew()
    asset = tools.create_asset("MH_Test01", "/Game/Football/Characters", unreal.MetaHumanCharacter, fac)
    log("created asset:", asset)
    sub = unreal.get_editor_subsystem(unreal.MetaHumanCharacterEditorSubsystem)
    log("subsystem:", sub)
    ok = sub.try_add_object_to_edit(asset)
    log("try_add_object_to_edit ->", ok)
    log("is_object_added_for_editing ->", sub.is_object_added_for_editing(asset))
    log("can_build_meta_human ->", sub.can_build_meta_human(asset))
    try:
        log("fixed_body_type:", asset.get_editor_property("fixed_body_type"))
    except Exception as e: log("fixed_body_type err", e)
    for fn in ("request_auto_rigging","request_texture_sources","build_meta_human"):
        try:
            doc = getattr(sub, fn).__doc__
            log("DOC", fn, (doc or "")[:600].replace("\n"," | "))
        except Exception as e: log("doc err", fn, e)
    unreal.EditorAssetLibrary.save_asset("/Game/Football/Characters/MH_Test01")
except Exception:
    log("EXC", traceback.format_exc().replace("\n"," | "))
