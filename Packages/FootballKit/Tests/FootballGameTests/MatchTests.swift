import XCTest
import simd
@testable import FootballGame
import FootballPhysics

func playing(_ m: MatchSimulation) { m.forcePhase(.playing) }
func advance(_ m: MatchSimulation, _ seconds: Float, _ input: [TeamSide: PlayerInput] = [:]) {
    for _ in 0..<Int((seconds * 120).rounded()) { m.step(input) }
}

final class SetupTests: XCTestCase {
    func testTwentyTwoPlayersWithOneKeeperEach() {
        let m = MatchSimulation(config: makeConfig())
        XCTAssertEqual(m.players.count, 22)
        for side in TeamSide.allCases {
            let team = m.players.filter { $0.team == side }
            XCTAssertEqual(team.count, 11)
            XCTAssertEqual(team.filter { $0.role == .gk }.count, 1)
            XCTAssertEqual(Set(team.map { $0.id }).count, 11)
        }
    }

    func testAllFormationsHaveElevenSlotsGoalkeeperFirst() {
        for f in Formation.allCases {
            let s = f.slots
            XCTAssertEqual(s.count, 11, f.rawValue)
            XCTAssertEqual(s[0].role, .gk)
            XCTAssertEqual(s.filter { $0.role == .gk }.count, 1)
            let n = f.rawValue.split(separator: "-").compactMap { Int($0) }
            let lines = [s.filter { $0.role.line == .defender }.count, s.filter { $0.role.line == .midfielder }.count, s.filter { $0.role.line == .forward }.count]
            XCTAssertEqual(lines.reduce(0, +), 10)
            XCTAssertEqual(lines[0], n[0], "\(f.rawValue) defenders")
            XCTAssertEqual(lines[2], n.last!, "\(f.rawValue) forwards")
        }
    }

    func testKickoffShapeTeamsInOwnHalfAndOpponentOutsideCircle() {
        let m = MatchSimulation(config: makeConfig())
        guard case .restart(let info) = m.phase else { return XCTFail() }
        XCTAssertEqual(info.kind, .kickoff); XCTAssertEqual(info.team, .home)
        for p in m.players where p.id != info.taker {
            XCTAssertLessThanOrEqual(p.pos.x * p.team.attackSign, 0.01, "player \(p.id) in own half")
            if p.team == .away { XCTAssertGreaterThanOrEqual(simd_length(p.pos), Laws.wallDistance - 0.1) }
        }
    }

    func testFormationShapeFollowsTheBall() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        func hold(_ x: Float, _ seconds: Float) {
            for _ in 0..<Int(seconds * 120) { m.placeBall(Vec3(x, 0.11, 0)); m.step() }
        }
        hold(-30, 10)
        let lineLow = meanX(m, .home, roles: .defender)
        hold(30, 14)
        let lineHigh = meanX(m, .home, roles: .defender)
        XCTAssertGreaterThan(lineHigh, lineLow + 5, "back line should step up when the ball is in the opponent half")
    }

    func testFormationRecognisableAfterTwoMinutes() throws {
        try skipInDebug()
        for f in Formation.allCases {
            let m = MatchSimulation(config: makeConfig(homeForm: f, awayForm: f))
            var n = 0
            var devSum: Float = 0, samples = 0
            while n < 120 * 120 {
                m.step(); _ = m.drainEvents(); n += 1
                if n % 240 == 0, case .playing = m.phase {
                    let ctx = m.teams[0].ctx
                    for p in m.players where p.team == .home && p.onPitch && p.role != .gk {
                        let a = m.anchorWorld(slot: p.slot, side: .home, ballDepth: ctx.ballDepth, inPossession: ctx.inPossession, ballLat: ctx.ballLat)
                        devSum += simd_distance(a, p.pos); samples += 1
                    }
                }
            }
            XCTAssertGreaterThan(samples, 0)
            XCTAssertLessThan(devSum / Float(max(samples, 1)), 16, "\(f.rawValue) mean deviation from formation anchors")
        }
    }

    func meanX(_ m: MatchSimulation, _ side: TeamSide, roles line: Role.Line) -> Float {
        let ps = m.players.filter { $0.team == side && $0.role.line == line }
        return ps.map { $0.pos.x * side.attackSign }.reduce(0, +) / Float(ps.count)
    }
}

final class FlowTests: XCTestCase {
    func testGoalScoresCelebratesAndConcedingTeamKicksOff() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        m.placeBall(Vec3(53.5, 0.5, 0))
        m.step()
        XCTAssertEqual(m.score.home, 1)
        if case .goalCelebration(_, let by) = m.phase { XCTAssertEqual(by, .home) } else { XCTFail("phase \(m.phase)") }
        advance(m, 4.2)
        guard case .restart(let info) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(info.kind, .kickoff); XCTAssertEqual(info.team, .away)
    }

    func testBallOverTouchlineGivesThrowInToOpponentOfLastTouch() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        m.lastTouch = 3  // a home player
        m.placeBall(Vec3(10, 0.2, 34.4), velocity: Vec3(0, 0, 3))
        advance(m, 0.2)
        guard case .restart(let info) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(info.kind, .throwIn); XCTAssertEqual(info.team, .away)
        XCTAssertEqual(m.players[info.taker].team, .away)
    }

    func testThrowInIsTakenByAITeamAndPlayResumes() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        m.lastTouch = 3
        m.placeBall(Vec3(10, 0.2, 34.4), velocity: Vec3(0, 0, 3))
        var resumed = false, thrown = false
        for _ in 0..<(120 * 8) {
            m.step()
            if m.drainEvents().contains(where: { if case .kick(_, _, _) = $0 { return true }; return false }) { thrown = true }
            if m.phase == .playing { resumed = true }
        }
        XCTAssertTrue(thrown, "the AI taker must throw the ball in")
        XCTAssertTrue(resumed, "play must resume after the throw-in")
    }

    func testCornerAndGoalKickAssignment() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        m.lastTouch = 14   // away player; ball behind +X goal line (away defends) -> corner for home
        m.placeBall(Vec3(53, 0.2, 10), velocity: Vec3(1, 0, 0))
        advance(m, 0.2)
        guard case .restart(let c) = m.phase else { return XCTFail() }
        XCTAssertEqual(c.kind, .corner); XCTAssertEqual(c.team, .home)
        playing(m); m.lastTouch = 4
        m.placeBall(Vec3(53, 0.2, 10), velocity: Vec3(1, 0, 0))
        advance(m, 0.2)
        guard case .restart(let g) = m.phase else { return XCTFail() }
        XCTAssertEqual(g.kind, .goalKick); XCTAssertEqual(g.team, .away)
        XCTAssertEqual(m.players[g.taker].role, .gk)
    }

    func testOffsideCalledOnFirstTouchOfPlayerInOffsidePosition() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        // Home passer at (0,0) with ball; home receiver at (35,5); away defenders at x<=30; away GK at 50.
        for p in m.players where p.team == .away { m.place(player: p.id, at: Vec2(p.role == .gk ? 50 : 30 - Float(p.slot), Float(p.slot) * 4 - 20)) }
        for p in m.players where p.team == .home { m.place(player: p.id, at: Vec2(-10, Float(p.slot) * 3 - 15)) }
        m.place(player: 9, at: Vec2(0, 0), heading: 0)
        m.place(player: 10, at: Vec2(38, 5))
        m.placeBall(Vec3(0.6, 0.11, 0))
        m.executePass(9, to: 10, kind: .pass, power: 0.8, human: true)
        XCTAssertTrue(m.pendingOffside.keys.contains(10))
        // Deterministic: deliver the ball to the offside receiver's feet (the AI defence is free to intercept a real pass).
        m.placeBall(Vec3(38.5, 0.11, 5.2)); m.lastTouch = 9
        var called = false
        for _ in 0..<(120 * 4) {
            m.step()
            if m.drainEvents().contains(.offside(player: 10)) { called = true; break }
        }
        XCTAssertTrue(called, "offside should be flagged when the offside receiver gets the ball")
        guard case .restart(let info) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(info.kind, .indirectFreeKick); XCTAssertEqual(info.team, .away)
    }

    func testOnsideReceiverNotFlagged() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        for p in m.players where p.team == .away { m.place(player: p.id, at: Vec2(p.role == .gk ? 50 : 36 - Float(p.slot), Float(p.slot) * 4 - 20)) }
        for p in m.players where p.team == .home { m.place(player: p.id, at: Vec2(-10, Float(p.slot) * 3 - 15)) }
        m.place(player: 9, at: Vec2(0, 0), heading: 0); m.place(player: 10, at: Vec2(30, 5))
        m.placeBall(Vec3(0.6, 0.11, 0))
        m.executePass(9, to: 10, kind: .pass, power: 0.8, human: true)
        XCTAssertFalse(m.pendingOffside.keys.contains(10))
    }

    func testFoulInsideAreaIsPenaltyOutsideIsFreeKick() {
        let m = MatchSimulation(config: makeConfig())
        playing(m)
        m.place(player: 11 + 5, at: Vec2(40, 3)); m.place(player: 4, at: Vec2(40.5, 3.5))   // away carrier fouled?
        // Home defender (4) fouls away attacker (16) inside the home... away attacks -X. Use areas explicitly:
        m.place(player: 16, at: Vec2(-45, 3)); m.place(player: 4, at: Vec2(-45.5, 3))
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        guard case .restart(let a) = m.phase else { return XCTFail() }
        XCTAssertEqual(a.kind, .penalty); XCTAssertEqual(a.team, .away); XCTAssertEqual(a.spot, Laws.penaltySpot(defending: .home))
        playing(m)
        m.place(player: 16, at: Vec2(-20, 3)); m.place(player: 4, at: Vec2(-20.5, 3))
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        guard case .restart(let b) = m.phase else { return XCTFail() }
        XCTAssertEqual(b.kind, .freeKick); XCTAssertEqual(b.team, .away)
        XCTAssertEqual(m.stats[0].fouls, 2)
    }

    func testSecondYellowIsRedAndPlayerLeavesPitch() {
        let m = MatchSimulation(config: makeConfig(seed: 3))
        playing(m)
        m.players[4].yellowCards = 1
        var sentOff = false
        for _ in 0..<60 {
            playing(m)
            m.place(player: 16, at: Vec2(0, 0)); m.place(player: 4, at: Vec2(0.5, 0))
            m.callFoul(by: 4, on: 16, severity: 1, fromBehind: true)
            if m.players[4].sentOff { sentOff = true; break }
            m.players[4].yellowCards = 1
        }
        XCTAssertTrue(sentOff)
        XCTAssertFalse(m.players[4].onPitch)
        XCTAssertEqual(m.players.filter { $0.team == .home && $0.onPitch }.count, 10)
        XCTAssertGreaterThanOrEqual(m.stats[0].redCards, 1)
    }

    func testHalfTimeSecondHalfAndFullTimeWithAddedTime() throws {
        try skipInDebug()
        let m = MatchSimulation(config: makeConfig(seed: 2, length: 30))
        var sawHalf = false, sawFull = false
        var n = 0
        var addedAtHalf: Float = 0
        while n < 120 * 120 && !sawFull {
            m.step(); n += 1
            for e in m.drainEvents() { if e == .halfTime { sawHalf = true; addedAtHalf = m.clock.addedSeconds }; if e == .fullTime { sawFull = true } }
        }
        XCTAssertTrue(sawHalf); XCTAssertTrue(sawFull)
        XCTAssertGreaterThanOrEqual(addedAtHalf, 60)
        XCTAssertEqual(m.clock.half, 2)
        XCTAssertGreaterThanOrEqual(m.clock.gameSeconds, 5400)
    }

    func testSubstitutionsLimitedToFive() {
        let m = MatchSimulation(config: makeConfig())
        for k in 0..<5 { XCTAssertTrue(m.substitute(.home, slot: 1 + k, with: 1 + (k % 4))) }
        XCTAssertFalse(m.substitute(.home, slot: 7, with: 2))
        XCTAssertEqual(m.substitutionsUsed(.home), 5)
        XCTAssertFalse(m.substitute(.away, slot: 0, with: 0), "cannot sub the keeper via outfield API")
    }
}
