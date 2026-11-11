"""
Original football athlete for Football 2026: skinned mesh + armature + football animation clips, exported to USDZ for RealityKit.

  Blender --background --python Tools/blender/make_football_player.py -- <out_dir> [--lods] [--clips idle,jog,...]

Outputs (out_dir):  player_lod0.usdz (+ _lod1/_lod2 with --lods)   mesh + skeleton + materials, no animation
                    anim_<clip>.usdz                               skeleton + SkelAnimation only (export_meshes=False)
                    player.json                                    bone list, material slots, clip table (fps, frames, loop, contact frame)

Conventions (Blender, Z up): character faces -Y, +X is the character's left, metres, feet at z=0.
USD export converts to Y-up with forward = -Z. Poses are authored with *absolute* bone orientations (rotations about world axes
applied to the rest orientation), so every clip is explicit and order-independent.
Everything here is original work (no third-party assets); see Documentation/ASSET_PIPELINE.md.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector, Matrix, Euler

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else '/tmp/football_player'
WANT_LODS = '--lods' in argv
CLIP_MESH = True                    # RealityKit only exposes animations on files that contain a skinned mesh
CLIPS_ARG = argv[argv.index('--clips') + 1].split(',') if '--clips' in argv else None
FPS = 30
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ skeleton (rest pose)
def V(x, y, z): return Vector((x, y, z))
BONES = {  # name: (head, tail, parent)
    'hips':      (V(0, 0, 0.95),        V(0, 0, 1.05),        None),
    'spine':     (V(0, 0, 1.05),        V(0, 0, 1.32),        'hips'),
    'chest':     (V(0, 0, 1.32),        V(0, 0, 1.50),        'spine'),
    'neck':      (V(0, 0, 1.50),        V(0, 0, 1.62),        'chest'),
    'head':      (V(0, 0, 1.62),        V(0, 0, 1.84),        'neck'),
}
for side, sx in (('L', 1), ('R', -1)):
    BONES.update({
        f'clavicle.{side}': (V(sx * 0.03, 0, 1.47), V(sx * 0.17, 0, 1.47), 'chest'),
        f'upper_arm.{side}': (V(sx * 0.17, 0, 1.47), V(sx * 0.31, 0, 1.24), f'clavicle.{side}'),
        f'forearm.{side}':  (V(sx * 0.31, 0, 1.24), V(sx * 0.37, 0, 1.01), f'upper_arm.{side}'),
        f'hand.{side}':     (V(sx * 0.37, 0, 1.01), V(sx * 0.40, 0, 0.89), f'forearm.{side}'),
        f'thigh.{side}':    (V(sx * 0.09, 0, 0.93), V(sx * 0.095, 0, 0.52), 'hips'),
        f'shin.{side}':     (V(sx * 0.095, 0, 0.52), V(sx * 0.095, 0, 0.10), f'thigh.{side}'),
        f'foot.{side}':     (V(sx * 0.095, 0, 0.10), V(sx * 0.095, -0.17, 0.045), f'shin.{side}'),
        f'toe.{side}':      (V(sx * 0.095, -0.17, 0.045), V(sx * 0.095, -0.25, 0.035), f'foot.{side}'),
    })
ORDER = list(BONES.keys())          # parents precede children

# ------------------------------------------------------------------ mesh: union of capsules -> voxel remesh
def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def add_blob(bm, a, b, ra, rb, seg=16):
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-6:
        r = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=10, radius=ra)
        bmesh.ops.translate(bm, vec=a, verts=r['verts']); return
    new = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=ra, radius2=rb, depth=d.length)['verts']
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=new)
    for p, r in ((a, ra), (b, rb)):
        s = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=10, radius=r)['verts']
        bmesh.ops.translate(bm, vec=p, verts=s)

def build_body(height=1.80, build=0.5, voxel=0.022):
    k = height / 1.84
    w = 0.92 + 0.2 * build
    bm = bmesh.new()
    def B(a, b, ra, rb): add_blob(bm, (a[0] * k * w if abs(a[0]) > 0 else 0, a[1], a[2] * k), (b[0] * k * w if abs(b[0]) > 0 else 0, b[1], b[2] * k), ra * k * w, rb * k * w)
    B((0, 0.0, 0.98), (0, 0, 1.06), 0.16, 0.15)                 # pelvis
    B((0, 0.0, 1.06), (0, 0, 1.34), 0.15, 0.17)                 # abdomen/chest
    B((0, 0.0, 1.34), (0, 0, 1.50), 0.17, 0.16)                 # ribcage / shoulders
    B((-0.20, 0, 1.47), (0.20, 0, 1.47), 0.07, 0.07)            # shoulder girdle
    B((0, 0, 1.50), (0, 0, 1.63), 0.06, 0.055)                  # neck
    B((0, 0.0, 1.69), (0, -0.01, 1.74), 0.105, 0.10)            # head
    B((0, -0.095, 1.69), (0, -0.115, 1.69), 0.03, 0.025)        # nose
    for sx in (1, -1):
        B((sx * 0.17, 0, 1.47), (sx * 0.31, 0, 1.24), 0.058, 0.050)   # upper arm (A-pose)
        B((sx * 0.31, 0, 1.24), (sx * 0.37, 0, 1.01), 0.048, 0.040)   # forearm
        B((sx * 0.37, 0, 1.01), (sx * 0.40, 0, 0.89), 0.038, 0.032)   # hand
        B((sx * 0.09, 0, 0.95), (sx * 0.095, 0, 0.52), 0.092, 0.068)  # thigh
        B((sx * 0.095, 0, 0.52), (sx * 0.095, 0, 0.12), 0.066, 0.048) # shin
        B((sx * 0.095, 0, 0.09), (sx * 0.095, -0.20, 0.05), 0.050, 0.040)  # foot
    me = bpy.data.meshes.new('body'); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new('body', me); bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    m = ob.modifiers.new('remesh', 'REMESH'); m.mode = 'VOXEL'; m.voxel_size = voxel; m.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier='remesh')
    sm = ob.modifiers.new('smooth', 'SMOOTH'); sm.factor = 0.8; sm.iterations = 6
    bpy.ops.object.modifier_apply(modifier='smooth')
    return ob

MAT_SLOTS = ['skin', 'shirt', 'shorts', 'socks', 'boots']
def make_materials(ob, skin=(0.78, 0.56, 0.42), shirt=(0.85, 0.1, 0.12), shorts=(1, 1, 1), socks=(0.85, 0.1, 0.12)):
    cols = {'skin': skin, 'shirt': shirt, 'shorts': shorts, 'socks': socks, 'boots': (0.03, 0.03, 0.035)}
    for n in MAT_SLOTS:
        m = bpy.data.materials.new(n); m.use_nodes = True
        bsdf = m.node_tree.nodes['Principled BSDF']; c = cols[n]
        bsdf.inputs['Base Color'].default_value = (c[0], c[1], c[2], 1); bsdf.inputs['Roughness'].default_value = 0.65 if n != 'boots' else 0.4
        ob.data.materials.append(m)
    # Assign by body zone (face centre): kit regions painted on the mesh.
    for p in ob.data.polygons:
        c = p.center; z = c.z; ax = abs(c.x)
        if z < 0.075: idx = 4                                  # boots
        elif z < 0.46 and abs(c.y) < 0.2 and ax < 0.2: idx = 3 # socks (shins)
        elif 0.62 < z <= 1.00 and ax < 0.22: idx = 2           # shorts
        elif 1.00 < z < 1.55 and (ax < 0.17 or (z > 1.30 and ax < 0.27)): idx = 1   # shirt incl. short sleeves
        else: idx = 0
        p.material_index = idx

def make_hair(style=1, color=(0.08, 0.06, 0.05)):
    bm = bmesh.new()
    r = bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.112)['verts']
    sc = {0: (1, 1, 0.5), 1: (1, 1, 0.72), 2: (1, 1.1, 0.8), 3: (0.9, 0.9, 0.85)}.get(style, (1, 1, 0.7))
    bmesh.ops.scale(bm, vec=Vector(sc), verts=r); bmesh.ops.translate(bm, vec=Vector((0, 0.005, 1.775 - (0.02 if style == 0 else 0))), verts=r)
    me = bpy.data.meshes.new('hair'); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new('hair', me); bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new('hair'); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color, 1); m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
    ob.data.materials.append(m)
    return ob

# ------------------------------------------------------------------ armature
def build_armature():
    arm = bpy.data.armatures.new('skeleton'); ob = bpy.data.objects.new('skeleton', arm)
    bpy.context.scene.collection.objects.link(ob); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    for n in ORDER:
        h, t, parent = BONES[n]
        b = arm.edit_bones.new(n); b.head, b.tail = h, t
        if parent: b.parent = arm.edit_bones[parent]; b.use_connect = (parent not in ('hips',) or True) and (h - BONES[parent][1]).length < 1e-4
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob

def seg_dist(p, a, b):
    ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
    return (p - (a + ab * t)).length

def skin(mesh_ob, arm_ob):
    """Distance-to-bone-segment weights (inverse distance^4, top 3 bones, normalised). More predictable than heat diffusion on a
    voxel-unioned body: no pelvis dragging when a thigh swings, arms never bind to the torso."""
    for n in ORDER: mesh_ob.vertex_groups.new(name=n)
    arm_names = [n for n in ORDER if n not in ('toe.L', 'toe.R')]
    for v in mesh_ob.data.vertices:
        p = v.co
        ds = sorted(((seg_dist(p, BONES[n][0], BONES[n][1]), n) for n in arm_names))[:3]
        ws = [1.0 / (max(d, 0.004) ** 4) for d, _ in ds]; tot = sum(ws)
        for (d, n), w in zip(ds, ws): mesh_ob.vertex_groups[n].add([v.index], w / tot, 'REPLACE')
    mesh_ob.parent = arm_ob
    mod = mesh_ob.modifiers.new('Armature', 'ARMATURE'); mod.object = arm_ob

def bind_rigid(ob, arm_ob, bone):
    vg = ob.vertex_groups.new(name=bone); vg.add(range(len(ob.data.vertices)), 1.0, 'REPLACE')
    ob.parent = arm_ob
    mod = ob.modifiers.new('Armature', 'ARMATURE'); mod.object = arm_ob

# ------------------------------------------------------------------ pose authoring (absolute orientations)
ARM_REST_ADJ = 0.42      # radians pulling the A-pose arms back to vertical

def Rabs(rx=0, ry=0, rz=0): return Euler((rx, ry, rz), 'XYZ').to_matrix().to_4x4()

class Poser:
    def __init__(self, arm_ob):
        self.ob = arm_ob
        self.loop = True; self.frames = 1
        for pb in arm_ob.pose.bones: pb.rotation_mode = 'QUATERNION'
        self.rest = {n: arm_ob.data.bones[n].matrix_local.to_3x3().to_4x4() for n in ORDER}

    def pose(self, frame, ang, root=(0, 0, 0)):
        """ang: bone -> (rx, ry, rz) absolute rotation about WORLD axes applied to the rest orientation. Forward swing of a limb = negative rx
        (character faces -Y). root: hips translation offset."""
        ob = self.ob
        if not self.loop:
            # The USD exporter trims trailing identical frames, which would cut held poses (fall, catch...) short and make RealityKit snap back
            # to the rest pose early. A sub-millimetre drift keeps every frame distinct so the full authored length is exported.
            root = (root[0], root[1], root[2] + 0.0004 * frame / max(1, self.frames))
        for n in ORDER:
            pb = ob.pose.bones[n]
            rx, ry, rz = ang.get(n, (0, 0, 0))
            if n.startswith(('upper_arm', 'forearm', 'hand')):
                ry += ARM_REST_ADJ if n.endswith('.L') else -ARM_REST_ADJ   # clips assume arms hang straight down
            if BONES[n][2] is None:
                head = BONES[n][0] + Vector(root)
            else:
                bpy.context.view_layer.update()
                head = ob.pose.bones[BONES[n][2]].tail.copy()
            M = Matrix.Translation(head) @ Rabs(rx, ry, rz) @ self.rest[n]
            pb.matrix = M
            pb.keyframe_insert('rotation_quaternion', frame=frame)
            if BONES[n][2] is None: pb.keyframe_insert('location', frame=frame)

def fwd(a): return -a      # forward swing -> rx

def run_pose(phase, amp, lean=0.0):
    s, c = math.sin(phase), math.cos(phase)
    hipL, hipR = s * amp * 0.95, -s * amp * 0.95
    kneeL = -(0.1 + 1.15 * amp * max(0, c)); kneeR = -(0.1 + 1.15 * amp * max(0, -c))
    shL, shR = -hipL * 0.85, -hipR * 0.85
    elb = 0.35 + 0.7 * amp
    A = {}
    A['spine'] = (fwd(lean), 0, 0); A['chest'] = (fwd(lean * 0.6), 0, 0)
    A['thigh.L'] = (fwd(hipL), 0, 0); A['shin.L'] = (fwd(hipL + kneeL), 0, 0); A['foot.L'] = (fwd((hipL + kneeL) * 0.4 + 0.1 * amp), 0, 0)
    A['thigh.R'] = (fwd(hipR), 0, 0); A['shin.R'] = (fwd(hipR + kneeR), 0, 0); A['foot.R'] = (fwd((hipR + kneeR) * 0.4 + 0.1 * amp), 0, 0)
    A['upper_arm.L'] = (fwd(shL), -0.12, 0); A['forearm.L'] = (fwd(shL + elb), -0.12, 0)
    A['upper_arm.R'] = (fwd(shR), 0.12, 0); A['forearm.R'] = (fwd(shR + elb), 0.12, 0)
    return A, (0, 0, 0.02 * amp * math.cos(2 * phase))

def clip_cycle(name, frames, amp, lean):
    def f(arm, P):
        for i in range(frames):
            A, root = run_pose(2 * math.pi * i / frames, amp, lean)
            P.pose(i + 1, A, root)
    return f

def clip_idle(arm, P):
    n = 60
    for i in range(n):
        t = 2 * math.pi * i / n
        A = {'spine': (fwd(0.03 * math.sin(t)), 0, 0), 'chest': (fwd(0.02 * math.sin(t + 0.5)), 0, 0), 'head': (0.02 * math.sin(t * 0.5), 0, 0),
             'upper_arm.L': (0, -0.10, 0), 'upper_arm.R': (0, 0.10, 0), 'forearm.L': (fwd(0.15), -0.10, 0), 'forearm.R': (fwd(0.15), 0.10, 0)}
        P.pose(i + 1, A, (0, 0, 0.004 * math.sin(t)))

def clip_kick(arm, P):
    # 14 frames: 1-2 short wind-up, 3 CONTACT (the game starts the clip here), 4-14 follow-through. Support leg bent, arms counter-swing.
    keys = {1: (-0.5, -0.9), 3: (1.25, -0.25), 8: (0.9, -0.35), 14: (0.1, -0.15)}
    ks = sorted(keys)
    for f in range(1, 15):
        lo = max(k for k in ks if k <= f); hi = min(k for k in ks if k >= f)
        u = 0 if hi == lo else (f - lo) / (hi - lo); u = u * u * (3 - 2 * u)
        h = keys[lo][0] + (keys[hi][0] - keys[lo][0]) * u; k = keys[lo][1] + (keys[hi][1] - keys[lo][1]) * u
        A = {'thigh.R': (fwd(h), 0, 0), 'shin.R': (fwd(h + k), 0, 0), 'foot.R': (fwd(h + k + 0.4), 0, 0),
             'thigh.L': (fwd(-0.15), 0, 0), 'shin.L': (fwd(-0.15 - 0.5), 0, 0), 'foot.L': (0, 0, 0),
             'spine': (fwd(0.12), 0, 0), 'upper_arm.L': (fwd(0.7 * h / 1.25), -0.2, 0), 'upper_arm.R': (fwd(-0.6 * h / 1.25), 0.2, 0),
             'forearm.L': (fwd(0.9), -0.2, 0), 'forearm.R': (fwd(0.6), 0.2, 0)}
        P.pose(f, A, (0, 0, -0.05))

def clip_tackle(arm, P):
    n = 24
    for i in range(n):
        u = math.sin(math.pi * i / (n - 1))
        A = {'thigh.R': (fwd(1.0 * u), 0, 0), 'shin.R': (fwd(0.8 * u), 0, 0), 'foot.R': (fwd(0.9 * u), 0, 0),
             'thigh.L': (fwd(-0.5 * u), 0, 0), 'shin.L': (fwd(-1.2 * u), 0, 0), 'spine': (fwd(0.35 * u), 0, 0), 'chest': (fwd(0.2 * u), 0, 0),
             'upper_arm.L': (fwd(-0.4 * u), -0.6 * u, 0), 'upper_arm.R': (fwd(-0.4 * u), 0.6 * u, 0)}
        P.pose(i + 1, A, (0, -0.25 * u, -0.22 * u))

def clip_slide(arm, P):
    n = 36
    for i in range(n):
        u = min(1, i / 6) if i < 28 else max(0, (n - 1 - i) / 8)
        A = {'hips': (math.radians(70) * u, 0, 0), 'thigh.R': (fwd(0.2 * u) - math.radians(70) * u, 0, 0), 'thigh.L': (-math.radians(70) * u + fwd(-0.1) * u, 0, 0),
             'shin.R': (-math.radians(70) * u, 0, 0), 'shin.L': (-math.radians(70) * u + 0.6 * u, 0, 0),
             'spine': (math.radians(10) * u, 0, 0), 'upper_arm.L': (fwd(0.6) * u, -0.9 * u, 0), 'upper_arm.R': (fwd(0.6) * u, 0.9 * u, 0)}
        P.pose(i + 1, A, (0, -1.2 * min(1, i / 28) * u, -0.62 * u))

def clip_fall(arm, P):
    n = 30
    for i in range(n):
        u = min(1, i / 14)
        A = {'hips': (0, math.radians(85) * u, 0), 'upper_arm.L': (0, -1.2 * u, 0), 'upper_arm.R': (0, 1.0 * u, 0), 'shin.L': (fwd(-0.6) * u, 0, 0), 'shin.R': (fwd(-0.3) * u, 0, 0)}
        P.pose(i + 1, A, (0, 0, -0.62 * u))

def clip_getup(arm, P):
    n = 30
    for i in range(n):
        u = 1 - min(1, i / 22)
        A = {'hips': (0, math.radians(85) * u, 0), 'spine': (fwd(0.5 * math.sin(math.pi * (1 - u))), 0, 0), 'upper_arm.L': (0, -1.0 * u, 0), 'upper_arm.R': (0, 1.0 * u, 0)}
        P.pose(i + 1, A, (0, 0, -0.62 * u))

def clip_celebrate(arm, P):
    n = 60
    for i in range(n):
        t = 2 * math.pi * i / n
        A = {'upper_arm.L': (fwd(2.9 + 0.25 * math.sin(3 * t)), -0.4, 0), 'upper_arm.R': (fwd(2.9 + 0.25 * math.sin(3 * t + 1)), 0.4, 0),
             'forearm.L': (fwd(2.9), -0.4, 0), 'forearm.R': (fwd(2.9), 0.4, 0), 'head': (0.1 * math.sin(2 * t), 0, 0.15 * math.sin(t)),
             'thigh.L': (fwd(0.1), 0, 0), 'thigh.R': (fwd(0.1), 0, 0), 'shin.L': (fwd(-0.2), 0, 0), 'shin.R': (fwd(-0.2), 0, 0)}
        P.pose(i + 1, A, (0, 0, 0.18 * abs(math.sin(2 * t))))

def clip_jump_header(arm, P):
    n = 30
    for i in range(n):
        t = i / (n - 1); z = 0.55 * math.sin(math.pi * t)
        head = math.exp(-((t - 0.5) / 0.12) ** 2)       # neck thrust at the apex
        A = {'spine': (fwd(-0.25 * (1 - head) + 0.45 * head), 0, 0), 'neck': (fwd(0.3 * head), 0, 0), 'head': (fwd(0.25 * head), 0, 0),
             'thigh.L': (fwd(0.6 * z), 0, 0), 'shin.L': (fwd(-0.9 * z), 0, 0), 'thigh.R': (fwd(-0.2 * z), 0, 0), 'shin.R': (fwd(-1.0 * z), 0, 0),
             'upper_arm.L': (fwd(-0.6), -0.7, 0), 'upper_arm.R': (fwd(-0.6), 0.7, 0)}
        P.pose(i + 1, A, (0, 0, z))

def clip_gk_ready(arm, P):
    n = 60
    for i in range(n):
        t = 2 * math.pi * i / n
        A = {'thigh.L': (fwd(0.45), -0.12, 0), 'thigh.R': (fwd(0.45), 0.12, 0), 'shin.L': (fwd(-0.35), 0, 0), 'shin.R': (fwd(-0.35), 0, 0),
             'spine': (fwd(0.28), 0, 0), 'chest': (fwd(0.1), 0, 0), 'head': (fwd(-0.2), 0, 0),
             'upper_arm.L': (fwd(0.5), -0.7, 0), 'upper_arm.R': (fwd(0.5), 0.7, 0), 'forearm.L': (fwd(1.0), -0.5, 0), 'forearm.R': (fwd(1.0), 0.5, 0)}
        P.pose(i + 1, A, (0, 0, -0.22 + 0.01 * math.sin(t)))

def make_dive(sign):
    def f(arm, P):
        n = 30
        for i in range(n):
            u = min(1, i / 12); hold = 1 if i < 22 else max(0, 1 - (i - 22) / 8)
            roll = math.radians(72) * sign * u * hold          # roll about Y (character's long axis side)
            A = {'hips': (0, roll, 0), 'upper_arm.L': (fwd(3.0 * u), -0.15, 0), 'upper_arm.R': (fwd(3.0 * u), 0.15, 0), 'forearm.L': (fwd(3.0 * u), -0.15, 0), 'forearm.R': (fwd(3.0 * u), 0.15, 0),
                 'thigh.L': (fwd(0.3 * u), 0, 0), 'thigh.R': (fwd(-0.2 * u), 0, 0), 'shin.L': (fwd(-0.2 * u), 0, 0), 'shin.R': (fwd(-0.5 * u), 0, 0)}
            P.pose(i + 1, A, (-1.3 * sign * u * hold, 0, -0.1 * u))
    return f

def clip_gk_catch(arm, P):
    n = 24
    for i in range(n):
        u = math.sin(math.pi * min(1, i / 16) / 2); hold = 1
        A = {'upper_arm.L': (fwd(1.7 * u), -0.2 * (1 - u), 0), 'upper_arm.R': (fwd(1.7 * u), 0.2 * (1 - u), 0), 'forearm.L': (fwd(1.7 * u + 0.9 * u), 0.2 * u, 0), 'forearm.R': (fwd(1.7 * u + 0.9 * u), -0.2 * u, 0),
             'spine': (fwd(0.25 * u), 0, 0), 'thigh.L': (fwd(0.3), 0, 0), 'thigh.R': (fwd(0.3), 0, 0), 'shin.L': (fwd(-0.3), 0, 0), 'shin.R': (fwd(-0.3), 0, 0)}
        P.pose(i + 1, A, (0, 0, -0.12))

def clip_gk_punch(arm, P):
    n = 24
    for i in range(n):
        u = math.sin(math.pi * i / (n - 1))
        A = {'upper_arm.R': (fwd(2.4 * u), 0.3, 0), 'forearm.R': (fwd(2.4 * u + 0.1), 0.3, 0), 'upper_arm.L': (fwd(1.0 * u), -0.6, 0), 'forearm.L': (fwd(1.2 * u), -0.4, 0),
             'spine': (fwd(0.15 * u), 0, 0), 'thigh.R': (fwd(0.5 * u), 0, 0), 'shin.R': (fwd(-0.8 * u), 0, 0)}
        P.pose(i + 1, A, (0, 0, 0.1 * u))

CLIPS = {   # name: (builder, frames, loop, contact_frame)
    'idle': (clip_idle, 60, True, None),
    'walk': (clip_cycle('walk', 36, 0.28, 0.02), 36, True, None),
    'jog': (clip_cycle('jog', 24, 0.60, 0.07), 24, True, None),
    'sprint': (clip_cycle('sprint', 18, 1.0, 0.18), 18, True, None),
    'kick': (clip_kick, 14, False, 3),
    'tackle': (clip_tackle, 24, False, 4),
    'slide': (clip_slide, 36, False, 10),
    'fall': (clip_fall, 30, False, None),
    'getup': (clip_getup, 30, False, None),
    'celebrate': (clip_celebrate, 60, True, None),
    'jump_header': (clip_jump_header, 30, False, 15),
    'gk_ready': (clip_gk_ready, 60, True, None),
    'gk_dive_left': (make_dive(1), 30, False, 12),
    'gk_dive_right': (make_dive(-1), 30, False, 12),
    'gk_catch': (clip_gk_catch, 24, False, 14),
    'gk_punch': (clip_gk_punch, 24, False, 10),
}

# ------------------------------------------------------------------ LOD baking
def bake_lod(body, arm_ob, ratio, name):
    """Decimated COPY of the skinned body (vertex groups kept). The USD exporter writes the original mesh data for skinned objects, so a
    modifier would not reach the file; the decimation has to be baked into real mesh data."""
    mod = body.modifiers.new('dec_tmp', 'DECIMATE'); mod.ratio = ratio
    arm_mod = body.modifiers['Armature']; arm_mod.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(body.evaluated_get(dg)); me.name = name
    body.modifiers.remove(mod); arm_mod.show_viewport = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for vg in body.vertex_groups: ob.vertex_groups.new(name=vg.name)
    # Decimation merges vertices and their weights: keep the 4 strongest influences per vertex and renormalise (RealityKit/mobile limit).
    pruned = []
    for v in me.vertices:
        top = sorted(((g.weight, g.group) for g in v.groups if g.weight > 1e-4), reverse=True)[:4]
        tot = sum(w for w, _ in top) or 1.0
        pruned.append([(gi, w / tot) for w, gi in top])
    for vg in ob.vertex_groups: vg.remove(range(len(me.vertices)))
    for vi, lst in enumerate(pruned):
        for gi, w in lst: ob.vertex_groups[gi].add([vi], w, 'REPLACE')
    ob.parent = arm_ob
    m = ob.modifiers.new('Armature', 'ARMATURE'); m.object = arm_ob
    return ob

def show_only(active, others):
    for o in others: o.hide_viewport = True; o.hide_render = True
    active.hide_viewport = False; active.hide_render = False

# ------------------------------------------------------------------ export helpers
def usd_export(path, meshes=True, animation=False):
    bpy.ops.wm.usd_export(filepath=path, export_animation=animation, export_armatures=True, only_deform_bones=False, export_meshes=meshes,
                          export_materials=meshes, generate_preview_surface=True, export_uvmaps=False, export_normals=True,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                          root_prim_path='/Player', convert_scene_units='METERS', xform_op_mode='TRS', export_shapekeys=False,
                          selected_objects_only=False, evaluation_mode='RENDER', triangulate_meshes=True)

def main():
    clear()
    sc = bpy.context.scene; sc.render.fps = FPS; sc.unit_settings.system = 'METRIC'
    body = build_body()
    arm = build_armature()
    make_materials(body)
    skin(body, arm)
    hair = make_hair(); bind_rigid(hair, arm, 'head')
    nverts = len(body.data.vertices); nfaces = len(body.data.polygons)
    print(f'MESH body verts={nverts} faces={nfaces}')

    lods = {0: body, 1: bake_lod(body, arm, 0.3, 'body_lod1'), 2: bake_lod(body, arm, 0.08, 'body_lod2')}
    print('LODS', {k: len(v.data.vertices) for k, v in lods.items()})
    P = Poser(arm)
    arm.animation_data_create()
    info = {}
    names = CLIPS_ARG or list(CLIPS)
    for name in names:
        builder, frames, loop, contact = CLIPS[name]
        act = bpy.data.actions.new(name); act.use_fake_user = True; arm.animation_data.action = act
        for pb in arm.pose.bones: pb.matrix_basis = Matrix.Identity(4)
        for o in (*lods.values(), hair): o.hide_viewport = True      # skip mesh evaluation while keyframing bones
        P.loop, P.frames = loop, frames
        builder(arm, P)
        show_only(lods[2], [lods[0], lods[1]]); hair.hide_viewport = False; hair.hide_render = False   # clip files carry the tiny LOD2 body
        info[name] = {'fps': FPS, 'frames': frames, 'loop': loop, 'contact_frame': contact}
        sc.frame_start, sc.frame_end = 1, frames
        usd_export(os.path.join(OUT, f'anim_{name}.usdz'), meshes=CLIP_MESH, animation=True)
        print('CLIP', name, frames)
    # Mesh + skeleton (rest pose, no animation)
    arm.animation_data.action = None
    for pb in arm.pose.bones: pb.matrix_basis = Matrix.Identity(4)
    sc.frame_set(1)
    for lod in (0, 1, 2):
        show_only(lods[lod], [v for k, v in lods.items() if k != lod])
        if lod == 0 or WANT_LODS:
            usd_export(os.path.join(OUT, f'player_lod{lod}.usdz'), meshes=True, animation=False)
            print('LOD', lod, len(lods[lod].data.vertices), 'verts')
    json.dump({'bones': ORDER, 'parents': {n: BONES[n][2] for n in ORDER}, 'material_slots': MAT_SLOTS + ['hair'], 'clips': info,
               'mesh': {'lod_vertices': {k: len(v.data.vertices) for k, v in lods.items()}, 'lod0_faces': nfaces}, 'height_m': 1.84, 'forward': '-Z (USD)', 'up': 'Y',
               'generator': 'Tools/blender/make_football_player.py (original, procedural)'},
              open(os.path.join(OUT, 'player.json'), 'w'), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'player.blend'))
    print('DONE')

main()
