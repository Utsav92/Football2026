# Roadmap
1. **Hardware verification**: real DualSense/DualShock tests (hot-plug, remap, two-pad versus); listen-through of audio and mix; visual pass over every menu screen.
2. **Characters**: purchase/download (by the owner) the Fab rigged footballer under the Professional tier and/or Mixamo clips → `Tools/import_character.py` → retarget → validate; selective MetaHuman for close-ups after reading the current EULA (AI-training clause is version-dependent).
3. **Animation**: foot IK and motion warping to the ball; header/volley/volleyed clips; mocap-grade clips from licensed sources; proper idle→run acceleration clips.
4. **Gameplay depth**: dedicated volley/skill/jockey animation clips; tune shootout realism; engine-level change of ends if it is ever needed beyond presentation.
5. **AI**: data-driven pressing triggers and run timing from more SkillCorner matches; benchmark any trained model against the rule baseline; difficulty tuning for goals.
6. **Graphics/perf**: live frame-pacing study (full-screen, 4K, thermal), grass shader and GPU-instanced crowd animation if profiling justifies Metal, reduce skinning compute.
7. **Release**: Developer ID signing, notarization, hardened runtime review, App Store sandbox review.
8. **Online multiplayer** (separate project).
