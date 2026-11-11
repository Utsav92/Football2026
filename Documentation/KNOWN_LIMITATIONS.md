# Known limitations & defects (honest list)

**Verification gaps**
- No physical gamepad was available: the GameController adapter, hot-plug/reconnect-to-pause and two-controller assignment are written, their mapping logic is unit-tested, but they have not run against real hardware.
- Audio is synthesised and unit-tested (finite, unclipped, loop seamless, whistle spectrum) but nobody has listened to it; mix levels are unverified.
- Main menu, quick match, tournament, career and settings were inspected in offscreen `NSHostingView` renders (the tournament layout overlap and wasted vertical space found there were fixed). The pause menu, substitution panel, summary overlays and training screen were not inspected.
- Live window frame rate was not reliably measured (see PERFORMANCE_REPORT).
- Rain particles do not show in offscreen renders; whether they show in the live window is unverified.
- RealityKit finding: in the offscreen renderer a texture/mesh swapped on a live entity is not displayed; `isEnabled` toggles and transforms are. The scoreboard therefore uses pre-made digit glyphs. Whether the same limitation applies to the live RealityView was not tested.

**Gameplay**
- Implemented since the first release: headers, volleys, finesse curl, jockey/shield, skill moves, advantage rule, extra time + real shootout, goalkeeper red cards, change of ends (second half and second extra-time period).
- Change of ends is a *presentation* rotation (viewer simulation mirrored 180°, input negated, cameras flipped); the authoritative engine keeps one direction. Mirrored rendering was verified (teams swap sides at 45:07) but input negation and the mirrored mini-map were only unit-/logic-tested, not played.
- A sent-off keeper's replacement keeps an outfield kit on screen (the rig is built at kick-off) and the animation set has no dedicated volley/skill clips (volleys reuse `kick`; skill moves have no clip).
- Shootout kicks/saves are decided by the same physics as open play; human kickers use the normal charged-shot input. Not yet tuned for realism (conversion rate unmeasured).
- AI pass completion is ~50–65 %; the difficulty effect is large in tackles/shots but modest in goals. No ML model was trained.
- A human taker waits up to 9 s on restarts before the AI takes over. Substitution AI is a simple tired-player swap.

**Characters & animation**
- The athlete is an original stylised placeholder (blocky anatomy, no face, no cloth, no hair physics, no shirt numbers on the skinned model — the HUD shows the number). It is not photorealistic and does not use MetaHuman, the Fab listing, Mixamo or motion capture (none were acquired).
- Clips are procedurally keyframed, not mocap. Ball contact is synchronised to the kick event within ~0.1 s (contact is frame 3 of the clip); there is no foot IK.
- Retargeting (`Tools/retarget_animations.py`) was verified only on a synthetic Mixamo-named source; T-pose→A-pose correction is not implemented.

**Graphics**
- RealityKit only. No custom Metal shader was written: none was justified by measurement. No grass shader, no hardware ray tracing, no TAA control. SpotLightComponent produced no light in this renderer, so floodlights are point lights.
- Crowd is one static mesh per stand with a vertical bounce, not individually animated spectators.

**Distribution**
- Ad-hoc signed, not notarized (Gatekeeper rejects it). App Store sandbox/privacy review not done.
- Unreal Engine was not used (not installed; unsupported on macOS 27/Xcode 27 per Epic's docs).
