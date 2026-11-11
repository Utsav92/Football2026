import XCTest
import simd
@testable import FootballGame
import FootballPhysics

final class SkillAndShotTests: XCTestCase {
    func human(_ seed: UInt64 = 1) -> MatchSimulation {
        let m = MatchSimulation(config: makeConfig(humans: [.home], seed: seed)); playing(m)
        let c = m.controlled(.home)!
        for p in m.players where p.id != c && p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
        return m
    }

    func testFinesseShotCurvesIntoTheGoalFromOutsideThePost() {
        var curled = 0
        for seed in 1...12 {
            let m = human(UInt64(seed)); let c = m.controlled(.home)!
            m.place(player: 11, at: Vec2(51, 20), heading: .pi)               // keeper out of the way: measure the ball path only
            m.place(player: c, at: Vec2(34, 10), heading: 0); m.placeBall(Vec3(34.9, 0.11, 10))
            m.executeShot(c, power: 1, aim: unit(Vec2(18.5, -10)), human: true, finesse: true)
            let v = m.ball.velocity
            let zAtLine0 = 10 + v.z / v.x * (52.5 - 34.9)
            XCTAssertGreaterThan(abs(m.ball.curveSpin.y), 10)
            var crossing: Float?
            for _ in 0..<(120 * 3) { m.step(); if m.ball.position.x >= 52.5 { crossing = m.ball.position.z; break } }
            if let z = crossing, abs(zAtLine0) > abs(z) + 0.3 { curled += 1 }
        }
        XCTAssertGreaterThan(curled, 8, "the Magnus force should bend a finesse shot back towards the goal (\(curled)/12)")
    }

    func testPlainShotHasNoCurve() {
        let m = human(); let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(34, 0), heading: 0); m.placeBall(Vec3(34.9, 0.11, 0))
        m.executeShot(c, power: 0.8, aim: Vec2(1, 0), human: true)
        XCTAssertEqual(m.ball.curveSpin, .zero)
    }

    func testJockeySlowsAndKeepsFacingTheBall() {
        let m = human(); let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(-10, 0), heading: 0); m.placeBall(Vec3(-10, 0.11, 7))       // ball to the side, but still nearest to this player
        advance(m, 3, [.home: PlayerInput(move: Vec2(1, 0), sprint: true)])
        let free = m.players[c].speed
        m.place(player: c, at: Vec2(-10, 0), heading: 0); m.placeBall(Vec3(-10, 0.11, 7))
        advance(m, 3, [.home: PlayerInput(move: Vec2(1, 0), sprint: true, jockeyHeld: true)])
        XCTAssertLessThan(m.players[c].speed, free * 0.7)
        let toBall = Vec2(m.ball.position.x, m.ball.position.z) - m.players[c].pos
        var d = atan2(toBall.y, toBall.x) - m.players[c].heading
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        XCTAssertLessThan(abs(d), 0.5, "jockeying defender keeps facing the ball while shuffling")
    }

    func tackleWinRate(shield: Bool = false, evade: Bool = false) -> Float {
        var wins = 0
        for seed in 1...150 {
            let m = MatchSimulation(config: makeConfig(humans: [.home], seed: UInt64(seed))); playing(m)
            let c = m.controlled(.home)!, carrier = 11 + 9
            for p in m.players where p.id != c && p.id != carrier { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
            m.place(player: c, at: Vec2(0, 0), heading: 0); m.place(player: carrier, at: Vec2(1, 0), heading: .pi)
            m.placeBall(Vec3(0.5, 0.11, 0)); m.ballOwner = carrier; m.lastTouch = carrier
            m.players[carrier].jockey = shield; m.players[carrier].evade = evade ? 0.5 : 0
            m.step([.home: PlayerInput(tackleHeld: true)])
            if m.ballOwner != carrier { wins += 1 }
        }
        return Float(wins) / 150
    }

    func testShieldingAndSkillMovesMakeTacklesHarder() {
        let base = tackleWinRate(), shield = tackleWinRate(shield: true), skill = tackleWinRate(evade: true)
        XCTAssertLessThan(shield, base - 0.04, "shielding \(shield) vs \(base)")
        XCTAssertLessThan(skill, base * 0.6, "a skill move beats most challenges: \(skill) vs \(base)")
    }

    func testSkillMoveFiresEventSetsEvadeAndHasCooldown() {
        let m = human(); let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(0, 0), heading: 0); m.placeBall(Vec3(0.9, 0.11, 0.3))
        advance(m, 0.5, [.home: PlayerInput()])
        XCTAssertEqual(m.ballOwner, c)
        _ = m.drainEvents()
        m.step([.home: PlayerInput(skill: Vec2(0, 1))])               // side-step
        XCTAssertTrue(m.drainEvents().contains(.skillMove(player: c)))
        XCTAssertGreaterThan(m.players[c].evade, 0.3)
        XCTAssertGreaterThan(m.players[c].skillCooldown, 0.5)
        m.step([.home: PlayerInput(skill: Vec2(0, 1))])
        XCTAssertFalse(m.drainEvents().contains(.skillMove(player: c)), "cooldown prevents spamming")
    }

    func testDragBackPullsTheBallBehindThePlayer() {
        let m = human(); let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(0, 0), heading: 0); m.placeBall(Vec3(0.9, 0.11, 0.3))
        advance(m, 0.5, [.home: PlayerInput()])
        let before = m.ball.position.x - m.players[c].pos.x
        m.step([.home: PlayerInput(skill: Vec2(-1, 0))])
        advance(m, 0.2, [.home: PlayerInput()])
        XCTAssertLessThan(m.ball.position.x - m.players[c].pos.x, before - 0.8)
    }
}

final class AerialTests: XCTestCase {
    func setup(humans: Set<TeamSide> = [.home]) -> MatchSimulation {
        let m = MatchSimulation(config: makeConfig(humans: humans, seed: 3)); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
        return m
    }

    func testAutomaticHeaderOnHeadHeightBall() {
        let m = setup(humans: [])
        m.place(player: 9, at: Vec2(40, 0), heading: 0)
        m.placeBall(Vec3(38, 1.7, 0), velocity: Vec3(7, -0.5, 0))
        var kinds: [KickKind] = []
        for _ in 0..<120 { m.step(); for e in m.drainEvents() { if case .kick(9, let k, _) = e { kinds.append(k) } } }
        XCTAssertEqual(kinds.first, .header)
        XCTAssertGreaterThan(m.players[9].headAnim + 1, 0)
    }

    func testHeaderNearGoalIsAShotAndCounts() {
        let m = setup(humans: [])
        m.place(player: 9, at: Vec2(48, 1), heading: 0)
        m.placeBall(Vec3(47.2, 1.6, 1), velocity: Vec3(6, -0.3, 0))
        var vAtContact: Vec3?
        for _ in 0..<60 { m.step(); if vAtContact == nil, m.drainEvents().contains(where: { if case .kick(9, .header, _) = $0 { return true }; return false }) { vAtContact = m.ball.velocity } }
        XCTAssertGreaterThanOrEqual(m.stats[0].shots, 1)
        XCTAssertGreaterThan(try! XCTUnwrap(vAtContact).x, 3, "headed towards goal at the moment of contact")
    }

    func testHumanHeaderUsesPressAndDirection() {
        let m = setup()
        let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(20, 0), heading: 0); m.placeBall(Vec3(20.3, 1.5, 0), velocity: Vec3(0, -0.2, 0.1))
        var kind: KickKind?
        for t in 0..<30 {
            m.step([.home: PlayerInput(move: Vec2(0, 1), shootHeld: t < 3)])
            for e in m.drainEvents() { if case .kick(c, let k, _) = e { kind = k } }
        }
        XCTAssertEqual(kind, .header)
        XCTAssertGreaterThan(m.ball.velocity.z + 0.01, 0, "headed in the stick direction")
    }

    func testVolleyIsStruckOnTheFullAndFlagged() {
        let m = setup()
        let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(30, 0), heading: 0); m.placeBall(Vec3(30.8, 0.6, 0), velocity: Vec3(-8, 0.5, 0))
        var kind: KickKind?
        for t in 0..<20 { m.step([.home: PlayerInput(shootHeld: t < 4)]); for e in m.drainEvents() { if case .kick(c, let k, _) = e { kind = k } } }
        XCTAssertEqual(kind, .volley)
        XCTAssertGreaterThanOrEqual(m.stats[0].shots, 1)
    }

    func testGoalkeeperDoesNotHeadTheBall() {
        let m = setup(humans: [])
        m.place(player: 11, at: Vec2(50, 0)); m.placeBall(Vec3(50.2, 1.7, 0), velocity: Vec3(-2, -0.2, 0))
        for _ in 0..<30 { m.step() }
        for e in m.drainEvents() { if case .kick(11, .header, _) = e { XCTFail("keepers use their hands") } }
    }
}

final class AdvantageTests: XCTestCase {
    func foulSetup() -> MatchSimulation {
        let m = MatchSimulation(config: makeConfig(seed: 5)); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -30 : 30, Float(p.slot) * 5 - 25)) }
        m.place(player: 16, at: Vec2(0, 0), heading: .pi); m.place(player: 4, at: Vec2(-0.6, 0))        // away carrier 16, home defender 4
        m.placeBall(Vec3(-0.4, 0.11, 0)); m.ballOwner = 16; m.lastTouch = 16
        return m
    }

    func testAdvantagePlayedWhenFouledSideKeepsTheBall() {
        let m = foulSetup()
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        m.place(player: 4, at: Vec2(-30, 20))                   // the fouler is no longer in the picture: the carrier keeps the ball
        XCTAssertEqual(m.phase, .playing, "play continues")
        XCTAssertTrue(m.advantagePending)
        XCTAssertTrue(m.drainEvents().contains(.advantage(.away)))
        XCTAssertEqual(m.stats[0].fouls, 1)
        for _ in 0..<(120 * 3) { m.step() ; if case .restart(let r) = m.phase, r.kind == .freeKick { XCTFail("foul must not be recalled while they keep the ball") ; break } }
        XCTAssertFalse(m.advantagePending, "the window expires")
    }

    func testFoulIsCalledBackIfTheFouledSideLosesTheBall() {
        let m = foulSetup()
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        m.ballOwner = 5; m.lastTouch = 5                       // a home player wins it
        m.step()
        guard case .restart(let info) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(info.kind, .freeKick); XCTAssertEqual(info.team, .away)
        XCTAssertEqual(info.spot.x, 0, accuracy: 0.8)
    }

    func testNoAdvantageInsideTheAreaOrAfterRedCard() {
        let m = foulSetup()
        m.place(player: 16, at: Vec2(-45, 3)); m.place(player: 4, at: Vec2(-45.5, 3)); m.placeBall(Vec3(-45.2, 0.11, 3)); m.ballOwner = 16
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        guard case .restart(let r) = m.phase else { return XCTFail("\(m.phase)") }
        XCTAssertEqual(r.kind, .penalty)
        XCTAssertFalse(m.advantagePending)
    }

    func testLooseBallFoulStillStopsPlay() {
        let m = foulSetup(); m.ballOwner = nil
        m.callFoul(by: 4, on: 16, severity: 0.5, fromBehind: false)
        if case .restart = m.phase {} else { XCTFail("no advantage without possession") }
    }
}

final class ExtraTimeShootoutTests: XCTestCase {
    func knockout(_ seed: UInt64 = 1, length: Float = 120) -> MatchSimulation {
        var c = makeConfig(seed: seed, length: length); c.knockout = true
        return MatchSimulation(config: c)
    }

    func testLevelKnockoutGoesToExtraTimeThenWouldNotEndAt90() {
        let m = knockout(); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -30 : 30, Float(p.slot) * 5 - 25)) }
        m.placeBall(Vec3(0, 0.11, 30), velocity: .zero)
        m.clock.startSecondHalf(); m.clock.tick((5400 - 2700 - 3) / m.clock.timeScale)
        var sawBreak = false, sawET = false
        for _ in 0..<(120 * 60) { m.step(); for e in m.drainEvents() { if e == .halfTime { sawBreak = true }; if e == .extraTimeStart { sawET = true } }; if m.clock.half == 3 { break } }
        XCTAssertTrue(sawBreak); XCTAssertTrue(sawET); XCTAssertEqual(m.clock.half, 3)
        XCTAssertNotEqual(m.phase, .fullTime)
        XCTAssertGreaterThanOrEqual(m.clock.gameSeconds, 5400)
    }

    func testNonKnockoutLevelEndsAtFullTime() {
        let m = MatchSimulation(config: makeConfig(seed: 1, length: 60)); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -30 : 30, Float(p.slot) * 5 - 25)) }
        m.clock.startSecondHalf(); m.clock.tick((5400 - 2700 - 3) / m.clock.timeScale)
        for _ in 0..<(120 * 40) { m.step(); if m.phase == .fullTime { break } }
        XCTAssertEqual(m.phase, .fullTime); XCTAssertEqual(m.clock.half, 2)
    }

    func testShootoutProducesAWinnerWithConsistentScores() {
        for seed in 1...4 {
            let m = knockout(UInt64(seed)); playing(m)
            m.startShootout()
            var kicks = 0, n = 0
            while m.phase != .fullTime && n < 120 * 600 {
                m.step(); n += 1
                for e in m.drainEvents() { if case .shootoutKick = e { kicks += 1 } }
            }
            XCTAssertEqual(m.phase, .fullTime, "seed \(seed): shootout must finish")
            let w = try! XCTUnwrap(m.shootoutWinner)
            let so = m.shootout
            XCTAssertGreaterThan(so.scored[w.rawValue], so.scored[w.opponent.rawValue])
            XCTAssertEqual(kicks, so.taken[0] + so.taken[1])
            XCTAssertGreaterThanOrEqual(kicks, 6, "cannot be decided before 3+3 kicks")
            XCTAssertLessThanOrEqual(abs(so.taken[0] - so.taken[1]), 1)
            XCTAssertEqual(m.score, Score(), "a shootout never changes the match score")
        }
    }

    func testShootoutAlternatesTeamsAndUsesDifferentKickers() {
        let m = knockout(7); playing(m); m.startShootout()
        var teams: [TeamSide] = [], takers: [Int] = []
        var lastTaker = -1, n = 0
        while m.phase != .fullTime && n < 120 * 600 {
            m.step(); n += 1
            if case .restart(let r) = m.phase, r.kind == .penalty, r.taker != lastTaker || teams.isEmpty || lastTaker == -1 { if r.taker != lastTaker { teams.append(r.team); takers.append(r.taker); lastTaker = r.taker } }
            _ = m.drainEvents()
        }
        XCTAssertEqual(teams.first, .home)
        for (a, b) in zip(teams, teams.dropFirst()) { XCTAssertNotEqual(a, b) }
        XCTAssertGreaterThan(Set(takers).count, 3, "kickers rotate")
    }

    func testEveryKnockoutMatchIsDecided() throws {
        try skipInDebug()
        for seed in 1...8 {
            var c = makeConfig(seed: UInt64(seed), length: 40); c.knockout = true
            let m = MatchSimulation(config: c)
            var n = 0
            while m.phase != .fullTime && n < 120 * 900 { m.step(); n += 1; _ = m.drainEvents() }
            XCTAssertEqual(m.phase, .fullTime, "seed \(seed)")
            XCTAssertTrue(m.score.home != m.score.away || m.shootoutWinner != nil, "a knockout match must have a winner (seed \(seed))")
        }
    }
}

final class KeeperDismissalTests: XCTestCase {
    func testSentOffGoalkeeperIsReplacedByBenchKeeperAtTheCostOfAForward() {
        var done = false
        for seed in 1...200 where !done {
            let m = MatchSimulation(config: makeConfig(seed: UInt64(seed))); playing(m)
            for p in m.players where p.id != 0 && p.id != 16 { m.place(player: p.id, at: Vec2(p.team == .home ? -30 : 30, Float(p.slot) * 5 - 25)) }
            m.place(player: 0, at: Vec2(-50, 0)); m.place(player: 16, at: Vec2(-48, 3))
            m.placeBall(Vec3(-48.5, 0.11, 3)); m.ballOwner = 16
            m.callFoul(by: 0, on: 16, severity: 1, fromBehind: true)
            guard m.players[0].sentOff else { continue }
            done = true
            let home = m.players.filter { $0.team == .home && $0.onPitch }
            XCTAssertEqual(home.count, 10)
            XCTAssertEqual(home.filter { $0.role == .gk }.count, 1, "exactly one keeper on the pitch")
            let benchKeeper = m.teamSetup(.home).players.dropFirst(11).first { $0.role == .gk }!
            XCTAssertEqual(home.first { $0.role == .gk }!.name, benchKeeper.name)
            XCTAssertFalse(home.contains { $0.role.line == .forward && $0.slot == home.first { $0.role == .gk }!.slot && $0.role != .gk })
            for _ in 0..<(120 * 5) { m.step() }
            XCTAssertTrue(m.players.filter { $0.team == .home && $0.role == .gk && $0.onPitch }.count == 1)
        }
        XCTAssertTrue(done, "a keeper red card must be reachable")
    }
}
