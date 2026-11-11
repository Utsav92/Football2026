import unreal, math, traceback
def log(*a): print("LC3", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
try:
    for name in ("athlete_cmu_kick_01_Anim", "athlete_cmu_kick_03_Anim", "athlete_cmu_loco_walk_35_01_Anim", "athlete_cmu_loco_jog_35_17_Anim", "athleteskeleton_jog"):
        s = unreal.load_asset(f"/Game/Football/Athlete/{name}"); L = s.get_editor_property("sequence_length"); out = []
        for t in (0.0, L * 0.5):
            p = pose(s, t); h, f, hd = wp(p, "hips"), wp(p, "foot_R"), wp(p, "head")
            out.append(f"t={t:.2f}: hips->footR {math.dist((h.x,h.y,h.z),(f.x,f.y,f.z)):.0f}cm hips->head {math.dist((h.x,h.y,h.z),(hd.x,hd.y,hd.z)):.0f}cm")
        log(name, " | ".join(out))
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
