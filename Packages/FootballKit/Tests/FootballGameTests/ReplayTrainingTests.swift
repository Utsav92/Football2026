import XCTest
import simd
@testable import FootballGame
import FootballPhysics

final class ReplayTests: XCTestCase {
    func testRecorderKeepsRingBufferAtThirtyHertz() {
        let m = MatchSimulation(config: makeConfig(seed: 3)); playing(m)
        var r = ReplayRecorder(seconds: 4, hz: 30)
        for _ in 0..<(120 * 10) { m.step(); r.record(m) }
        XCTAssertEqual(r.frames.count, 120, "4 s * 30 Hz")
        let dt = r.frames[1].t - r.frames[0].t
        XCTAssertEqual(dt, 1.0 / 30, accuracy: 1e-3)
        XCTAssertEqual(r.clip(lastSeconds: 1).count, 31, accuracy: 1)
        XCTAssertEqual(r.frames[0].players.count, 22)
    }

    func testPlaybackInterpolatesAndFinishes() {
        let m = MatchSimulation(config: makeConfig(seed: 4)); playing(m)
        for p in m.players { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
        m.placeBall(Vec3(0, 0.11, 0), velocity: Vec3(10, 0, 0))
        var r = ReplayRecorder(seconds: 3, hz: 30)
        for _ in 0..<240 { m.step(); r.record(m) }
        var p = ReplayPlayer(frames: r.clip(lastSeconds: 2), speed: 0.5)
        let a = p.sample()!
        p.advance(1.0)                                  // 0.5 s of match time at half speed
        let b = p.sample()!
        XCTAssertGreaterThan(b.ballPosition.x, a.ballPosition.x + 1)
        XCTAssertEqual(b.t - a.t, 0.5, accuracy: 0.02)
        // interpolation between two stored frames lies between them
        var q = ReplayPlayer(frames: r.clip(lastSeconds: 2), speed: 1)
        q.advance(0.0166)
        let mid = q.sample()!
        XCTAssertGreaterThanOrEqual(mid.ballPosition.x, r.clip(lastSeconds: 2)[0].ballPosition.x)
        while !p.isFinished { p.advance(0.5) }
        XCTAssertTrue(p.isFinished)
    }

    func testApplyFrameDrivesAViewerSimulationWithoutTouchingLiveMatch() {
        let live = MatchSimulation(config: makeConfig(seed: 5)); playing(live)
        for _ in 0..<600 { live.step() }
        var r = ReplayRecorder(seconds: 2, hz: 30); for _ in 0..<240 { live.step(); r.record(live) }
        let viewer = MatchSimulation(config: makeConfig(seed: 5))
        let frame = r.frames[10]
        viewer.apply(frame)
        XCTAssertEqual(viewer.players[7].pos, frame.players[7].pos)
        XCTAssertEqual(viewer.ball.position, frame.ballPosition)
        XCTAssertNotEqual(live.ball.position, frame.ballPosition, "live match keeps running independently")
    }
}

final class TrainingTests: XCTestCase {
    func session(_ k: TrainingKind) -> TrainingSession {
        let c = makeConfig(seed: 1)
        return TrainingSession(kind: k, home: c.home, away: c.away, seed: 4)
    }
    func run(_ s: TrainingSession, _ sec: Float, _ input: PlayerInput = PlayerInput()) { for _ in 0..<Int(sec * 120) { s.step(input) } }

    func testFreePracticeRemovesOppositionOutfield() {
        let s = session(.freePractice)
        XCTAssertEqual(s.sim.players.filter { $0.team == .away && $0.onPitch }.count, 1, "only the keeper remains")
        XCTAssertEqual(s.sim.players.filter { $0.team == .home && $0.onPitch }.count, 11)
        run(s, 5)
        XCTAssertEqual(s.sim.phase, .playing)
    }

    func testShootingDrillResetsAfterEachAttempt() {
        let s = session(.shooting)
        XCTAssertEqual(s.sim.players.filter { $0.onPitch }.count, 3, "human, own keeper, opposing keeper")
        let human = s.sim.controlled(.home)!
        var shots = 0
        for _ in 0..<(120 * 40) {
            // the human holds shoot whenever the ball is at their feet
            s.step(PlayerInput(shootHeld: (Int(s.sim.ball.position.x * 10) % 2 == 0)))
            if s.attempts > shots { shots = s.attempts }
            if shots >= 3 { break }
        }
        XCTAssertGreaterThanOrEqual(s.attempts, 1, "attempt counter advances")
        XCTAssertLessThan(simd_distance(s.sim.players[human].pos, Vec2(s.sim.ball.position.x, s.sim.ball.position.z)), 12, "ball is reset near the player")
        XCTAssertLessThanOrEqual(s.goals, s.attempts)
    }

    func testPenaltyDrillRepeatsPenalties() {
        let s = session(.penalties)
        guard case .restart(let info) = s.sim.phase else { return XCTFail() }
        XCTAssertEqual(info.kind, .penalty)
        // take the penalty (human charges and releases shoot), then expect the drill to re-arm itself
        for _ in 0..<(120 * 3) { s.step(PlayerInput(shootHeld: true)) }
        for _ in 0..<(120 * 12) { s.step(PlayerInput()) ; if s.attempts >= 1 { break } }
        XCTAssertGreaterThanOrEqual(s.attempts, 1)
        run(s, 3)
        if case .restart(let again) = s.sim.phase { XCTAssertEqual(again.kind, .penalty) } else { XCTAssertEqual(s.sim.phase, .playing) }
    }

    func testFreeKickDrillStartsDirectFreeKickWithWall() {
        let s = session(.freeKicks)
        guard case .restart(let info) = s.sim.phase else { return XCTFail() }
        XCTAssertEqual(info.kind, .freeKick); XCTAssertEqual(info.team, .home)
        XCTAssertGreaterThan(s.sim.players.filter { $0.team == .away && $0.onPitch }.count, 5, "defenders stay on to form the wall")
        XCTAssertLessThan(abs(info.spot.x - 52.5), 29)
    }

    func testPassingDrillCountsCompletedPasses() {
        let s = session(.passing)
        XCTAssertEqual(s.sim.players.filter { $0.team == .away && $0.onPitch }.count, 0)
        // pass to the nearest teammate repeatedly
        var tick = 0
        for _ in 0..<(120 * 30) {
            tick += 1
            let hold = (tick / 40) % 3 == 0
            let t = s.sim.players.filter { $0.team == .home && $0.onPitch && $0.id != s.sim.controlled(.home)! }.first!
            let me = s.sim.players[s.sim.controlled(.home)!]
            let dir = t.pos - me.pos
            s.step(PlayerInput(move: simd_length(dir) > 0.1 ? dir / simd_length(dir) * 0.3 : .zero, passHeld: hold))
        }
        XCTAssertGreaterThanOrEqual(s.passesCompleted, 1)
    }
}

final class InputBufferingTests: XCTestCase {
    func testEarlyKickPressFiresWhenBallArrives() {
        let m = MatchSimulation(config: makeConfig(humans: [.home], seed: 6)); playing(m)
        let c = m.controlled(.home)!
        for p in m.players where p.id != c { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
        m.place(player: c, at: Vec2(0, 0), heading: 0)
        // ball rolling towards the player, 2 m away when the shot button is released: it arrives inside the 0.18 s buffer window
        m.placeBall(Vec3(2.2, 0.11, 0), velocity: Vec3(-3, 0, 0))
        for _ in 0..<6 { m.step([.home: PlayerInput(shootHeld: true)]) }
        m.step([.home: PlayerInput()])                        // release: ball not yet in range
        _ = m.drainEvents()
        var fired = false
        for _ in 0..<(120 * 1) { m.step([.home: PlayerInput()]); if m.drainEvents().contains(where: { if case .kick(_, .shot, _) = $0 { return true }; return false }) { fired = true; break } }
        XCTAssertTrue(fired, "a shot pressed slightly early is buffered and fires when the ball arrives")
    }

    func testBufferedKickExpires() {
        let m = MatchSimulation(config: makeConfig(humans: [.home], seed: 6)); playing(m)
        let c = m.controlled(.home)!
        for p in m.players where p.id != c { m.place(player: p.id, at: Vec2(p.team == .home ? -40 : 40, Float(p.slot) * 5 - 25)) }
        m.place(player: c, at: Vec2(0, 0), heading: 0); m.placeBall(Vec3(30, 0.11, 0))
        for _ in 0..<6 { m.step([.home: PlayerInput(shootHeld: true)]) }
        m.step([.home: PlayerInput()])
        for _ in 0..<60 { m.step([.home: PlayerInput()]) }       // wait far longer than the buffer window
        m.placeBall(Vec3(0.9, 0.11, 0))
        _ = m.drainEvents()
        for _ in 0..<30 { m.step([.home: PlayerInput()]) }
        XCTAssertFalse(m.drainEvents().contains { if case .kick = $0 { return true }; return false }, "an old press must not fire late")
    }
}

final class MirrorPresentationTests: XCTestCase {
    func testMirrorRotatesWorldHalfTurnAndKeepsControlAndOwner() {
        let live = MatchSimulation(config: makeConfig(humans: [.home], seed: 2)); playing(live)
        for _ in 0..<600 { live.step() }
        let viewer = MatchSimulation(config: makeConfig(humans: [.home], seed: 2))
        viewer.mirrorPresentation(from: live, mirrored: true)
        for i in 0..<22 {
            XCTAssertEqual(viewer.players[i].pos, -live.players[i].pos)
            var d = viewer.players[i].heading - live.players[i].heading - .pi
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            XCTAssertEqual(d, 0, accuracy: 1e-4)
        }
        XCTAssertEqual(viewer.ball.position.x, -live.ball.position.x, accuracy: 1e-5)
        XCTAssertEqual(viewer.ball.position.z, -live.ball.position.z, accuracy: 1e-5)
        XCTAssertEqual(viewer.ball.position.y, live.ball.position.y)
        XCTAssertEqual(viewer.controlled(.home), live.controlled(.home))
        XCTAssertEqual(viewer.ballOwner, live.ballOwner)
        viewer.mirrorPresentation(from: live, mirrored: false)
        XCTAssertEqual(viewer.players[5].pos, live.players[5].pos)
    }

    func testMirroredReplayFrameApply() {
        let m = MatchSimulation(config: makeConfig(seed: 3)); playing(m)
        var r = ReplayRecorder(seconds: 2, hz: 30); for _ in 0..<120 { m.step(); r.record(m) }
        let v = MatchSimulation(config: makeConfig(seed: 3))
        v.apply(r.frames[5], mirrored: true)
        XCTAssertEqual(v.players[3].pos, -r.frames[5].players[3].pos)
    }
}
