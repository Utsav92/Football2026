#!/usr/bin/env python3
"""Motion data preprocessing. Standard library only (numpy optional, only for reading .npz SMPL files).

  python3 Tools/preprocess_motion.py skillcorner     # real broadcast-derived 3D pose (MIT): gait statistics + normalised clips
  python3 Tools/preprocess_motion.py smpl-selftest   # verifies the SMPL -> game-skeleton conversion maths on synthetic input
  python3 Tools/preprocess_motion.py smpl FILE.npz [--up y|z]   # RESEARCH ONLY: AMASS/WorldPose-style SMPL sequence (authorised access required)

What the SkillCorner pose is: 29 joints/player at 25 FPS with ~6-12 cm p90 error, only for detected players, z relative to the player
centroid. It is NOT clean mocap and NOT game-ready animation: it is used here to measure real gait (cadence vs speed) for calibrating
procedural animation, and as a normalised-skeleton exercise. Nothing here claims WorldPose/AMASS data is present: those are gated."""
import gzip, json, math, os, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'Datasets', 'raw', 'skillcorner', 'bodypose', 'sample_1925299_phase406.jsonl.gz')
OUT = os.path.join(ROOT, 'Datasets', 'motion')
FPS = 25.0

# 29 SkillCorner joints -> game skeleton (17 joints)
GAME_JOINTS = ['pelvis', 'spine', 'neck', 'head', 'l_shoulder', 'l_elbow', 'l_wrist', 'r_shoulder', 'r_elbow', 'r_wrist',
               'l_hip', 'l_knee', 'l_ankle', 'r_hip', 'r_knee', 'r_ankle', 'l_toe', 'r_toe']
def to_game(j):
    def p(n): return j[n]['xyz'] if n in j and j[n] else None
    def mid(a, b): return [(a[i] + b[i]) / 2 for i in range(3)] if a and b else None
    g = {'pelvis': p('midHip'), 'neck': p('neck'), 'head': p('nose') or mid(p('lEar'), p('rEar')),
         'l_shoulder': p('lShoulder'), 'l_elbow': p('lElbow'), 'l_wrist': p('lWrist'),
         'r_shoulder': p('rShoulder'), 'r_elbow': p('rElbow'), 'r_wrist': p('rWrist'),
         'l_hip': p('lHip'), 'l_knee': p('lKnee'), 'l_ankle': p('lAnkle'), 'r_hip': p('rHip'), 'r_knee': p('rKnee'), 'r_ankle': p('rAnkle'),
         'l_toe': p('lBigToe'), 'r_toe': p('rBigToe')}
    g['spine'] = mid(g['pelvis'], g['neck'])
    return g

def skillcorner():
    tracks = defaultdict(list)
    n = 0
    with gzip.open(RAW, 'rt') as f:
        for line in f:
            d = json.loads(line); n += 1
            for p in d['player_data']:
                tracks[p['player_id']].append((d['frame'], p['x'], p['y'], p.get('joints')))
    # Per-player windows of 1.6 s where joints exist in every frame
    W = int(1.6 * FPS)
    samples = []
    clips = {}
    for pid, tr in tracks.items():
        tr.sort()
        for s in range(0, len(tr) - W, W // 2):
            win = tr[s:s + W]
            if any(w[3] is None for w in win) or win[-1][0] - win[0][0] != W - 1: continue
            dx, dy = win[-1][1] - win[0][1], win[-1][2] - win[0][2]
            dist = math.hypot(dx, dy); speed = dist / ((W - 1) / FPS)
            if speed < 1.5: continue
            ux, uy = dx / dist, dy / dist
            sig = []
            ok = True
            for _, _, _, j in win:
                if 'lAnkle' not in j or 'rAnkle' not in j or not j['lAnkle'] or not j['rAnkle']: ok = False; break
                la, ra = j['lAnkle']['xyz'], j['rAnkle']['xyz']
                sig.append((la[0] - ra[0]) * ux + (la[1] - ra[1]) * uy)     # ankle separation along the running direction
            if not ok: continue
            m = sum(sig) / len(sig); sig = [v - m for v in sig]
            # smooth (3-tap) then count sign changes with hysteresis: each change = one step
            sm = [(sig[max(0, i - 1)] + sig[i] + sig[min(len(sig) - 1, i + 1)]) / 3 for i in range(len(sig))]
            thr = 0.04; state = 0; steps = 0
            for v in sm:
                if v > thr and state <= 0: steps += state != 0; state = 1
                elif v < -thr and state >= 0: steps += state != 0; state = -1
            if max(sm) - min(sm) < 0.15: continue
            samples.append({'player': pid, 'speed': speed, 'cadence': steps / ((W - 1) / FPS)})
            # normalised clip relative to pelvis, rotated to the running heading
            if pid not in clips:
                frames = []
                for fr, x, y, j in win:
                    g = to_game(j); pel = g['pelvis']
                    if not pel: frames = []; break
                    row = {}
                    for name in GAME_JOINTS:
                        q = g.get(name)
                        if q is None: row = None; break
                        rx, ry, rz = q[0] - pel[0], q[1] - pel[1], q[2] - pel[2]
                        row[name] = [round(rx * ux + ry * uy, 3), round(-rx * uy + ry * ux, 3), round(rz, 3)]
                    if row is None: frames = []; break
                    frames.append(row)
                if frames: clips[pid] = {'fps': FPS, 'speed_ms': round(speed, 2), 'frames': frames}
    os.makedirs(OUT, exist_ok=True)
    stats = {}
    if len(samples) >= 5:
        xs = [s['speed'] for s in samples]; ys = [s['cadence'] for s in samples]
        mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
        sxx = sum((x - mx) ** 2 for x in xs); sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys)); syy = sum((y - my) ** 2 for y in ys)
        b = sxy / sxx
        stats = {'n_windows': len(samples), 'speed_range_ms': [round(min(xs), 2), round(max(xs), 2)], 'cadence_steps_per_s_vs_speed': {
            'slope': round(b, 3), 'intercept': round(my - b * mx, 3), 'r2': round(sxy * sxy / (sxx * syy), 3) if syy else None},
            'mean_cadence': round(my, 2)}
    out = {'source': 'skillcorner_opendata bodypose sample (MIT, credit SkillCorner)', 'caveat': 'broadcast-derived pose, 6-12 cm p90 error; not mocap',
           'skeleton': GAME_JOINTS, 'gait': stats, 'clips': {str(k): v for k, v in clips.items()}}
    json.dump(out, open(os.path.join(OUT, 'skillcorner_gait.json'), 'w'), separators=(',', ':'))
    print('frames', n, '| tracks', len(tracks), '| usable running windows', len(samples), '| clips', len(clips)); print(json.dumps(stats))
    # Compare with the procedural run cycle: phase rate = 2.2 + 1.05*v rad/s; cycle=2 steps -> steps/s = 2*(2.2+1.05 v)/(2*pi)
    if stats:
        for v in (3, 5, 7, 8.5):
            real = stats['cadence_steps_per_s_vs_speed']['intercept'] + stats['cadence_steps_per_s_vs_speed']['slope'] * v
            proc = (2.2 + 1.05 * v) / math.pi
            print(f'  v={v:4.1f} m/s  real cadence {real:4.2f} steps/s   procedural rig {proc:4.2f} steps/s')

# ---------- SMPL (research-only; no data included) ----------
SMPL_TO_GAME = {0: 'pelvis', 3: 'spine', 12: 'neck', 15: 'head', 16: 'l_shoulder', 17: 'r_shoulder', 18: 'l_elbow', 19: 'r_elbow',
                20: 'l_wrist', 21: 'r_wrist', 1: 'l_hip', 2: 'r_hip', 4: 'l_knee', 5: 'r_knee', 7: 'l_ankle', 8: 'r_ankle', 10: 'l_toe', 11: 'r_toe'}

def axis_angle_to_quat(aa):
    a = math.sqrt(sum(v * v for v in aa))
    if a < 1e-9: return [1.0, 0.0, 0.0, 0.0]
    s = math.sin(a / 2) / a
    return [math.cos(a / 2), aa[0] * s, aa[1] * s, aa[2] * s]    # w, x, y, z

def smpl_sequence_to_game(poses, trans, fps, up='y'):
    """poses: N x (>=66) axis-angle floats (22 body joints x 3); trans: N x 3. Returns normalised local-rotation clip.
    Coordinates: SMPL/AMASS are right-handed; set up='z' for sources whose gravity axis is z (converted to y-up)."""
    frames = []
    for p, t in zip(poses, trans):
        rots = {SMPL_TO_GAME[j]: axis_angle_to_quat(p[3 * j:3 * j + 3]) for j in SMPL_TO_GAME}
        root = list(t) if up == 'y' else [t[0], t[2], -t[1]]
        frames.append({'root': [round(v, 4) for v in root], 'rot': {k: [round(c, 5) for c in v] for k, v in rots.items()}})
    return {'fps': fps, 'joints': list(SMPL_TO_GAME.values()), 'frames': frames, 'note': 'research-only; local joint rotations as quaternions (w,x,y,z)'}

def smpl_selftest():
    q = axis_angle_to_quat([0, 0, 0]); assert q == [1.0, 0.0, 0.0, 0.0]
    q = axis_angle_to_quat([0, math.pi / 2, 0]); assert abs(q[0] - math.cos(math.pi / 4)) < 1e-9 and abs(q[2] - math.sin(math.pi / 4)) < 1e-9
    poses = [[0.0] * 66, [0.0] * 3 + [0.5, 0, 0] + [0.0] * 60]
    clip = smpl_sequence_to_game(poses, [[0, 0.9, 0], [0, 0.9, 1.0]], 30)
    assert len(clip['frames']) == 2 and 'l_hip' in clip['frames'][1]['rot'] and abs(sum(c * c for c in clip['frames'][1]['rot']['l_hip']) - 1) < 1e-4
    clip_z = smpl_sequence_to_game(poses, [[0, 0, 0.9], [0, 1.0, 0.9]], 30, up='z')
    assert clip_z['frames'][0]['root'][1] == 0.9 and clip_z['frames'][1]['root'][2] == -1.0
    print('SMPL -> game-skeleton conversion selftest OK (synthetic input; no AMASS/WorldPose data is present or implied)')

def smpl_file(path, up):
    try: import numpy as np
    except ImportError: sys.exit('numpy is required to read .npz files: pip install numpy')
    d = np.load(path, allow_pickle=True)
    fps = float(d['mocap_framerate']) if 'mocap_framerate' in d else float(d.get('mocap_frame_rate', 30))
    clip = smpl_sequence_to_game(d['poses'].tolist(), d['trans'].tolist(), fps, up)
    out = os.path.join(OUT, os.path.basename(path).replace('.npz', '.research.json'))
    os.makedirs(OUT, exist_ok=True); json.dump(clip, open(out, 'w'))
    print('wrote', out, '(RESEARCH ONLY - do not ship or redistribute)')

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'skillcorner'
    if cmd == 'skillcorner': skillcorner()
    elif cmd == 'smpl-selftest': smpl_selftest()
    elif cmd == 'smpl': smpl_file(sys.argv[2], sys.argv[sys.argv.index('--up') + 1] if '--up' in sys.argv else 'y')
