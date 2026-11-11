#!/usr/bin/env python3
"""Convert CMU Graphics Lab ASF/AMC motion capture (original files from mocap.cs.cmu.edu, 'free for all uses') into BVH, in pure Python.
Does not use any third-party conversion (some, e.g. the 4TU FBX set, carry non-commercial licences).

  cmu_asf_amc_to_bvh.py --asf 10.asf --amc 10_01.amc --out kick.bvh [--inplace] [--check] [--euler zyx|xyz]

Model (Lander / Acclaim spec): per bone C = axis orientation (global rest), M = AMC rotation in the bone's local axes.
  A_root = C_root M_root C_root^-1 ;  A_i = A_parent * C_i M_i C_i^-1 ;  start_child = start_parent + A_parent * (dir_parent * len_parent)
BVH joint frames are the global rest axes, so BVH offsets are the rest bone vectors and the BVH local rotation is C_i M_i C_i^-1.
--check re-derives joint positions from the written BVH and compares with direct ASF forward kinematics (must agree to <1e-3 m)."""
import argparse, math, sys

LEN_TO_M = (1 / 0.45) * 0.0254   # ASF ':units length 0.45' -> metres (CMU convention: unit = 1/0.45 inch)

def rx(a): c, s = math.cos(a), math.sin(a); return [[1, 0, 0], [0, c, -s], [0, s, c]]
def ry(a): c, s = math.cos(a), math.sin(a); return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
def rz(a): c, s = math.cos(a), math.sin(a); return [[c, -s, 0], [s, c, 0], [0, 0, 1]]
def mm(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def mv(a, v): return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]
def tr(a): return [[a[j][i] for j in range(3)] for i in range(3)]
I3 = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
FN = {'x': rx, 'y': ry, 'z': rz}

def euler(angles_deg, order, mode):
    """order e.g. 'xyz' (the order angles are listed in). mode 'zyx': R = R_o3 R_o2 R_o1 (first-listed applied first, extrinsic); 'xyz': R = R_o1 R_o2 R_o3."""
    mats = [FN[o](math.radians(a)) for o, a in zip(order, angles_deg)]
    if mode == 'zyx': mats = mats[::-1]
    r = I3
    for m in mats: r = mm(r, m)
    return r

def parse_asf(path):
    bones, hier, root = {}, {}, {}
    sec = None; cur = None
    for raw in open(path):
        l = raw.strip()
        if not l or l.startswith('#'): continue
        if l.startswith(':'): sec = l[1:].split()[0]; continue
        t = l.split()
        if sec == 'root':
            if t[0] == 'order': root['order'] = [x.lower() for x in t[1:]]
            elif t[0] == 'axis': root['axis'] = t[1].lower()
            elif t[0] == 'position': root['position'] = [float(x) for x in t[1:4]]
            elif t[0] == 'orientation': root['orientation'] = [float(x) for x in t[1:4]]
        elif sec == 'bonedata':
            if t[0] == 'begin': cur = {'dof': []}
            elif t[0] == 'end': bones[cur['name']] = cur; cur = None
            elif cur is not None:
                if t[0] == 'name': cur['name'] = t[1]
                elif t[0] == 'direction': cur['dir'] = [float(x) for x in t[1:4]]
                elif t[0] == 'length': cur['len'] = float(t[1]) * LEN_TO_M
                elif t[0] == 'axis': cur['axis'] = [float(x) for x in t[1:4]]; cur['axis_order'] = t[4].lower()
                elif t[0] == 'dof': cur['dof'] = [x.lower() for x in t[1:]]
        elif sec == 'hierarchy':
            if t[0] in ('begin', 'end'): continue
            hier[t[0]] = t[1:]
    return root, bones, hier

def parse_amc(path):
    frames, cur = [], None
    for raw in open(path):
        l = raw.strip()
        if not l or l[0] in '#:': continue
        t = l.split()
        if len(t) == 1 and t[0].isdigit(): cur = {}; frames.append(cur); continue
        if cur is not None: cur[t[0]] = [float(x) for x in t[1:]]
    return frames

def build(root, bones, hier, mode, cmode):
    parent = {}; order = []
    def walk(n, p):
        for c in hier.get(n, []): parent[c] = n; order.append(c); walk(c, n)
    walk('root', None)
    C = {}
    for n in order:
        b = bones[n]; C[n] = euler(b['axis'], b['axis_order'], cmode)
    return parent, order, C

def local_rot(bone_name, bones, C, frame, mode):
    """C M C^-1 for a bone at one frame."""
    b = bones[bone_name]; vals = frame.get(bone_name, [])
    ang = {d: v for d, v in zip(b['dof'], vals)}
    a3 = [ang.get('rx', 0), ang.get('ry', 0), ang.get('rz', 0)]
    M = euler(a3, 'xyz', mode) if b['dof'] == ['rx', 'ry', 'rz'] or True else I3
    # honour the dof order as listed: build rotation in listed order
    names = [d[1] for d in b['dof']]; vs = [ang[d] for d in b['dof']]
    M = euler(vs, ''.join(names), mode) if names else I3
    return mm(mm(C[bone_name], M), tr(C[bone_name]))

def fk(root, bones, hier, parent, order, C, frame, mode, inplace_yaw=None, drop_xz=False):
    """World joint (bone start) positions + accumulated rotations A for one frame."""
    ro = root['order']; vals = frame['root']; d = dict(zip(ro, vals))
    pos = [d.get('tx', 0) * LEN_TO_M, d.get('ty', 0) * LEN_TO_M, d.get('tz', 0) * LEN_TO_M]
    Mr = euler([d.get('rx', 0), d.get('ry', 0), d.get('rz', 0)], 'xyz', mode)
    # root rotation order as listed (rx ry rz in the file's order)
    rot_names = [x[1] for x in ro if x.startswith('r')]; rot_vals = [d[x] for x in ro if x.startswith('r')]
    Mr = euler(rot_vals, ''.join(rot_names), mode)
    A = {'root': Mr}; P = {'root': pos}
    for n in order:
        p = parent[n]; bp = bones.get(p)
        vec = [x * bp['len'] for x in bp['dir']] if bp else [0, 0, 0]
        P[n] = [P[p][i] + v for i, v in enumerate(mv(A[p], vec))]
        A[n] = mm(A[p], local_rot(n, bones, C, frame, mode))
    return P, A

def zyx_from_matrix(R):
    y = -math.asin(max(-1, min(1, R[2][0])))
    if abs(R[2][0]) < 0.99999: x = math.atan2(R[2][1], R[2][2]); z = math.atan2(R[1][0], R[0][0])
    else: x = math.atan2(-R[1][2], R[1][1]); z = 0.0
    return [math.degrees(z), math.degrees(y), math.degrees(x)]

def posture_score(root, bones, hier, parent, order, C, frames, mode):
    ok = 0; n = 0
    for f in frames[::max(1, len(frames) // 40)]:
        P, A = fk(root, bones, hier, parent, order, C, f, mode)
        hips = P['root'][1]; head = P['head'][1] if 'head' in P else hips
        feet = min(P['lfoot'][1], P['rfoot'][1], P['ltoes'][1], P['rtoes'][1])
        n += 1
        if head - hips > 0.35 and hips - feet > 0.55 and hips - feet < 1.3: ok += 1
    return ok / max(1, n)

def write_bvh(path, root, bones, hier, parent, order, C, frames, mode, inplace):
    children = {n: [c for c in order if parent[c] == n] for n in ['root'] + order}
    lines = ['HIERARCHY']
    def off(n):   # offset of bone n's start relative to its parent's start = parent's rest vector
        if n == 'root': return [0, 0, 0]
        bp = bones.get(parent[n]); return [x * bp['len'] for x in bp['dir']] if bp else [0, 0, 0]
    def emit(n, ind):
        o = off(n); name = n
        kw = 'ROOT' if n == 'root' else 'JOINT'
        lines.append(f"{ind}{kw} {name}"); lines.append(f"{ind}{{"); lines.append(f"{ind}\tOFFSET {o[0]:.6f} {o[1]:.6f} {o[2]:.6f}")
        if n == 'root': lines.append(f"{ind}\tCHANNELS 6 Xposition Yposition Zposition Zrotation Yrotation Xrotation")
        else: lines.append(f"{ind}\tCHANNELS 3 Zrotation Yrotation Xrotation")
        ch = children[n]
        for c in ch: emit(c, ind + '\t')
        if not ch:
            b = bones.get(n); v = [x * b['len'] for x in b['dir']] if b else [0, 0.05, 0]
            lines.append(f"{ind}\tEnd Site"); lines.append(f"{ind}\t{{"); lines.append(f"{ind}\t\tOFFSET {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}"); lines.append(f"{ind}\t}}")
        lines.append(f"{ind}}}")
    emit('root', '')
    yaw0 = 0.0; x0 = z0 = 0.0
    if inplace:
        f0 = frames[0]; ro = f0['root']; d = dict(zip(root['order'], ro))
        rn = [x[1] for x in root['order'] if x.startswith('r')]; rv = [d[x] for x in root['order'] if x.startswith('r')]
        A0 = euler(rv, ''.join(rn), mode); fwd = mv(A0, [0, 0, 1]); yaw0 = math.atan2(fwd[0], fwd[2])
        x0, z0 = d.get('tx', 0) * LEN_TO_M, d.get('tz', 0) * LEN_TO_M
    lines += ['MOTION', f'Frames: {len(frames)}', 'Frame Time: 0.008333']
    unyaw = ry(-yaw0)
    for f in frames:
        d = dict(zip(root['order'], f['root']))
        pos = [d.get('tx', 0) * LEN_TO_M, d.get('ty', 0) * LEN_TO_M, d.get('tz', 0) * LEN_TO_M]
        rn = [x[1] for x in root['order'] if x.startswith('r')]; rv = [d[x] for x in root['order'] if x.startswith('r')]
        Rr = euler(rv, ''.join(rn), mode)
        if inplace: pos = [0.0, pos[1], 0.0]; Rr = mm(unyaw, Rr)
        row = pos + zyx_from_matrix(Rr)
        for n in order: row += zyx_from_matrix(local_rot(n, bones, C, f, mode))
        lines.append(' '.join(f"{v:.5f}" for v in row))
    open(path, 'w').write('\n'.join(lines) + '\n')

def bvh_fk_check(path, root, bones, hier, parent, order, C, frames, mode, inplace):
    """Independent BVH reader + FK; compares joint positions with direct ASF FK on sample frames (only valid when not --inplace)."""
    txt = open(path).read().split('MOTION'); hdr = txt[0].splitlines(); mot = txt[1].strip().splitlines()[2:]
    joints = []; stack = []; cur = None
    for l in hdr:
        t = l.split()
        if not t: continue
        if t[0] in ('ROOT', 'JOINT'): cur = {'name': t[1], 'parent': stack[-1] if stack else None}; joints.append(cur); stack.append(t[1])
        elif t[0] == 'End': stack.append('__end__')
        elif t[0] == 'OFFSET' and cur is not None and stack and stack[-1] != '__end__': cur['off'] = [float(x) for x in t[1:4]]
        elif t[0] == 'CHANNELS': cur['n'] = int(t[1])
        elif t[0] == '}': stack.pop()
    worst = 0.0
    for fi in range(0, len(frames), max(1, len(frames) // 12)):
        vals = [float(x) for x in mot[fi].split()]; k = 0; W = {}; Pw = {}
        for j in joints:
            n = j['n']; ch = vals[k:k + n]; k += n
            if n == 6: pos = ch[:3]; z, y, x = ch[3:]
            else: pos = [0, 0, 0]; z, y, x = ch
            R = mm(mm(rz(math.radians(z)), ry(math.radians(y))), rx(math.radians(x)))
            if j['parent'] is None: W[j['name']] = R; Pw[j['name']] = pos
            else:
                p = j['parent']; W[j['name']] = mm(W[p], R); Pw[j['name']] = [Pw[p][i] + v for i, v in enumerate(mv(W[p], j['off']))]
        P, A = fk(root, bones, hier, parent, order, C, frames[fi], mode)
        for nme in Pw:
            worst = max(worst, max(abs(Pw[nme][i] - P[nme][i]) for i in range(3)))
    return worst

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--asf', required=True); ap.add_argument('--amc', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--inplace', action='store_true'); ap.add_argument('--trim-kick', action='store_true', help='keep only ~1 s around the fastest foot (the strike)'); ap.add_argument('--check', action='store_true'); ap.add_argument('--euler', default=None, help='zyx|xyz (default: auto-select by posture score)')
    ap.add_argument('--cmode', default=None, help='composition mode for the ASF axis rotation (default: same as --euler)')
    a = ap.parse_args()
    root, bones, hier = parse_asf(a.asf); frames = parse_amc(a.amc)
    best = None
    for mode in ([a.euler] if a.euler else ['zyx']):   # 'zyx' chosen empirically: 1 cm ground-height std vs 3-5 cm for 'xyz' on CMU soccer clips
        for cmode in ([a.cmode or mode] if (a.euler or a.cmode) else ['zyx']):
            parent, order, C = build(root, bones, hier, mode, cmode)
            sc = posture_score(root, bones, hier, parent, order, C, frames, mode)
            print(f"convention M={mode} C={cmode}: posture score {sc:.2f}")
            if best is None or sc > best[0]: best = (sc, mode, cmode, parent, order, C)
    sc, mode, cmode, parent, order, C = best
    if a.trim_kick:
        rel = []
        for f in frames:
            P, _ = fk(root, bones, hier, parent, order, C, f, mode); rel.append((tuple(P['lfoot'][i] - P['root'][i] for i in range(3)), tuple(P['rfoot'][i] - P['root'][i] for i in range(3))))
        best_i, best_v, foot = 1, 0, 'l'   # kicking-foot speed relative to the hips (ignores the whole-body run-up)
        for i in range(1, len(frames)):
            for k, nm in ((0, 'l'), (1, 'r')):
                v = math.dist(rel[i][k], rel[i - 1][k]) * 120
                if v > best_v: best_i, best_v, foot = i, v, nm
        lo, hi = max(0, best_i - int(0.55 * 120)), min(len(frames), best_i + int(0.45 * 120))
        print(f"strike at frame {best_i} ({best_i/120:.2f}s) by the {foot.upper()} foot, peak foot speed {best_v:.1f} m/s; keeping frames {lo}-{hi} ({(hi-lo)/120:.2f}s)")
        frames = frames[lo:hi]
    print(f"using M={mode} C={cmode} (score {sc:.2f}); {len(frames)} frames, {len(order)+1} joints")
    if sc < 0.9: print("WARNING: posture score below 0.9: conventions may be wrong"); 
    write_bvh(a.out, root, bones, hier, parent, order, C, frames, mode, a.inplace)
    if a.check:
        if a.inplace: write_bvh(a.out + '.raw', root, bones, hier, parent, order, C, frames, mode, False); chk = bvh_fk_check(a.out + '.raw', root, bones, hier, parent, order, C, frames, mode, False)
        else: chk = bvh_fk_check(a.out, root, bones, hier, parent, order, C, frames, mode, False)
        import os
        if a.inplace and os.path.exists(a.out + '.raw'): os.remove(a.out + '.raw')
        print(f"BVH-vs-ASF forward-kinematics max joint error: {chk:.6f} m", "PASS" if chk < 1e-3 else "FAIL")
    print('wrote', a.out)

if __name__ == '__main__': main()
