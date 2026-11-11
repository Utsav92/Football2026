import unreal, traceback
def log(*a): print("GS", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
def measure(path, hips, feet, n=60):
    s = unreal.load_asset(path); L = s.get_editor_property("sequence_length"); out = {}
    for foot in feet:
        ys, zs = [], []
        for i in range(n + 1):
            p = pose(s, L * i / n); ys.append(wp(p, foot).y - wp(p, hips).y); zs.append(wp(p, foot).z)
        lo = min(zs); thr = lo + 0.25 * (max(zs) - lo); v = []   # ground-contact frames: foot within the lowest quarter of its height range
        for i in range(n):
            if zs[i] <= thr and zs[i + 1] <= thr: v.append((ys[i + 1] - ys[i]) / (L / n))
        out[foot] = (sum(v) / len(v) / 100.0 if v else float('nan'), len(v))
    return out, L
try:
    for label, path, hips, feet, gs in (("CMU source jog 35_17", "/Game/Football/Mocap/cmu_loco_jog_35_17_Anim", "root", ("lfoot", "rfoot"), 3.153),
                                        ("athlete retarget jog 35_17", "/Game/Football/Athlete/athlete_cmu_loco_jog_35_17_Anim", "hips", ("foot_L", "foot_R"), 3.153),
                                        ("CMU source walk 35_01", "/Game/Football/Mocap/cmu_loco_walk_35_01_Anim", "root", ("lfoot", "rfoot"), 1.287),
                                        ("athlete retarget walk 35_01", "/Game/Football/Athlete/athlete_cmu_loco_walk_35_01_Anim", "hips", ("foot_L", "foot_R"), 1.287)):
        m, L = measure(path, hips, feet); log(f"{label}: cycle {L:.3f}s, true ground speed {gs} m/s, stance-foot speed vs hips (m/s): " + ", ".join(f"{k} {v[0]:.2f} (n={v[1]})" for k, v in m.items()))
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
