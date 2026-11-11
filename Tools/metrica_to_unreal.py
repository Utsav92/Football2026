#!/usr/bin/env python3
"""Convert Metrica Sports sample tracking (raw 25 Hz CSV) into a compact Unreal-ready replay.

Licence: Metrica's sample-data repository declares NO licence (README: "be responsible; acknowledge the source if public").
Therefore the output is LOCAL RESEARCH ONLY: written to Datasets/replay/ (git-ignored) and never bundled into a packaged game build.

Coordinates: Metrica gives normalised [0,1] with the origin at the top-left. Real pitch size is not published with the sample;
we assume 105 x 68 m (documented assumption). Output units are centimetres, origin at the centre spot:
    UE X = (x - 0.5) * 105 * 100     (along the pitch, as in the game simulation)
    UE Y = (y - 0.5) * 68  * 100     (across the pitch)
Outputs:  <out>.json (metadata + schema report)   <out>.bin (int16 little-endian [frame][slot][x,y] in cm; -32768 = missing)
Slots: 0..13 home columns, 14..27 away columns, 28 = ball.   Usage: metrica_to_unreal.py [--src DIR] [--out PREFIX] [--validate-only]
"""
import argparse, csv, json, math, os, struct, sys, time

PITCH_L, PITCH_W = 105.0, 68.0
MISSING = -32768
MAX_SPEED = 14.0   # m/s: faster than any footballer (Bolt ~12.4 m/s peak)

def read_team(path):
    with open(path, newline='') as f:
        r = csv.reader(f)
        side = next(r); jersey = next(r); header = next(r)
    if header[:3] != ['Period', 'Frame', 'Time [s]']: raise ValueError(f"{path}: unexpected header {header[:3]}")
    players = []
    for i in range(3, len(header) - 2, 2):
        name = header[i]
        if not name.startswith('Player'): raise ValueError(f"{path}: column {i} is {name!r}, expected PlayerNN")
        players.append({'column': i, 'name': name, 'jersey': int(jersey[i])})
    if header[-2] != 'Ball': raise ValueError(f"{path}: last columns are not Ball")
    return side[3], players

def load(path, nplayers):
    rows = []
    with open(path, newline='') as f:
        r = csv.reader(f); next(r); next(r); next(r)
        for line in r:
            rows.append(line)
    return rows

def val(s):
    return None if s in ('', 'NaN') else float(s)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--src', default='Datasets/raw/metrica/Sample_Game_1')
    ap.add_argument('--out', default='Datasets/replay/metrica_game1'); ap.add_argument('--validate-only', action='store_true'); a = ap.parse_args()
    hp = os.path.join(a.src, 'Sample_Game_1_RawTrackingData_Home_Team.csv'); ap_ = os.path.join(a.src, 'Sample_Game_1_RawTrackingData_Away_Team.csv')
    hside, hpl = read_team(hp); aside, apl = read_team(ap_)
    assert hside == 'Home' and aside == 'Away', (hside, aside)
    assert len(hpl) <= 14 and len(apl) <= 14, (len(hpl), len(apl))
    hr, ar = load(hp, len(hpl)), load(ap_, len(apl))
    if len(hr) != len(ar): raise SystemExit(f"FAIL: home has {len(hr)} frames, away {len(ar)}")
    n = len(hr); problems = []; out = bytearray(); periods = {}; maxspeed = 0.0; oob = 0; missing = 0; masked = 0; prev = {}; raw_prev = {}; lost = {}
    for k in range(n):
        h, w = hr[k], ar[k]
        per, fr, tm = int(h[0]), int(h[1]), float(h[2])
        if (int(w[0]), int(w[1])) != (per, fr): problems.append(f"frame {k}: period/frame mismatch home/away")
        if k and fr != prev.get('fr', 0) + 1 and per == prev.get('per'): problems.append(f"frame {k}: non-consecutive {prev.get('fr')} -> {fr}")
        periods.setdefault(per, [k, k]); periods[per][1] = k
        slots = []
        for side_rows, pl in ((h, hpl), (w, apl)):
            for s in range(14):
                if s < len(pl):
                    x, y = val(side_rows[pl[s]['column']]), val(side_rows[pl[s]['column'] + 1])
                else: x = y = None
                slots.append((x, y))
        slots.append((val(h[-2]), val(h[-1])))
        for si, (x, y) in enumerate(slots):
            if x is None or y is None or math.isnan(x) or math.isnan(y):
                out += struct.pack('<hh', MISSING, MISSING); missing += 1; prev.pop(si, None); raw_prev.pop(si, None); lost.pop(si, None); continue
            cx = max(-32767, min(32767, round((x - 0.5) * PITCH_L * 100))); cy = max(-32767, min(32767, round((y - 0.5) * PITCH_W * 100)))
            if si < 28:
                # Quarantine tracking artefacts: samples that are off the pitch, or whose raw step from the previous raw frame exceeds
                # MAX_SPEED, are masked (hidden) until the raw track is self-consistent for 3 frames. Raw values are never edited.
                out_of_pitch = not (-0.02 <= x <= 1.02 and -0.02 <= y <= 1.02)
                rp = raw_prev.get(si); raw_prev[si] = (cx, cy, per)
                step_ok = rp is not None and rp[2] == per and math.hypot(cx - rp[0], cy - rp[1]) / 100.0 / 0.04 <= MAX_SPEED
                mask = False
                if out_of_pitch: oob += 1; lost[si] = 3; mask = True
                elif si in lost:
                    if step_ok: lost[si] -= 1
                    else: lost[si] = 3
                    mask = True
                    if lost[si] <= 0: del lost[si]
                elif rp is not None and rp[2] == per and not step_ok: lost[si] = 3; mask = True
                if mask:
                    masked += 1; prev.pop(si, None); out += struct.pack('<hh', MISSING, MISSING); continue
                if si in prev and prev[si][2] == per:
                    maxspeed = max(maxspeed, math.hypot(cx - prev[si][0], cy - prev[si][1]) / 100.0 / 0.04)
            out += struct.pack('<hh', cx, cy)
            prev[si] = (cx, cy, per)
        prev['fr'] = fr; prev['per'] = per
    report = {'frames': n, 'hz': 25, 'periods': {str(p): v for p, v in periods.items()}, 'missing_samples': missing,
              'out_of_pitch_samples_masked': oob, 'artefact_samples_masked_total': masked, 'max_player_speed_ms_after_cleaning': round(maxspeed, 2), 'problems': problems[:20], 'problem_count': len(problems)}
    meta = {'source': 'metrica_sample_game1', 'licence': 'NONE DECLARED - local research only, do not ship', 'assumed_pitch_m': [PITCH_L, PITCH_W],
            'units': 'cm', 'axes': 'UE X along pitch, UE Y across pitch, origin centre spot', 'hz': 25, 'frames': n,
            'slots': {'home': hpl, 'away': apl, 'ball_slot': 28}, 'period_frames': report['periods'], 'validation': report}
    print(json.dumps(report, indent=1))
    ok = not problems and maxspeed <= MAX_SPEED + 0.01
    print("VALIDATION:", "PASS" if ok else "FAIL")
    if a.validate_only or not ok and '--force' not in sys.argv: sys.exit(0 if ok else 1)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out + '.bin', 'wb').write(out); json.dump(meta, open(a.out + '.json', 'w'), indent=1)
    print(f"wrote {a.out}.bin ({len(out)/1e6:.1f} MB) and {a.out}.json")

if __name__ == '__main__': main()
