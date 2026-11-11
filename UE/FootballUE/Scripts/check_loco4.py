import unreal, math, traceback
def log(*a): print("LC4", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
def lp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.LOCAL).translation
try:
    bones = ["hips","spine","chest","neck","head","clavicle_L","upper_arm_L","hand_L","thigh_L","shin_L","foot_L","toe_L"]
    for name in ("athleteskeleton_idle", "athlete_cmu_loco_jog_35_17_Anim"):
        s = unreal.load_asset(f"/Game/Football/Athlete/{name}"); p = pose(s, 0.1)
        log(name, "WORLD", {b: tuple(round(x) for x in (wp(p,b).x, wp(p,b).y, wp(p,b).z)) for b in bones})
        log(name, "LOCAL", {b: tuple(round(x, 1) for x in (lp(p,b).x, lp(p,b).y, lp(p,b).z)) for b in bones})
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
