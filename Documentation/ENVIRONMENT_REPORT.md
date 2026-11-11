# Environment & Unreal Engine feasibility report — 2026-11-09

## Machine (measured)
| Item | Value |
|---|---|
| Chip | Apple M5 Pro, 16-core GPU, **Metal 4** reported by `system_profiler` |
| Memory | 24 GB unified |
| macOS | 27.0 (build 26A425) |
| Xcode | 27.2 (27B52); SDKs: macOS / iOS / tvOS 27.2 |
| Free disk | ~82 GB of 460 GB on the system volume |
| Swift | 6.4.2 |
| Blender | 5.2.3 LTS at /Applications/Blender.app |

## Unreal Engine on this machine (measured)
- `/Users/Shared/Epic Games/UE_5.7` and `UE_5.8` exist but are **empty install shells** (32–35 MB, one `.egstore/Pending/*.manifest` each, created today 18:51).
- `~/Library/Application Support/Epic/UnrealEngineLauncher/LauncherInstalled.dat` → `"InstallationList": []`.
- No `UnrealEditor`, `UnrealBuildTool` or `.uproject` anywhere on disk. **No Unreal Engine is installed.** The Epic Games Launcher is running; the engine downloads were queued but not performed.

## Compatibility with Epic's documentation (web, 2026-11-09)
- UE 5.8 macOS requirements page: minimum macOS Sonoma 14.5, recommended Sequoia 15; **minimum Xcode 26.0, recommended Xcode 26.1.1; Xcode 26.4 documented as incompatible**.
- This machine is on **macOS 27 + Xcode 27**, neither of which the Epic pages list as supported. Forum reports (user reports, not Epic guidance) state UE 5.8.1/5.8.2/5.8.3 fail to build Game targets on macOS 27 + Xcode 27.
- macOS cannot be downgraded in place; a second, older Xcode can sit beside Xcode 27 but whether it runs on macOS 27 is unverified.
- Not verified (needs an installed engine): Metal RHI startup, Lumen/Nanite/VSM support on M5 Pro, Xcode project generation, packaging.

## Disk budget
UE for Mac is tens of GB plus derived data and Xcode caches; 82 GB free is tight for engine + project + MetaHuman content.

## Sources
- https://dev.epicgames.com/documentation/en-us/unreal-engine/macos-development-requirements-for-unreal-engine
- https://forums.unrealengine.com/t/ue5-8-unable-to-build-game-on-macos-27/2746676
- https://forums.unrealengine.com/t/ue-5-8-3-build-macos-27-every-mac-game-target-build-fails-at-failed-to-finalize-the-app-with-xcode-because-uba-starts-xcodebuild-with-stdin-closed/2840411
