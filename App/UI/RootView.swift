import SwiftUI

struct RootView: View {
    let router: AppRouter
    var body: some View {
        ZStack {
            switch router.screen {
            case .splash: SplashView(router: router)
            case .mainMenu: MainMenuView(router: router)
            case .quickMatch(let versus): QuickMatchView(router: router, versus: versus)
            case .training: TrainingMenuView(router: router)
            case .tournament: TournamentView(router: router)
            case .career: CareerView(router: router)
            case .settings: SettingsView(router: router)
            case .match: if let m = router.match { MatchView(model: m, router: router).id(m.session.id) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.screen)
    }
}
