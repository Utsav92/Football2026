import XCTest
import simd
@testable import FootballGame
import FootballPhysics

/// Guards the data-fitted team shape (TacticalPriors). Bands are the real-data value ± a tolerance:
/// SkillCorner 2024/25 (out of possession): length 23.4 m, width 25.5 m; defensive-line slope vs ball 0.58 (Metrica 0.52).
final class CalibrationTests: XCTestCase {
    func pct(_ v: [Float], _ q: Float) -> Float {
        let s = v.sorted(); let i = q * Float(s.count - 1); let lo = Int(i.rounded(.down)); let hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (i - Float(lo))
    }

    func testSimulatedTeamShapeMatchesRealTrackingBands() throws {
        try skipInDebug()
        var lengths: [Float] = [], widths: [Float] = [], bx: [Float] = [], line: [Float] = []
        for seed in 1...3 {
            let m = MatchSimulation(config: makeConfig(seed: UInt64(seed)))
            var n = 0
            while m.phase != .fullTime && n < 120 * 500 {
                m.step(); n += 1; _ = m.drainEvents()
                guard n % 120 == 0, case .playing = m.phase, let owner = m.ballOwner else { continue }
                let attacking = m.players[owner].team
                let side = attacking.opponent                     // team out of possession
                let dir = side.attackSign
                let outfield = m.players.filter { $0.team == side && $0.onPitch }.map { SIMD2($0.pos.x * dir, $0.pos.y * dir) }.sorted { $0.x < $1.x }.dropFirst()
                let xs = outfield.map { $0.x }, ys = outfield.map { $0.y }
                lengths.append(pct(xs, 0.9) - pct(xs, 0.1)); widths.append(pct(ys, 0.9) - pct(ys, 0.1))
                bx.append(m.ball.position.x * dir); line.append(xs.prefix(4).reduce(0, +) / 4)
            }
        }
        let mean = { (v: [Float]) in v.reduce(0, +) / Float(v.count) }
        XCTAssertGreaterThan(lengths.count, 100)
        XCTAssertEqual(mean(lengths), 23.4, accuracy: 6, "team length out of possession")
        XCTAssertEqual(mean(widths), 25.5, accuracy: 6, "team width out of possession")
        // Least-squares slope of the defensive line against the ball.
        let mb = mean(bx), ml = mean(line)
        var sxy: Float = 0, sxx: Float = 0
        for i in 0..<bx.count { sxy += (bx[i] - mb) * (line[i] - ml); sxx += (bx[i] - mb) * (bx[i] - mb) }
        XCTAssertEqual(sxy / sxx, 0.58, accuracy: 0.15, "defensive line should follow the ball like real teams")
    }
}

final class ShotModelTests: XCTestCase {
    /// Empirical Wyscout goal rates (all shots, 43k): 8-12 m 17.5%, 16-20 m 7.3%, 24-28 m 2.6%.
    func testXGMatchesEmpiricalDistanceBands() {
        XCTAssertEqual(TacticalPriors.xG(dx: 10, dy: 0), 0.20, accuracy: 0.07)
        XCTAssertEqual(TacticalPriors.xG(dx: 18, dy: 0), 0.075, accuracy: 0.03)
        XCTAssertEqual(TacticalPriors.xG(dx: 26, dy: 0), 0.03, accuracy: 0.015)
    }
    func testXGMonotonicInDistanceAndWorseFromWideAnglesAndHeaders() {
        var last: Float = 1
        for d in stride(from: 5, through: 35, by: 5) { let x = TacticalPriors.xG(dx: Float(d), dy: 0); XCTAssertLessThan(x, last); last = x }
        XCTAssertLessThan(TacticalPriors.xG(dx: 8, dy: 15), TacticalPriors.xG(dx: 8, dy: 0))
        XCTAssertLessThan(TacticalPriors.xG(dx: 8, dy: 0, header: true), TacticalPriors.xG(dx: 8, dy: 0))
        XCTAssertTrue((0...1).contains(TacticalPriors.xG(dx: 0.5, dy: 0)))
    }
}
