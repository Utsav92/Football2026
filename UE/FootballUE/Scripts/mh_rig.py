import unreal, time, traceback
def log(*a): print("MHRIG", *a, flush=True)
state = {"t0": time.time(), "step": 0, "done": False}
try:
    rt = unreal.MetaHumanRigType
    log("rig types:", [n for n in dir(rt) if n.isupper()])
    log("build params props:", [n for n in dir(unreal.MetaHumanCharacterEditorBuildParameters) if not n.startswith('_') and not callable(getattr(unreal.MetaHumanCharacterEditorBuildParameters, n, None))][:30])
    asset = unreal.load_asset("/Game/Football/Characters/MH_Test01")
    sub = unreal.get_editor_subsystem(unreal.MetaHumanCharacterEditorSubsystem)
    log("added:", sub.try_add_object_to_edit(asset))
    p = unreal.MetaHumanCharacterAutoRiggingRequestParams()
    log("autorig params props:", [n for n in dir(p) if not n.startswith('_') and not callable(getattr(p, n, None))])
    sub.request_auto_rigging(asset, p)
    log("auto-rig requested")
    sub.request_texture_sources(asset, unreal.MetaHumanCharacterTextureRequestParams())
    log("texture sources requested")
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | ")); state["done"] = True

def tick(dt):
    if state["done"]: return
    el = time.time() - state["t0"]
    if int(el) % 15 == 0 and int(el) != state.get("last", -1):
        state["last"] = int(el)
        try:
            a = unreal.load_asset("/Game/Football/Characters/MH_Test01")
            s = unreal.get_editor_subsystem(unreal.MetaHumanCharacterEditorSubsystem)
            log(f"t={int(el)}s can_build={s.can_build_meta_human(a)} has_hires={a.has_high_resolution_textures()}")
        except Exception as e: log("poll err", e)
    if el > 420:
        log("timeout; saving and quitting"); state["done"] = True
        unreal.EditorAssetLibrary.save_asset("/Game/Football/Characters/MH_Test01")
        unreal.SystemLibrary.execute_console_command(None, "quit")
h = unreal.register_slate_post_tick_callback(tick)
