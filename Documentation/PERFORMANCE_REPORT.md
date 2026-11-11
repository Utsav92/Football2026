# Performance report (measured 2026-11-09)

Machine: Apple M5 Pro (16-core GPU), 24 GB, macOS 27.0, Xcode 27.2, Release build (`-O`, whole-module). Nothing below is extrapolated.

## Simulation (render-independent)
`SimExport --bench`: 5 full AI-vs-AI 11v11 matches, 120 Hz fixed steps.
| Metric | Value |
|---|---|
| Time per 22-player step | median **13.8 µs** (best 13.5, worst 16.0) |
| Throughput | ≈72,000 steps/s (600× real time) |
| Cost of the 120 Hz timestep | ≈0.17 % of one core |
The unit-test suite plays 8+ full matches in a few seconds in release for the same reason.

## Update (default preset is now High)
Five consecutive High-preset runs (7,704 spectators) gave a **bimodal** result: two runs at mean 4.7–5.8 ms (p95 ≈ 5 ms) and three runs at mean ≈12 ms (p95 15.6–17.7 ms). The modes alternate between identical runs, which points to GPU clock state or contention on this shared machine rather than the code (a floodlight change in between had no effect on the fast mode). **Consequence: High at 720p offscreen sits at or just inside the 16.7 ms / 60 fps budget in its slow mode and is not a guaranteed 60 fps.** Night (4 point lights on): mean 5.7 ms, p95 12.2 ms in the one run taken. Medium: mean 5.8 ms, p95 6.8 ms.

## Rendering — offscreen `RealityRenderer`, 1280×720 (first measurements, before High became the default) (`Football2026 --render <dir> --graphics <preset>`)
| Preset | Spectators | Crowd triangles | Scene build | Frame (CPU encode + GPU wait) mean / p95 | Peak RSS |
|---|---|---|---|---|---|
| Low | 1,033 | 24.8 k | 0.50 s | 6.0 / 3.8 ms | 310 MB |
| Medium | 3,437 | 82.5 k | 0.64 s | 4.8 / 4.4 ms | 321 MB |
| High | 7,704 | 184.9 k | 0.64 s | 4.3 / 5.4 ms | 326 MB |
Simulation + scene synchronisation (22 skinned rigs, camera, LOD): **0.08 ms** mean per frame (p95 0.15–0.19 ms). First rendered frame costs 55–330 ms
(shader warm-up) and is excluded from "typical" figures above only through the p95; it is in the max. Differences between presets are inside run-to-run
noise: at this resolution the GPU is not the limiting factor.
Startup: 22 skinned characters' assets load in 1.1 s; the app bundle is 6 MB (2.4 MB of characters).

## GPU time (Instruments, Metal System Trace)
`xctrace record --template "Metal System Trace"` of the offscreen run (Medium preset), intervals filtered to this process (887 intervals):
GPU busy time per rendered frame — **median 2.66 ms, mean 4.22 ms, p95 13.7 ms (includes shader warm-up frames), max 36.7 ms.**
By channel: Compute 327 ms total (skinning/culling), Fragment 54 ms, Vertex 19 ms. Frames were grouped by time gaps, so per-frame figures are approximate.

## Live window — partial and NOT a 60 FPS proof
The live window reported **45.8–50 fps**, 0.27–0.29 ms main-thread frame work and 271–324 MB RSS in two 5-second samples. This desktop was shared and the window
was partly covered, which makes macOS throttle RealityView; one attempt to force the window on top stopped the update loop altogether. I therefore do **not**
claim 60 FPS in a window, at 4K, or full-screen. Offscreen numbers show headroom (4–6 ms CPU+GPU, 2.7 ms GPU median at 720p), but live frame pacing was not measured.

## Not measured
Thermal behaviour / sustained load · live frame pacing and 1 % lows · 4K and full-screen cost · memory growth over a full 6-minute match · draw-call counts ·
battery/power · RealityKit-internal CPU time (a Time Profiler trace was not captured).
## How to reproduce
`swift run -c release SimExport --bench` · `Football2026 --render /tmp/out --times 4,14 --graphics medium` · `xcrun xctrace record --template "Metal System Trace" --launch -- <app binary> --render …`
