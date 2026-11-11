import unreal, traceback
def log(*a): print("LC", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
try:
    for path, bones in (("/Game/Football/Mocap/cmu_loco_jog_35_17_Anim", ("root", "lfoot", "rfoot")), ("/Game/Football/Athlete/athlete_loco_jog_35_17_Anim", ("hips", "foot_L", "foot_R")),
                        ("/Game/Football/Mocap/cmu_kick_01_Anim", ("root", "lfoot", "rfoot"))):
        s = unreal.load_asset(path); L = s.get_editor_property("sequence_length"); log(path.split("/")[-1], "len", round(L, 3), "frames", s.get_editor_property("number_of_sampled_frames"))
        for t in (0.0, L * 0.25, L * 0.5, L * 0.75):
            p = pose(s, t); log("  t=%.2f" % t, {b: (round(wp(p, b).x), round(wp(p, b).y), round(wp(p, b).z)) for b in bones})
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
