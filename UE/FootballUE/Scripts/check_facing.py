import unreal, traceback
def log(*a): print("FACE", *a, flush=True)
try:
    seq = unreal.load_asset("/Game/Football/Athlete/athleteskeleton_idle")
    pose = unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, 0.0, unreal.AnimPoseEvaluationOptions())
    def w(b): return unreal.AnimPoseExtensions.get_bone_pose(pose, b, unreal.AnimPoseSpaces.WORLD).translation
    for a, b in (("foot_L","toe_L"),("foot_R","toe_R"),("thigh_L","thigh_R"),("hips","head")):
        pa, pb = w(a), w(b); log(f"{a}->{b}", "dx", round(pb.x-pa.x,2), "dy", round(pb.y-pa.y,2), "dz", round(pb.z-pa.z,2))
except Exception:
    log("EXC", traceback.format_exc().replace("\n"," | "))
