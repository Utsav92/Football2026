# Character asset pipeline

```
make_football_player.py (Blender 5.2, headless)  ->  Assets/Characters/out/{player_lod0..2.usdz, anim_*.usdz, player.json, player.blend}
Tools/gen_pbxproj.py (stages)                    ->  Assets/Bundle/  ->  app Resources
Tools/validate_assets.py (re-imports in Blender) ->  Datasets/validation/asset_validation.json   (PASS required)
CharacterAssets.swift / SkinnedPlayerRig.swift   ->  RealityKit entities, kit colours per team, LOD + clip state machine
```
Run: `/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/make_football_player.py -- Assets/Characters/out --lods` (≈20 s).
Preview poses: `Blender -b Assets/Characters/out/player.blend --python Tools/blender/preview_poses.py -- sheet.png kick:3 slide:18 …`.

## Conventions
Blender Z-up, faces −Y, metres, feet at z=0 → USD Y-up, forward −Z (the app rotates the model −90° about Y so game forward is +X). 21 bones, one skeleton for
every file. Materials in fixed slot order: skin, shirt, shorts, socks, boots, hair (the app replaces them per team). Skin weights: inverse-distance^4 to bone
segments, top-3 for LOD0, top-4 pruned for baked LODs. Each clip file carries the lowest-LOD mesh because RealityKit exposes animations only on files with a skinned mesh.

## Lessons recorded (all found by validation, not assumed)
- Blender's USD exporter ignores modifiers on skinned meshes → LODs are baked into real mesh data (466 vs 5,808 verts).
- The exporter trims trailing identical frames → a held `fall` pose played 0.47 s instead of 1.0 s; fixed with a sub-millimetre drift on non-looping clips.
- Decimation breaks the ≤4-influence guarantee → weights are pruned and renormalised after baking.
- USD renames `.L` joints to `_L` → validators normalise names.
- Blender 5 layered actions removed `Action.fcurves` → helper in `_retarget_inner.py`.

## Adding third-party assets (you acquire them; nothing is auto-downloaded)
1. Fab / other model: `python3 Tools/import_character.py <file> --license-confirmed "<licence + order>"` → report in `Datasets/characters/` (skeleton family, tris, textures, weights, height, next step).
2. Mixamo/UE clips: `python3 Tools/retarget_animations.py --source clip.fbx --map mixamo --name run --out Assets/Characters/out`, then `Tools/validate_assets.py`.
3. Never commit raw third-party files you may not redistribute; `Datasets/LICENSE_AUDIT.md` lists the terms found for each source.
Self-tests: `python3 Tools/import_character.py --selftest` (FBX path on our own export), `python3 Tools/retarget_animations.py --selftest` (synthetic Mixamo-named source).
