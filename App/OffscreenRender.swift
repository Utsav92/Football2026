import SwiftUI
import RealityKit
import Metal
import AppKit
import FootballGame
import FootballData

/// Headless verification: renders the live scene (RealityRenderer -> Metal texture) and SwiftUI screens (ImageRenderer) to PNG files
/// without a window, so results do not depend on the desktop. Also records per-frame render times.
///   Football2026 --render <dir> [--tod Night|Sunset|Day] [--weather Rain|Overcast|Clear] [--camera N] [--graphics low|medium|high] [--times 4,10,20]
@MainActor
enum OffscreenRender {
    static var requested: Bool { CommandLine.arguments.contains("--render") }

    private static func arg(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func writePNG(_ tex: MTLTexture, to url: URL) {
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }          // BGRA -> RGBA
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let img = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
    }

    static func run() async {
        let dir = URL(fileURLWithPath: arg("--render") ?? "/tmp/f26-render", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let router = AppRouter(); router.bootstrap()
        guard let db = router.database else { print("RENDER: database failed to load"); exit(1) }
        var cfg = router.makeConfig(home: db.clubs[0], away: db.clubs[6], humans: CommandLine.arguments.contains("--human") ? [.home] : [], minutes: 6, seed: 7)
        cfg.wetPitch = arg("--weather") == "Rain"
        var s = MatchSession(config: cfg, mode: .quick)
        s.timeOfDay = TimeOfDay(rawValue: arg("--tod") ?? "Day") ?? .day
        s.weather = Weather(rawValue: arg("--weather") ?? "Clear") ?? .clear
        if let g = arg("--graphics") { router.settings.value.graphics = GraphicsPreset.allCases.first { $0.rawValue.lowercased() == g } ?? .medium }
        await renderUI(router, dir)
        if CommandLine.arguments.contains("--overlays") { await renderOverlays(router, db, dir); exit(0) }
        await CharacterAssets.shared.load()
        print("RENDER: character assets available=\(CharacterAssets.shared.isAvailable) load=\(String(format: "%.2f", CharacterAssets.shared.loadSeconds))s error=\(CharacterAssets.shared.loadError ?? "none")")
        let model = GameModel(session: s, settings: router.settings, keyboard: router.keyboard, gamepad: router.gamepad, audio: router.audio)
        if let c = arg("--cam")?.split(separator: ",").compactMap({ Float($0) }), c.count == 6 { model.cameraOverride = (SIMD3(c[0], c[1], c[2]), SIMD3(c[3], c[4], c[5])) }
        if let c = arg("--camera"), let n = Int(c), let m = CameraMode(rawValue: n) { model.cameraRig.mode = m }
        func ns(_ c: ColorRGB) -> NSColor { NSColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1) }
        var o = PitchScene.SceneOptions(); o.preset = router.settings.value.graphics; o.timeOfDay = s.timeOfDay; o.weather = s.weather
        o.home = ns(cfg.home.primary); o.away = ns(cfg.away.primary); o.homeName = cfg.home.shortName; o.awayName = cfg.away.shortName
        if CommandLine.arguments.contains("--second-half") { model.sim.debugStartSecondHalf() }
        if CommandLine.arguments.contains("--penalty") { model.sim.setupRestart(.penalty, team: .home, spot: Laws.penaltySpot(defending: .away)) }
        let t0 = Date()
        await model.world.build(sim: model.sim, options: o)
        print("RENDER: scene built in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s — spectators \(model.world.stadium.spectatorCount), crowd triangles \(model.world.stadium.triangleCount), skinned=\(model.world.usingSkinned)")
        do {
            let renderer = try RealityRenderer()
            renderer.entities.append(model.world.root)
            renderer.activeCamera = model.world.cameraEntity
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 1280, height: 720, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            let device = MTLCreateSystemDefaultDevice()!
            let tex = device.makeTexture(descriptor: desc)!
            let times = (arg("--times") ?? "4,10").split(separator: ",").compactMap { Float($0) }
            var clock: Float = 0
            var renderMS: [Double] = [], stepMS: [Double] = []
            let dt: Float = 1.0 / 60
            for (k, target) in times.enumerated() {
                while clock < target {
                    let a = Date()
                    model.headlessAdvance(dt)
                    stepMS.append(Date().timeIntervalSince(a) * 1000)
                    clock += dt
                    if Int(clock / dt) % 6 == 0 || clock >= target {       // render every 6th frame for timing; always at the target
                        let r0 = Date()
                        let out = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))
                        try renderer.updateAndRender(deltaTime: TimeInterval(dt * 6), cameraOutput: out, onComplete: { _ in })
                        renderMS.append(Date().timeIntervalSince(r0) * 1000)
                    }
                }
                try await Task.sleep(nanoseconds: 300_000_000)
                writePNG(tex, to: dir.appendingPathComponent("scene\(k)_t\(Int(target)).png"))
                print("RENDER: wrote scene\(k)_t\(Int(target)).png (match clock \(model.sim.clock.display), score \(model.sim.score.home)-\(model.sim.score.away), camera \(model.cameraRig.effective.name))")
            }
            func stat(_ v: [Double]) -> String { let s = v.sorted(); return v.isEmpty ? "n/a" : String(format: "mean %.2f ms, p95 %.2f ms, max %.2f ms (n=%d)", v.reduce(0, +) / Double(v.count), s[Int(Double(s.count - 1) * 0.95)], s.last!, v.count) }
            print("PERF sim+scene-sync per frame: \(stat(stepMS))")
            print("PERF RealityRenderer frame 1280x720 (CPU encode + GPU wait; first frame includes shader warm-up): \(stat(renderMS))")
        } catch { print("RENDER ERROR: \(error)") }
        exit(0)
    }

    /// Match overlays (pause, substitutions, summaries, HUD) over the pitch colour, using a real GameModel that has simulated a few minutes.
    static func renderOverlays(_ router: AppRouter, _ db: GameDatabase, _ dir: URL) async {
        func save<V: View>(_ v: V, _ name: String, w: CGFloat = 1180, h: CGFloat = 740) async {
            let host = NSHostingView(rootView: ZStack { LinearGradient(colors: [Color(red: 0.12, green: 0.42, blue: 0.16), Color(red: 0.08, green: 0.3, blue: 0.12)], startPoint: .top, endPoint: .bottom); v }.frame(width: w, height: h).environment(\.colorScheme, .dark))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host; win.setFrameOrigin(NSPoint(x: -3000, y: -3000)); win.orderFrontRegardless()
            try? await Task.sleep(nanoseconds: 450_000_000); host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("ov_\(name).png")); win.orderOut(nil); print("RENDER: wrote ov_\(name).png")
        }
        var cfg = router.makeConfig(home: db.clubs[0], away: db.clubs[6], humans: [.home], minutes: 6, seed: 7)
        cfg.knockout = false
        let model = GameModel(session: MatchSession(config: cfg, mode: .quick), settings: router.settings, keyboard: router.keyboard, gamepad: router.gamepad, audio: router.audio)
        for _ in 0..<2400 { model.sim.step([.home: PlayerInput()]) }       // 20 s of play
        model.refreshSubLists()
        model.homeScore = 1; model.awayScore = 0; model.clockText = "34:12  1H"; model.playerName = "Q. Zielinski"; model.playerNumber = 9; model.playerRole = "ST"
        model.shotsText = "6 – 3"; model.possessionHome = 58; model.cameraName = "Broadcast"; model.minimap = model.sim.players.filter { $0.onPitch }.map { MiniDot(id: $0.id, x: $0.pos.x, z: $0.pos.y, team: $0.team, controlled: false, isBall: false) }
        await save(HUDView(model: model), "hud")
        model.paused = true
        await save(PauseOverlay(model: model, router: router, outSlot: .constant(nil), showSubs: .constant(false)), "pause")
        await save(PauseOverlay(model: model, router: router, outSlot: .constant(4), showSubs: .constant(true)), "subs")
        model.paused = false
        model.summaryTitle = "HALF TIME"; model.summaryRows = [SummaryRow(label: "Possession", home: "58%", away: "42%"), SummaryRow(label: "Shots", home: "6", away: "3"), SummaryRow(label: "On target", home: "4", away: "1"), SummaryRow(label: "Passes (completed)", home: "211 (84%)", away: "164 (77%)"), SummaryRow(label: "Fouls", home: "5", away: "7")]
        await save(SummaryOverlay(model: model), "summary")
        model.banner = "GOAL!"; model.subBanner = "#9 Q. Zielinski"; model.toast = "Teams change ends"; model.shootoutText = "ALD 3 – 2 RED  (9 kicks)"; model.replayActive = false; model.charging = true; model.chargeLevel = 0.7; model.chargeKind = "SHOT"
        await save(HUDView(model: model), "hud_goal")
    }

    /// SwiftUI screens to PNG via an offscreen NSHostingView (draws native pickers/scroll views, unlike ImageRenderer).
    static func renderUI(_ router: AppRouter, _ dir: URL) async {
        func save<V: View>(_ v: V, _ name: String, w: CGFloat = 1180, h: CGFloat = 780) async {
            let host = NSHostingView(rootView: v.frame(width: w, height: h).environment(\.colorScheme, .dark))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host; win.setFrameOrigin(NSPoint(x: -3000, y: -3000)); win.orderFrontRegardless()
            try? await Task.sleep(nanoseconds: 450_000_000)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("ui_\(name).png"))
            win.orderOut(nil); print("RENDER: wrote ui_\(name).png")
        }
        await save(MainMenuView(router: router), "mainmenu")
        await save(QuickMatchView(router: router, versus: false), "quickmatch")
        await save(SettingsView(router: router), "settings")
        await save(TrainingMenuView(router: router), "training")
        if let db = router.database {
            router.newTournament(format: .groupsThenKnockout(groups: 2, advancePerGroup: 2), clubCount: 8, userClub: db.clubs[0].id)
            for _ in 0..<3 { router.simulateTournamentRound() }
            await save(TournamentView(router: router), "tournament")
            router.newCareer(clubID: db.clubs[5].id)
            for _ in 0..<6 { router.simulateCareerWeek() }
            await save(CareerView(router: router), "career")
            router.tournament = nil
        }
    }
}
