import XCTest
import simd
@testable import FootballGame
import FootballPhysics

final class HumanControlTests: XCTestCase {
    func humanMatch(seed: UInt64 = 1) -> MatchSimulation { let m = MatchSimulation(config: makeConfig(humans: [.home], seed: seed)); playing(m); return m }

    func testControlledPlayerMovesOthersStayAI() {
        let m = humanMatch()
        let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(-20, 0), heading: 0)
        m.placeBall(Vec3(-19.1, 0.11, 0.3))
        let start = m.players[c].pos
        advance(m, 2, [.home: PlayerInput(move: Vec2(1, 0), sprint: true)])
        XCTAssertGreaterThan(m.players[c].pos.x - start.x, 8)
        XCTAssertEqual(m.players[c].state, .controlled)
        XCTAssertTrue(m.players.contains { $0.team == .home && $0.id != c && $0.state != .controlled && $0.state != .idle })
    }

    func testSwitchPicksNearestToBallAndRaisesEvent() {
        let m = humanMatch()
        let c = m.controlled(.home)!
        m.placeBall(Vec3(-20, 0.11, 10))
        advance(m, 0.1)
        _ = m.drainEvents()
        m.step([.home: PlayerInput(switchPressed: true)])
        let n = m.controlled(.home)!
        XCTAssertNotEqual(n, c)
        XCTAssertNotEqual(m.players[n].role, .gk)
        XCTAssertTrue(m.drainEvents().contains(.switched(.home, to: n)))
        let dists = m.players.filter { $0.team == .home && $0.role != .gk && $0.id != c }.map { simd_distance($0.pos, Vec2(-20, 10)) }
        XCTAssertEqual(simd_distance(m.players[n].pos, Vec2(-20, 10)), dists.min()!, accuracy: 6)
    }

    func testPassCompletesAndControlSwitchesToReceiver() {
        let m = humanMatch(seed: 4)
        for p in m.players where p.team == .away { m.place(player: p.id, at: Vec2(30, Float(p.slot) * 5 - 25)) }
        for p in m.players where p.team == .home { m.place(player: p.id, at: Vec2(-30, Float(p.slot) * 5 - 25)) }
        let c = m.controlled(.home)!
        m.place(player: c, at: Vec2(0, 0), heading: 0)
        m.place(player: 8, at: Vec2(14, 0))
        m.placeBall(Vec3(0.9, 0.11, 0.2))
        advance(m, 0.3, [.home: PlayerInput(move: Vec2(1, 0))])
        advance(m, 0.1, [.home: PlayerInput(move: Vec2(1, 0), passHeld: true)])
        advance(m, 0.05, [.home: PlayerInput(move: Vec2(1, 0))])
        var completed = false
        for _ in 0..<(120 * 4) {
            m.step(); if m.drainEvents().contains(where: { if case .passCompleted(_, let to) = $0 { return to == 8 }; return false }) { completed = true; break }
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(m.controlled(.home), 8)
    }

    func testChargedShotFasterThanTap() {
        func shot(hold: Float) -> Float {
            let m = humanMatch()
            let c = m.controlled(.home)!
            m.place(player: c, at: Vec2(30, 0), heading: 0); m.placeBall(Vec3(30.9, 0.11, 0))
            advance(m, hold, [.home: PlayerInput(shootHeld: true)])
            m.step([.home: PlayerInput()])
            return simd_length(m.ball.velocity)
        }
        XCTAssertGreaterThan(shot(hold: 0.9), shot(hold: 0.05) + 8)
    }

    func testHumanTackleWinProbabilityDependsOnAttributes() {
        func winRate(tackling: Int, dribbling: Int) -> Float {
            var wins = 0
            for seed in 1...120 {
                let m = humanMatch(seed: UInt64(seed))
                let c = m.controlled(.home)!
                m.players[c].attributes.tackling = tackling; m.players[c].attributes.defensiveAwareness = tackling; m.players[c].attributes.strength = tackling
                let carrier = 11 + 9
                m.players[carrier].attributes.dribbling = dribbling; m.players[carrier].attributes.balance = dribbling; m.players[carrier].attributes.strength = dribbling
                m.place(player: c, at: Vec2(0, 0), heading: 0); m.place(player: carrier, at: Vec2(1.0, 0), heading: .pi)
                for p in m.players where p.id != c && p.id != carrier { m.place(player: p.id, at: Vec2(p.team == .home ? -30 : 30, Float(p.slot) * 5 - 25)) }
                m.placeBall(Vec3(0.5, 0.11, 0)); m.ballOwner = carrier; m.lastTouch = carrier
                m.step([.home: PlayerInput(tackleHeld: true)])
                if m.ballOwner != carrier { wins += 1 }
            }
            return Float(wins) / 120
        }
        let strong = winRate(tackling: 90, dribbling: 40), weak = winRate(tackling: 40, dribbling: 90)
        XCTAssertGreaterThan(strong, weak + 0.25, "strong \(strong) weak \(weak)")
        XCTAssertGreaterThan(strong, 0.5); XCTAssertLessThan(weak, 0.5)
    }

    func testSprintSpeedAttributeMatters() {
        func dist(_ sprint: Int) -> Float {
            let m = humanMatch(); let c = m.controlled(.home)!
            m.players[c].attributes.sprintSpeed = sprint; m.players[c].attributes.acceleration = 60
            m.place(player: c, at: Vec2(-40, 0), heading: 0); m.placeBall(Vec3(40, 0.11, 25))
            advance(m, 5, [.home: PlayerInput(move: Vec2(1, 0), sprint: true)])
            return m.players[c].pos.x + 40
        }
        XCTAssertGreaterThan(dist(95), dist(40) + 4)
    }

    func testShotPowerAndAccuracyAttributesMatter() {
        func speed(_ power: Int) -> Float {
            let m = humanMatch(); let c = m.controlled(.home)!
            m.players[c].attributes.shotPower = power
            m.place(player: c, at: Vec2(30, 0), heading: 0); m.placeBall(Vec3(30.9, 0.11, 0))
            m.executeShot(c, power: 1, aim: Vec2(1, 0), human: true)
            return simd_length(m.ball.velocity)
        }
        XCTAssertGreaterThan(speed(95), speed(30) + 5)
        func spread(_ acc: Int) -> Float {
            var zs: [Float] = []
            for seed in 1...60 {
                let m = humanMatch(seed: UInt64(seed)); let c = m.controlled(.home)!
                m.players[c].attributes.shootingAccuracy = acc
                m.place(player: c, at: Vec2(25, 0), heading: 0); m.placeBall(Vec3(25.9, 0.11, 0))
                m.executeShot(c, power: 0.8, aim: Vec2(1, 0), human: true)
                zs.append(m.ball.velocity.z / m.ball.velocity.x)
            }
            let mean = zs.reduce(0, +) / Float(zs.count)
            return (zs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(zs.count)).squareRoot()
        }
        XCTAssertLessThan(spread(95), spread(30) * 0.7)
    }
}

final class GoalkeeperTests: XCTestCase {
    func shotMatch(_ seed: UInt64) -> MatchSimulation {
        let m = MatchSimulation(config: makeConfig(seed: seed)); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -20 : 20, Float(p.slot) * 5 - 25)) }
        return m
    }

    func testKeeperSavesMostCentralShotsAndDivesForCornerShots() {
        var saved = 0, dived = 0
        let trials = 30
        for s in 1...trials {
            let m = shotMatch(UInt64(s))
            let gk = 11    // away keeper defends +X
            m.place(player: gk, at: Vec2(50, 0), heading: .pi)
            let z = Float(s % 5) - 2   // -2...2
            m.placeBall(Vec3(32, 0.11, 0), velocity: Vec3(24, 1.5, z * 0.35))
            var d = false
            var scored = false
            for _ in 0..<(120 * 3) {
                m.step()
                if m.players[gk].isDiving { d = true }
                if case .goalCelebration = m.phase { scored = true; break }
            }
            if d { dived += 1 }
            if !scored { saved += 1 }
        }
        XCTAssertGreaterThan(Double(saved) / Double(trials), 0.6, "keeper should stop most on-target shots; saved \(saved)/\(trials)")
        XCTAssertGreaterThan(dived, 3, "keeper should dive on some shots (\(dived))")
    }

    func testKeeperPredictsTrajectoryAndMovesToCrossingPoint() {
        let m = shotMatch(9)
        m.place(player: 11, at: Vec2(50, 0), heading: .pi)
        m.placeBall(Vec3(25, 0.11, 0), velocity: Vec3(20, 0.5, 2.2))
        let before = m.players[11].pos.y
        advance(m, 0.8)
        XCTAssertGreaterThan(m.players[11].pos.y, before + 0.8, "keeper should have moved towards the +z side")
    }

    func testKeeperCatchesSlowBallThenDistributesOutfield() {
        let m = shotMatch(2)
        m.place(player: 11, at: Vec2(50, 0), heading: .pi)
        m.placeBall(Vec3(40, 0.11, 0.5), velocity: Vec3(6, 0, 0))
        var caught = false
        var kicked = false
        for _ in 0..<(120 * 8) {
            m.step()
            for e in m.drainEvents() {
                if e == .save(keeper: 11, caught: true) { caught = true }
                if caught, case .kick(11, _, _) = e { kicked = true }
            }
        }
        XCTAssertTrue(caught, "slow central ball should be caught")
        XCTAssertTrue(kicked, "keeper should distribute after holding")
    }

    func testPenaltyIsTakenAndResolved() {
        var outcomes = Set<String>()
        for s in 1...8 {
            let m = MatchSimulation(config: makeConfig(seed: UInt64(s)))
            playing(m)
            m.setupRestart(.penalty, team: .home, spot: Laws.penaltySpot(defending: .away))
            var kicked = false
            for _ in 0..<(120 * 8) { m.step(); for e in m.drainEvents() { if case .kick(_, .shot, _) = e { kicked = true } } }
            XCTAssertTrue(kicked, "AI must take the penalty")
            outcomes.insert(m.score.home == 1 ? "goal" : "no goal")
        }
        XCTAssertFalse(outcomes.isEmpty)
    }
}

final class AIBehaviourTests: XCTestCase {
    func baseMatch() -> MatchSimulation {
        let m = MatchSimulation(config: makeConfig(seed: 11)); playing(m)
        for p in m.players where p.role != .gk { m.place(player: p.id, at: Vec2(p.team == .home ? -25 : 25, Float(p.slot) * 5 - 25)) }
        m.place(player: 0, at: Vec2(-50, 0)); m.place(player: 11, at: Vec2(50, 0))
        return m
    }

    func testNearestOpponentPressesCarrierAndOthersMark() {
        let m = baseMatch()
        let carrier = 11 + 6
        m.place(player: carrier, at: Vec2(-5, 0), heading: .pi); m.placeBall(Vec3(-5.6, 0.11, 0)); m.ballOwner = carrier; m.lastTouch = carrier
        m.players[carrier].possessionTime = -1000      // keep the carrier holding the ball
        m.place(player: 5, at: Vec2(-12, 2))      // closest home player
        for p in m.players where p.team == .away && p.role != .gk && p.id != carrier { m.place(player: p.id, at: Vec2(-14, Float(p.slot) * 4 - 20)) }
        advance(m, 0.5)
        XCTAssertTrue([.pressing, .tackling].contains(m.players[5].state), "closest defender should press; was \(m.players[5].state)")
        XCTAssertTrue(m.players.contains { $0.team == .home && $0.state == .marking }, "someone should be marking")
    }

    func testLooseBallClosestPlayerIntercepts() {
        let m = baseMatch()
        m.place(player: 6, at: Vec2(-10, 3))
        m.placeBall(Vec3(-3, 0.11, 8), velocity: Vec3(0.5, 0, 0))
        advance(m, 0.5)
        XCTAssertEqual(m.players[6].state, .intercepting)
    }

    func testForwardsMakeRunsWhenTeamHasBall() {
        let m = baseMatch()
        let carrier = 6
        m.place(player: carrier, at: Vec2(0, 0), heading: 0); m.placeBall(Vec3(0.7, 0.11, 0)); m.ballOwner = carrier; m.lastTouch = carrier
        advance(m, 1.2)
        let fw = m.players.filter { $0.team == .home && $0.role.line == .forward && $0.id != carrier }
        XCTAssertTrue(fw.contains { $0.state == .supporting }, "forwards should be making supporting runs")
        for f in fw { XCTAssertLessThanOrEqual(f.target.x, m.teams[0].ctx.offsideLine + 0.9, "runner stays onside") }
    }

    func testCarrierWithOpenGoalShoots() {
        let m = baseMatch()
        let carrier = 9
        m.place(player: carrier, at: Vec2(34, 0), heading: 0); m.placeBall(Vec3(34.7, 0.11, 0)); m.ballOwner = carrier; m.lastTouch = carrier
        for p in m.players where p.team == .away && p.role != .gk { m.place(player: p.id, at: Vec2(10, Float(p.slot) * 5 - 25)) }
        var shot = false
        for _ in 0..<(120 * 4) { m.step(); if m.drainEvents().contains(where: { if case .kick(9, .shot, _) = $0 { return true }; return false }) { shot = true; break } }
        XCTAssertTrue(shot)
    }

    func testBackPassesToSafeTeammateWhenPressedInOwnHalf() {
        var passes = 0
        for seed in 1...6 {
            let m = baseMatch()
            _ = seed
            m.place(player: 3, at: Vec2(-30, 0), heading: 0); m.placeBall(Vec3(-29.3, 0.11, 0)); m.ballOwner = 3; m.lastTouch = 3
            m.place(player: 11 + 9, at: Vec2(-27.5, 0.5)); m.place(player: 6, at: Vec2(-35, 12))
            for _ in 0..<(120 * 3) { m.step(); if m.drainEvents().contains(where: { if case .kick(3, _, _) = $0 { return true }; return false }) { passes += 1; break } }
        }
        XCTAssertGreaterThan(passes, 4, "pressured carrier should release the ball")
    }
}

final class StabilityTests: XCTestCase {
    func testDeterministicBySeed() throws {
        try skipInDebug()
        func run(_ seed: UInt64) -> (Vec2, Vec3, Score) {
            let m = MatchSimulation(config: makeConfig(seed: seed))
            advance(m, 90)
            return (m.players[7].pos, m.ball.position, m.score)
        }
        let a = run(5), b = run(5), c = run(6)
        XCTAssertEqual(a.0, b.0); XCTAssertEqual(a.1, b.1); XCTAssertEqual(a.2, b.2)
        XCTAssertNotEqual(a.1, c.1)
    }

    func testEveryFormationPairingPlaysAFullMatchStably() throws {
        try skipInDebug()
        let fs = Formation.allCases
        for (k, f) in fs.enumerated() {
            let g = fs[(k + 2) % fs.count]
            let m = MatchSimulation(config: makeConfig(seed: UInt64(20 + k), homeForm: f, awayForm: g))
            var n = 0
            while m.phase != .fullTime && n < 120 * 800 {
                m.step(); n += 1; _ = m.drainEvents()
                if n % 120 == 0 { assertSane(m, "\(f.rawValue) v \(g.rawValue) @\(n)") }
            }
            XCTAssertEqual(m.phase, .fullTime, "\(f.rawValue) v \(g.rawValue) must finish")
            XCTAssertLessThanOrEqual(m.score.home + m.score.away, 14)
        }
    }

    func testHumanPlusAIMatchWithRandomInputIsStable() throws {
        try skipInDebug()
        let m = MatchSimulation(config: makeConfig(humans: [.home, .away], seed: 8, length: 100))
        var rng = SplitMix64(seed: 99)
        var input = [TeamSide: PlayerInput]()
        var n = 0
        while m.phase != .fullTime && n < 120 * 900 {
            if n % 30 == 0 {
                for side in TeamSide.allCases {
                    input[side] = PlayerInput(move: Vec2(rng.range(-1, 1), rng.range(-1, 1)), sprint: rng.float() < 0.5,
                                              passHeld: rng.float() < 0.15, throughHeld: rng.float() < 0.05, lobHeld: rng.float() < 0.05,
                                              shootHeld: rng.float() < 0.1, tackleHeld: rng.float() < 0.1, slideHeld: rng.float() < 0.03, switchPressed: rng.float() < 0.1)
                }
            }
            m.step(input); n += 1; _ = m.drainEvents()
            if n % 120 == 0 { assertSane(m, "random input @\(n)") }
        }
        XCTAssertEqual(m.phase, .fullTime)
    }

    func testHarderAIOutperformsEasierAI() throws {
        try skipInDebug()
        var strong = TeamStats(), weak = TeamStats()
        var strongGoals = 0, weakGoals = 0
        for seed in 1...20 {
            for flip in [false, true] {
                var cfg = makeConfig(seed: UInt64(seed))
                cfg.difficultyOverride = flip ? [.home: .beginner, .away: .worldClass] : [.home: .worldClass, .away: .beginner]
                let m = MatchSimulation(config: cfg)
                var n = 0
                while m.phase != .fullTime && n < 120 * 800 { m.step(); n += 1; _ = m.drainEvents() }
                let s = flip ? 1 : 0
                strongGoals += m.score[flip ? .away : .home]; weakGoals += m.score[flip ? .home : .away]
                for (dst, i) in [(0, s), (1, 1 - s)] {
                    let x = m.stats[i]
                    if dst == 0 { strong.shots += x.shots; strong.passes += x.passes; strong.passesCompleted += x.passesCompleted; strong.tacklesWon += x.tacklesWon }
                    else { weak.shots += x.shots; weak.passes += x.passes; weak.passesCompleted += x.passesCompleted; weak.tacklesWon += x.tacklesWon }
                }
            }
        }
        let sc = Float(strong.passesCompleted) / Float(strong.passes), wc = Float(weak.passesCompleted) / Float(weak.passes)
        print("DIFF strong goals \(strongGoals) shots \(strong.shots) passAcc \(sc) tacklesWon \(strong.tacklesWon) | weak goals \(weakGoals) shots \(weak.shots) passAcc \(wc) tacklesWon \(weak.tacklesWon)")
        XCTAssertGreaterThan(strong.tacklesWon, weak.tacklesWon, "world-class AI should win the ball more often")
        XCTAssertGreaterThan(strong.shots, weak.shots)
        XCTAssertGreaterThanOrEqual(strongGoals, weakGoals - 3)
    }

    func assertSane(_ m: MatchSimulation, _ ctx: String) {
        XCTAssertTrue(m.ball.position.x.isFinite && m.ball.position.y.isFinite && m.ball.position.z.isFinite, "ball NaN \(ctx)")
        XCTAssertLessThan(abs(m.ball.position.x), 80, ctx); XCTAssertLessThan(abs(m.ball.position.z), 60, ctx)
        for p in m.players where p.onPitch {
            XCTAssertTrue(p.pos.x.isFinite && p.pos.y.isFinite && p.vel.x.isFinite, "player NaN \(ctx)")
            XCTAssertLessThan(abs(p.pos.x), PitchSpec.halfLength + 4.5, ctx); XCTAssertLessThan(abs(p.pos.y), PitchSpec.halfWidth + 4.5, ctx)
            XCTAssertLessThan(p.speed, 12, "speed \(ctx)")
        }
        XCTAssertGreaterThanOrEqual(m.players.filter { $0.team == .home && $0.onPitch }.count, 8)
    }
}
