import unreal, math, traceback
def log(*a): print("YAW", *a, flush=True)
def pose(seq, t): return unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, unreal.AnimPoseEvaluationOptions())
def wp(p, b): return unreal.AnimPoseExtensions.get_bone_pose(p, b, unreal.AnimPoseSpaces.WORLD).translation
def yaw_of_forward(p, l, r):
    a, b = wp(p, l), wp(p, r); sx, sy = b.x - a.x, b.y - a.y      # left->right vector
    # forward = rotate (left->right) by +90deg about Z in UE (X->Y): for a character facing +Y, left->right is -X; rotating -X by +90 deg gives -Y... so use the cross: fwd = (-sy*-1 ...)
    fx, fy = sy, -sx   # for left->right = (-1,0): fwd = (0, 1) = +Y
    return math.degrees(math.atan2(fy, fx))   # angle from +X toward +Y; +Y -> 90
try:
    names = ["loco_walk_35_01", "loco_jog_35_17", "loco_jog_35_23", "kick_01", "kick_02", "kick_03", "kick_05", "kick_06"]
    items = tuple((f"CMU retarget {n}", f"/Game/Football/Athlete/athlete_cmu_{n}_Anim", "thigh_L", "thigh_R", "clavicle_L", "clavicle_R") for n in names)
    for name, path, hl, hr, cl, cr in items:
        s = unreal.load_asset(path); L = s.get_editor_property("sequence_length"); ys = []; ysh = []
        for t in (0.0, L * 0.2, L * 0.4, L * 0.6, L * 0.8):
            p = pose(s, t); ys.append(yaw_of_forward(p, hl, hr)); ysh.append(yaw_of_forward(p, cl, cr))
        log(f"{name}: hip-axis facing yaw {[round(y) for y in ys]} | shoulder-axis facing yaw {[round(y) for y in ysh]}   (90 = faces +Y)")
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
