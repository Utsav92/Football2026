import unreal, math, traceback
def log(*a): print("RV", *a, flush=True)
def pose(seq, t):
    return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wpos(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
def sub(a, b): return unreal.Vector(a.x-b.x, a.y-b.y, a.z-b.z)
def ang(a, b):
    la, lb = math.sqrt(a.x**2+a.y**2+a.z**2), math.sqrt(b.x**2+b.y**2+b.z**2)
    if la < 1e-6 or lb < 1e-6: return float('nan')
    d = (a.x*b.x+a.y*b.y+a.z*b.z)/(la*lb); return math.degrees(math.acos(max(-1, min(1, d))))
try:
    pairs = [("hips->head", ("root","head"), ("hips","head")), ("hips->R foot", ("root","rfoot"), ("hips","foot_R")), ("hips->L foot", ("root","lfoot"), ("hips","foot_L")),
             ("R knee->foot", ("rtibia","rfoot"), ("shin_R","foot_R")), ("R shoulder->wrist", ("rhumerus","rwrist"), ("upper_arm_R","hand_R")), ("L shoulder->wrist", ("lhumerus","lwrist"), ("upper_arm_L","hand_L"))]
    for c in ("01", "03"):
        s = unreal.load_asset(f"/Game/Football/Mocap/cmu_kick_{c}_Anim"); t = unreal.load_asset(f"/Game/Football/Athlete/athlete_cmu_kick_{c}_Anim")
        log(f"clip {c}: source {s.get_editor_property('sequence_length'):.3f}s -> target {t.get_editor_property('sequence_length'):.3f}s")
        worst = 0
        for tt in (0.0, 0.25, 0.5, 0.55, 0.75, 0.95):
            ps, pt = pose(s, tt), pose(t, tt); row = []
            for nm, (sa, sb), (ta, tb) in pairs:
                a = ang(sub(wpos(ps, sb), wpos(ps, sa)), sub(wpos(pt, tb), wpos(pt, ta))); row.append(f"{nm} {a:.0f}"); worst = max(worst, a if a == a else 0)
            log(f"  t={tt:.2f}s  angle diff (deg): " + ", ".join(row))
        log(f"  worst limb-direction difference clip {c}: {worst:.0f} deg")
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
