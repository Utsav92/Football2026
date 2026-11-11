# Credits & attribution
- **SkillCorner** — Open Data (tracking, A-League 2024/25), MIT licence, © 2020 SkillCorner. Used to fit team-shape constants and running-cadence calibration. https://github.com/SkillCorner/opendata
- **Pappalardo, L. et al.** — *A public data set of spatio-temporal match events in soccer competitions*, Scientific Data 6:236 (2019), and *PlayeRank*, ACM TIST 10(5):59 (2019). Wyscout public dataset, CC BY 4.0. Used to fit the shot (xG) model and pass statistics. https://figshare.com/collections/Soccer_match_event_dataset/4415000
- Blender 5.2 (GPL) was used as a tool; the generated assets are original.
Datasets reviewed but **not** used in the shipped game: Metrica sample (no licence; local research only), StatsBomb (commercial use prohibited), SportsMOT, AMASS, WorldPose, SoccerNet(-GAR) — see `Datasets/LICENSE_AUDIT.md`.

- Motion data: CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), free for all uses; credit requested.

## Microsoft Rocketbox Avatar Library (Unreal build)
Character meshes/textures (Male_Adult_01-08, Female_Adult_01) from https://github.com/microsoft/Microsoft-Rocketbox, MIT License, Copyright (c) 2020 Microsoft. The MIT notice must stay with any redistribution of these assets. Animations on them are the project's own athlete clips and CMU mocap, retargeted (Scripts/retarget_to_rocketbox.py).
