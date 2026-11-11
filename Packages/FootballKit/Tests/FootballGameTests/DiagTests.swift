import XCTest
import simd
@testable import FootballGame
import FootballPhysics

/// Not an assertion test: prints aggregate behaviour metrics used to tune and document the AI.
final class BenchmarkTests: XCTestCase {
    func testBenchmark() throws {
        try skipInDebug()
        var shots = 0, onT = 0, goals = 0, passes = 0, ok = 0, fouls = 0, cards = 0, corners = 0, offs = 0, throwIns = 0, saves = 0, tackles = 0, won = 0, poss = 0
        let N = 8
        for seed in 1...N {
            let m = MatchSimulation(config: makeConfig(seed: UInt64(seed)))
            var n = 0
            while m.phase != .fullTime && n < 120 * 420 {
                m.step(); n += 1
                for e in m.drainEvents() {
                    switch e {
                    case .passCompleted: ok += 1
                    case .save: saves += 1
                    case .possession: poss += 1
                    case .restart(.throwIn, _): throwIns += 1
                    default: break
                    }
                }
            }
            for t in 0..<2 { let s = m.stats[t]; shots += s.shots; onT += s.shotsOnTarget; passes += s.passes; fouls += s.fouls
                cards += s.yellowCards + s.redCards; corners += s.corners; offs += s.offsides; tackles += s.tackles; won += s.tacklesWon }
            goals += m.score.home + m.score.away
        }
        let f = { (x: Int) in String(format: "%.1f", Double(x) / Double(N)) }
        print("BENCH per match: goals \(f(goals)) shots \(f(shots)) onTarget \(f(onT)) saves \(f(saves)) passes \(f(passes)) completed \(f(ok)) (\(passes > 0 ? ok * 100 / passes : 0)%) tackles \(f(tackles)) won \(f(won)) fouls \(f(fouls)) cards \(f(cards)) corners \(f(corners)) throwIns \(f(throwIns)) offsides \(f(offs)) possessionChanges \(f(poss))")
    }
}
