import unreal, traceback
def log(*a): print("SK", *a, flush=True)
try:
    for path in ("/Game/Football/Athlete/athleteskeleton_idle", "/Game/Football/Athlete/athlete_cmu_loco_jog_35_17_Anim", "/Game/Football/Mocap/cmu_kick_01_Anim"):
        s = unreal.load_asset(path); p = unreal.AnimPoseExtensions.get_anim_pose_at_time(s, 0.1, unreal.AnimPoseEvaluationOptions())
        names = [str(x) for x in unreal.AnimPoseExtensions.get_bone_names(p)]
        log(path.split("/")[-1], "n", len(names), names[:4])
        for b in names[:3]:
            w = unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD); l = unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.LOCAL)
            log("   ", b, "world S", [round(x, 3) for x in (w.scale3d.x, w.scale3d.y, w.scale3d.z)], "local S", [round(x, 3) for x in (l.scale3d.x, l.scale3d.y, l.scale3d.z)], "local T", [round(x, 2) for x in (l.translation.x, l.translation.y, l.translation.z)])
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
