import SwiftUI
import AppKit
import FootballGame
import FootballData

nonisolated(unsafe) var perfActivity: NSObjectProtocol?

@main
struct Football2026App: App {
    @State private var router = AppRouter()

    init() { if OffscreenRender.requested { Task { @MainActor in await OffscreenRender.run() } } }

    var body: some Scene {
        WindowGroup("Football 2026") {
            RootView(router: router)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true); router.bootstrap(); launchShortcuts()
                    if CommandLine.arguments.contains("--perf") { perfActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "frame-rate measurement") }
                }
        }
        .windowResizability(.contentMinSize)
    }

    /// Launch flags used for verification: --autoplay (AI vs AI), --training <kind>, --menu.
    private func launchShortcuts() {
        let a = CommandLine.arguments
        guard a.contains("--autoplay") || a.contains("--quick"), let db = router.database else { return }
        var cfg = router.makeConfig(home: db.clubs[0], away: db.clubs[6], humans: a.contains("--autoplay") ? [] : [.home], minutes: 6, seed: 7)
        if let i = a.firstIndex(of: "--minutes"), i + 1 < a.count, let m = Float(a[i + 1]) { cfg.matchLengthSeconds = m * 60 }
        var s = MatchSession(config: cfg, mode: .quick)
        if let i = a.firstIndex(of: "--tod"), i + 1 < a.count, let t = TimeOfDay(rawValue: a[i + 1]) { s.timeOfDay = t }
        if let i = a.firstIndex(of: "--weather"), i + 1 < a.count, let w = Weather(rawValue: a[i + 1]) { s.weather = w }
        router.screen = .splash
        Task { try? await Task.sleep(nanoseconds: 300_000_000); router.start(s, returnTo: .mainMenu) { _ in } }
    }
}
