#!/usr/bin/env python3
"""Extract one seamless gait cycle from a CMU locomotion clip (original ASF/AMC, 'free for all uses') as an in-place BVH, plus its true
ground speed, so the game can set playback rate = movement speed / cycle ground speed (no foot skating).

  cmu_extract_cycle.py --asf 35.asf --amc 35_17.amc --out Datasets/motion/loco/jog_35_17 [--cycles 1]
Writes <out>.bvh and <out>.json {ground_speed_ms, cycle_seconds, seam_error_m, strikes, source}."""
import argparse, json, math, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import cmu_asf_amc_to_bvh as c

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--asf', required=True); ap.add_argument('--amc', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--cycles', type=int, default=1, help='number of full gait cycles (2 steps each) to keep'); ap.add_argument('--stats-only', action='store_true'); a = ap.parse_args()
    root, bones, hier = c.parse_asf(a.asf); frames = c.parse_amc(a.amc); mode = 'zyx'
    parent, order, C = c.build(root, bones, hier, mode, mode)
    hz = 120.0; pos = []; fwdrel = []; hipy = []
    for f in frames:
        P, A = c.fk(root, bones, hier, parent, order, C, f, mode)
        fw = c.mv(A['root'], [0, 0, 1]); n = math.hypot(fw[0], fw[2]) or 1; fx, fz = fw[0] / n, fw[2] / n
        pos.append(P['root']); hipy.append(P['root'][1])
        fwdrel.append(((P['rfoot'][0] - P['root'][0]) * fx + (P['rfoot'][2] - P['root'][2]) * fz, (P['lfoot'][0] - P['root'][0]) * fx + (P['lfoot'][2] - P['root'][2]) * fz))
    # Gait period from the autocorrelation of the (mean-removed) right-foot forward position; then the start frame giving the most seamless, steadiest cycle.
    def pose_dist(i0, j):
        P0, _ = c.fk(root, bones, hier, parent, order, C, frames[i0], mode); P1, _ = c.fk(root, bones, hier, parent, order, C, frames[j], mode)
        return sum(math.dist([P0[n][0] - P0['root'][0], P0[n][1], P0[n][2] - P0['root'][2]], [P1[n][0] - P1['root'][0], P1[n][1], P1[n][2] - P1['root'][2]]) for n in ('lfoot', 'rfoot', 'lhand', 'rhand', 'head', 'ltoes', 'rtoes')) / 7
    sig = [v[0] - v[1] for v in fwdrel]; m = sum(sig) / len(sig); sig = [v - m for v in sig]   # right minus left foot: one clean sinusoid per full gait cycle
    var = sum(v * v for v in sig) or 1.0; best_lag, best_ac = None, -1
    for lag in range(int(0.45 * hz), min(int(1.5 * hz), len(sig) // 2 + 1)):
        ac = sum(sig[i] * sig[i + lag] for i in range(len(sig) - lag)) / var * len(sig) / max(1, len(sig) - lag)
        if ac > best_ac: best_ac, best_lag = ac, lag
    if best_lag is None or best_ac < 0.5: print("no periodic gait found (autocorr %.2f)" % best_ac); sys.exit(2)
    L = best_lag * a.cycles; best = None; total_strikes = 0
    for i0 in range(0, len(frames) - L - 6, 2):
        cand = [(pose_dist(i0, j), j) for j in range(i0 + L - 5, min(len(frames) - 1, i0 + L + 5) + 1)]
        seam, j1 = min(cand); T = (j1 - i0) / hz; d = math.dist((pos[i0][0], pos[i0][2]), (pos[j1][0], pos[j1][2])); spd = d / T
        sp = [math.dist((pos[q][0], pos[q][2]), (pos[q - 6][0], pos[q - 6][2])) / (6 / hz) for q in range(i0 + 6, j1)]
        spread = (max(sp) - min(sp)) / max(spd, 0.1) if sp else 9
        edge = 0.0 if (i0 > 0.08 * len(frames) and j1 < 0.92 * len(frames)) else 0.05   # prefer the steady middle of the take
        score = seam + 0.05 * spread + edge
        if best is None or score < best[0]: best = (score, i0, j1, spd, T, seam, spread)
    total_strikes = round(best_ac * 100)   # reused field: autocorrelation x100
    score, i0, j1, spd, T, seam, spread = best
    info = {'source': os.path.basename(a.amc), 'ground_speed_ms': round(spd, 3), 'cycle_seconds': round(T, 3), 'cycles': a.cycles, 'seam_error_m': round(seam, 4),
            'speed_spread_frac': round(spread, 3), 'autocorr_x100': total_strikes, 'frames': [i0, j1]}
    print(json.dumps(info))
    if a.stats_only: return
    os.makedirs(os.path.dirname(a.out) or '.', exist_ok=True)
    c.write_bvh(a.out + '.bvh', root, bones, hier, parent, order, C, frames[i0:j1 + 1], mode, True)
    json.dump(info, open(a.out + '.json', 'w'), indent=1)

if __name__ == '__main__': main()
