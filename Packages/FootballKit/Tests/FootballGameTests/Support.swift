import FootballGame
import FootballPhysics

func makeConfig(humans: Set<TeamSide> = [], seed: UInt64 = 1, length: Float = 360, homeForm: Formation = .f433, awayForm: Formation = .f442,
                difficulty: Difficulty = .professional, homeQ: Int = 68, awayQ: Int = 68) -> MatchConfig {
    let h = TeamSetup.generated(name: "Harbour FC", short: "HAR", quality: homeQ, formation: homeForm, seed: seed &* 3 + 1,
                                primary: ColorRGB(0.85, 0.1, 0.12), secondary: ColorRGB(1, 1, 1), idBase: 0)
    let a = TeamSetup.generated(name: "Ironvale", short: "IRO", quality: awayQ, formation: awayForm, seed: seed &* 7 + 2,
                                primary: ColorRGB(0.1, 0.25, 0.8), secondary: ColorRGB(0.05, 0.05, 0.1), idBase: 100)
    return MatchConfig(home: h, away: a, matchLengthSeconds: length, difficulty: difficulty, humanTeams: humans, seed: seed)
}

import XCTest
/// Statistical / full-match tests are meant for optimised builds (a debug match takes ~30 s).
func skipInDebug() throws {
    #if DEBUG
    throw XCTSkip("Heavy simulation test: run with `swift test -c release -Xswiftc -enable-testing`")
    #endif
}
