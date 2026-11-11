import Foundation
import FootballGame
import FootballModes

enum MatchMode: Equatable {
    case quick
    case tournament(fixtureID: Int)
    case career
    case training(TrainingKind)
    var isCompetitive: Bool { if case .training = self { return false }; return true }
}

struct MatchSession: Identifiable {
    let id = UUID()
    var config: MatchConfig
    var mode: MatchMode = .quick
    var homeClubID = 0, awayClubID = 0
    var timeOfDay: TimeOfDay = .day
    var weather: Weather = .clear
    var stadiumName = "Harbour Park"
    var knockout = false
}

struct MatchOutcome {
    var homeGoals: Int
    var awayGoals: Int
    var stats: [TeamStats]
    var shootoutWinner: TeamSide?
    var extraTime = false
    var knockoutTie: Bool { homeGoals == awayGoals }
}
