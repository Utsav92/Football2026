# Football 2026

Native macOS 3D football simulator: **Swift 6 · SwiftUI · RealityKit · AVFoundation · GameController**, with a render-independent, deterministic
match engine, a Blender-generated skinned athlete, a 20-club / 480-player fictional database, and data-calibrated tactical AI.
Original code and assets only. Developed and tested on an Apple M5 Pro Mac mini (24 GB, macOS 27, Xcode 27.2).

> **Engine decision.** A later brief asked for Unreal Engine. Unreal was not installed (UE 5.7/5.8 were empty queued installs) and Epic's docs
> do not cover macOS 27 + Xcode 27, so the project owner chose to keep Swift/RealityKit. See `Documentation/ENVIRONMENT_REPORT.md`.

## Run it
```bash
# prebuilt (ad-hoc signed, not notarized): Builds/Football2026-0.4-macOS-arm64.zip  -> unzip, right-click > Open
python3 Tools/gen_pbxproj.py       # stages Assets/ into the bundle and regenerates the Xcode project (after adding files)
xcodebuild -project Football2026.xcodeproj -scheme Football2026 -configuration Release -derivedDataPath build_release build
open build_release/Build/Products/Release/Football2026.app
```
Requires macOS 15+, Xcode 26+. Open `Football2026.xcodeproj` in Xcode and press Run for the debug workflow.

## Controls
| | Keyboard | Controller (PlayStation layout, remappable) |
|---|---|---|
| Move / sprint | WASD or arrows / Shift | Left stick / R2 |
| Pass · shoot (hold to charge) | E · Space | Cross · Circle |
| Finesse curl (hold with shoot) · jockey/shield · skill moves | Z · Ctrl · I/J/K/L | R1 · L2 · right stick |
| Cross/lob · through ball | F · G | Square · Triangle |
| Switch player | Q or Tab | L1 |
| Tackle · slide (defending) | X · V | Cross · Circle (context changes when you lose the ball) |
| Camera · replay · AI debug overlay | C · T · B | — |
| Pause · confirm | Esc · Return | Options |

## Modes
Quick Match (team, formation, difficulty, length, stadium, time of day, weather, controlled side) · Local Versus (two controllers) · Tournament
(league / groups+knockout / knockout) · Career (finances, transfers, contracts, training, injuries, seasons, saves with backup + migration) ·
Training (free practice, shooting, passing, penalties, free kicks) · Settings (controller remap/dead zone, graphics, audio, defaults — persisted).

## Architecture
```
Packages/FootballKit/ (SwiftPM, no rendering dependency, 139 unit tests)
  FootballPhysics   regulation pitch/goal geometry, ball integrator (gravity, drag, Magnus, bounce, rolling, posts/bar/nets), goal & out detection
  FootballGame      22-player match engine (120 Hz fixed step), rules/referee, tactical AI, goalkeepers, replay recorder, training drills
  FootballData      club/player records, lineup selection, database validation
  FootballModes     tournaments (fixtures, standings, knockout), career mode, save/load/migrate/backup
  FootballInput     controller mapping, remapping, buffering, assignments
  FootballAudio     procedural sound synthesis (pure DSP)
  SimExport         CLI: simulated tracking export + throughput benchmark
App/                SwiftUI menus & HUD, RealityKit scene (pitch, stadium, skinned players, cameras), audio/gamepad adapters, offscreen renderer
Tools/              Python/Blender pipelines (datasets, tracking, events, motion, characters, validation)
Datasets/           manifest.json, LICENSE_AUDIT.md, raw/ (git-ignored), processed/, tracking/, motion/, synthetic/, validation/
Assets/             Characters/out (Blender output), Database/clubs.json, Bundle/ (staged for the app)
```

## Status — what is implemented AND verified
| Area | State | Evidence |
|---|---|---|
| 11v11 engine: 22 players, 6 formations (4-3-3, 4-4-2, 4-2-3-1, 3-5-2, 5-3-2, 4-1-4-1), attributes drive speed/passing/shooting/tackling | ✅ | unit tests; full-match soak across all formation pairings; 55 game tests |
| Rules: kickoff, goals, throw-in, corner, goal kick, offside (position at pass, judged on first touch), fouls, **advantage**, free kick, penalty, yellow/red (**goalkeeper dismissal → bench keeper replaces a forward**), halves, added time, **extra time and a penalty shootout (knockout), change of ends**, substitutions | ✅ | `LawsTests`, `FlowTests`, `AdvancedRulesTests` |
| Skills & aerial play: **headers, volleys, finesse curl (Magnus), jockey, shielding, skill moves** (feint / drag-back / side-step beat most tackles) | ✅ | `SkillAndShotTests`, `AerialTests` |
| Physics: gravity, drag, Magnus, bounce, rolling, posts/bar/net, goal detection; frame-rate-independent | ✅ | 16 physics tests |
| AI: formation shape, marking, pressing, interception, overlaps, runs, utility-scored pass/shoot/dribble, goalkeeper trajectory prediction/dive/catch/parry/distribution, 5 difficulties | ✅ | behaviour tests; world-class vs beginner: 63 vs 29 goals, 188 vs 124 shots, 350 vs 144 tackles won (20 seeds × 2) |
| **Data-informed AI**: team shape fitted to real tracking (SkillCorner, MIT): simulated length 24.6 m vs real 23.4, width 25.9 vs 25.5, area 636 vs 646 m², spacing 8.7 vs 8.6; shot model fitted to 43,078 real shots (Wyscout, CC BY) | ✅ | `Tools/analyze_formations.py --compare`, `CalibrationTests`, `ShotModelTests` |
| Skinned Blender athlete (original): 3 LODs, 16 clips with speed-blended locomotion, kick/tackle/slide/fall/celebrate/GK clips, cross-fade state machine, kit colours per team | ✅ renders in-game | headless + live screenshots; `Tools/validate_assets.py` PASS |
| Stadium: stands, 1k–8k spectators by preset (**High is the default**), ad boards, flags, dugouts, floodlights, **working scoreboard**, day/sunset/night, overcast/rain (rain also changes ball physics) | ✅ renders (rain streaks not visible offscreen) | offscreen renders |
| Cameras: broadcast, tele, dynamic, end-to-end, player-follow, tactical, training, replay, penalty & free-kick (auto) | ✅ broadcast, dynamic, end-to-end, follow, tactical and penalty inspected; tele, training, free-kick and replay not | offscreen renders |
| Goal replays (30 Hz ring buffer, slow-mo, skip) | ⚠️ recorder/player logic tested; in-app playback not visually verified | `ReplayTests` |
| Menus, pause + substitutions, half/full-time stats, persistent settings | ✅ built; main menu, quick match, tournament, career, settings inspected in renders (tournament layout bug found and fixed); pause/substitution panels not inspected | offscreen `NSHostingView` renders |
| Tournament & career logic incl. persistence/migration/backup | ✅ | 25 tests |
| Audio: procedural crowd/kick/whistle/cheer/net/music, 3D-positioned SFX | ✅ synthesis tested; **not listened to** | 5 DSP tests |
| Controller support: GameController adapter, hot-plug, reconnect→pause, remap UI | ⚠️ logic tested; **no physical gamepad was available** | 9 mapping tests |

## Not implemented / planned (see `Documentation/KNOWN_LIMITATIONS.md` and `ROADMAP.md`)
MetaHuman/Fab/Mixamo/mocap characters (none acquired; pipeline + importers ready) · foot IK · custom Metal shaders (none justified by measurement) · grass shader · online multiplayer · notarization · trained ML models · live-hardware verification of gamepads.

## Tests & gates
```bash
cd Packages/FootballKit && swift test                                   # debug: fast tests (heavy full-match tests skip)
swift test -c release -Xswiftc -enable-testing                          # everything incl. full-match & statistical tests (~45 s)
python3 Tools/validate_assets.py     # re-imports every USDZ in Blender: skeleton, LODs, weights, scale, clip lengths
python3 Tools/validate_licenses.py   # fails if restricted data leaks into shipped code/assets
python3 Tools/inspect_datasets.py    # checksum + schema verification of downloaded datasets
```
Datasets, licences and what ships: `Datasets/LICENSE_AUDIT.md`. Credits/attribution: `Documentation/CREDITS.md`. Measured performance: `Documentation/PERFORMANCE_REPORT.md`.
