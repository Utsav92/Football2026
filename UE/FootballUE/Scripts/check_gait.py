import unreal, traceback
def log(*a): print("GAIT", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
try:
    import json, os
    meta = {"loco_walk_35_01": 1.287, "loco_jog_35_17": 3.153, "loco_jog_35_23": 3.407}
    for clip in ("walk", "jog", "sprint", "loco_walk_35_01", "loco_jog_35_17", "loco_jog_35_23"):
        path = f"/Game/Football/Athlete/athleteskeleton_{clip}" if not clip.startswith("loco") else f"/Game/Football/Athlete/athlete_cmu_{clip}_Anim"
        s = unreal.load_asset(path); L = s.get_editor_property("sequence_length"); n = 40
        res = {}
        for foot in ("foot_L", "foot_R"):
            ys, zs = [], []
            for i in range(n + 1):
                p = pose(s, L * i / n); h = wp(p, "hips"); f = wp(p, foot); ys.append(f.y - h.y); zs.append(f.z)
            # during ground contact (lowest 35% of foot heights) the foot should move BACKWARD relative to the hips (negative forward velocity) for a forward gait; forward axis is +Y
            thr = sorted(zs)[int(0.35 * n)]; v = []
            for i in range(n):
                if zs[i] <= thr and zs[i + 1] <= thr + 1.0: v.append((ys[i + 1] - ys[i]) / (L / n))
            res[foot] = (sum(v) / len(v) if v else float('nan'), len(v))
        gs = meta.get(clip); extra = f" | CMU ground speed {gs} m/s" if gs else ""
        log(f"{clip}{extra}: stance-foot velocity relative to hips along +Y (cm/s): L {res['foot_L'][0]:.0f} (n={res['foot_L'][1]}), R {res['foot_R'][0]:.0f} (n={res['foot_R'][1]})  -> {'FORWARD gait' if res['foot_L'][0] < 0 and res['foot_R'][0] < 0 else 'BACKWARD gait (moonwalk)' if res['foot_L'][0] > 0 and res['foot_R'][0] > 0 else 'mixed'}")
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
