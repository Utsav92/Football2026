# Testing
**139 XCTest cases** (release run, 0 failures): physics 16 · game 78 · modes 25 · input 9 · data 6 · audio 5. Debug runs skip the heavy full-match tests (`skipInDebug`).
Coverage highlights: ball bounce/rolling/drag/Magnus/posts/bar/nets/goal & out detection/determinism/step-size independence · offside, throw-in, corner, goal kick, penalty vs free-kick,
second yellow, halves & added time, substitutions · formations (6 × shape tests, all pairings play a full match without NaN/out-of-bounds) · human control, switching, charged kicks,
attribute effects (speed, power, accuracy, tackling) · goalkeeper saves/dives/catch/distribution/penalties · AI state transitions · replay recorder/player · training drills ·
input buffering · finesse curl, jockey, shielding and skill-move effects (statistical) · headers/volleys · advantage played/recalled · extra time, penalty shootout (alternation, rotation, winner consistency, every knockout match decided) · goalkeeper dismissal · change-of-ends mirroring · calibration against real tracking (team length/width/line slope) and real shots (xG bands) · database validity · tournaments (fixtures, tie-breaks, group→knockout, byes, penalties) ·
career (finances, transfers, contracts, training, injuries, seasons, determinism, save/load/migration/backup/corrupt/newer-version) · controller mapping/remap/buffer/assignments · audio DSP.
Scripts: `Tools/validate_assets.py`, `Tools/validate_licenses.py`, `Tools/inspect_datasets.py`, retarget/import/SMPL/StatsBomb self-tests.
**Not covered by automated tests**: SwiftUI views, RealityKit rendering, live input devices, audio playback. See KNOWN_LIMITATIONS.md.
