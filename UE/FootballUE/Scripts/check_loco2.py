import unreal, traceback
def log(*a): print("LC2", *a, flush=True)
try:
    for path, bones in (("/Game/Football/Athlete/athlete_loco_jog_35_17_Anim", ("hips", "thigh_L", "shin_L", "foot_L")), ("/Game/Football/Athlete/athlete_cmu_kick_01_Anim", ("hips", "thigh_L", "shin_L", "foot_L"))):
        s = unreal.load_asset(path); log(path.split("/")[-1], "skeleton:", s.get_editor_property("skeleton").get_path_name() if s.get_editor_property("skeleton") else None)
        for b in bones:
            tr = unreal.AnimationLibrary.get_bone_pose_for_time(s, b, 0.2, False)
            log("  ", b, "T", [round(x, 1) for x in (tr.translation.x, tr.translation.y, tr.translation.z)], "S", [round(x, 3) for x in (tr.scale3d.x, tr.scale3d.y, tr.scale3d.z)])
    sk = unreal.load_asset("/Game/Football/Athlete/athlete_Skeleton"); ref = unreal.load_asset("/Game/Football/Athlete/athleteskeleton_idle")
    for b in ("thigh_L", "shin_L", "foot_L"):
        tr = unreal.AnimationLibrary.get_bone_pose_for_time(ref, b, 0.0, False); log("  idle clip", b, "T", [round(x, 1) for x in (tr.translation.x, tr.translation.y, tr.translation.z)], "S", [round(x, 3) for x in (tr.scale3d.x, tr.scale3d.y, tr.scale3d.z)])
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
