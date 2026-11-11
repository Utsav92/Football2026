import XCTest
import simd
@testable import FootballPhysics

final class BallPhysicsTests: XCTestCase {
    let dt: Float = 1.0 / 120.0
    let physics = BallPhysics()

    func run(_ b: inout BallState, seconds: Float, physics p: BallPhysics? = nil) -> [BallEvent] {
        var all: [BallEvent] = []
        for _ in 0..<Int((seconds / dt).rounded()) { all += (p ?? physics).step(&b, dt: dt) }
        return all
    }

    func testFreeFallMatchesAnalyticWithoutDrag() {
        var cfg = BallPhysicsConfig(); cfg.airDragK = 0
        let p = BallPhysics(config: cfg)
        var b = BallState(position: Vec3(0, 10, 0))
        _ = run(&b, seconds: 1.0, physics: p)
        // y = 10 - 0.5 g t^2 = 5.095
        XCTAssertEqual(b.position.y, 10 - 0.5 * 9.81, accuracy: 0.05)
        XCTAssertEqual(b.velocity.y, -9.81, accuracy: 0.05)
    }

    func testBounceLosesEnergyByRestitution() {
        var cfg = BallPhysicsConfig(); cfg.airDragK = 0
        let p = BallPhysics(config: cfg)
        var b = BallState(position: Vec3(0, 2, 0))
        var maxAfter: Float = 0, bounced = false
        for _ in 0..<(120 * 3) {
            let ev = p.step(&b, dt: dt)
            if ev.contains(where: { if case .bounce = $0 { return true }; return false }) { bounced = true }
            if bounced { maxAfter = max(maxAfter, b.position.y) }
        }
        XCTAssertTrue(bounced)
        // Rebound height ~ e^2 * drop height (above ball radius).
        let drop = 2 - PitchSpec.ballRadius
        XCTAssertEqual(maxAfter - PitchSpec.ballRadius, drop * 0.62 * 0.62, accuracy: 0.1)
    }

    func testBallSettlesAndRollsToStop() {
        var b = BallState(position: Vec3(0, 3, 0))
        b.velocity = Vec3(6, 0, 0)
        _ = run(&b, seconds: 20)
        XCTAssertEqual(b.speed, 0, accuracy: 0.001)
        XCTAssertEqual(b.position.y, PitchSpec.ballRadius, accuracy: 0.002)
        XCTAssertGreaterThan(b.position.x, 5)
    }

    func testRollingDecelerationRate() {
        var cfg = BallPhysicsConfig(); cfg.airDragK = 0
        let p = BallPhysics(config: cfg)
        var b = BallState(position: Vec3(0, PitchSpec.ballRadius, 0))
        b.velocity = Vec3(5, 0, 0)
        _ = run(&b, seconds: 1, physics: p)
        XCTAssertEqual(b.velocity.x, 5 - cfg.rollingDecel, accuracy: 0.05)
    }

    func testAirDragSlowsBall() {
        var b = BallState(position: Vec3(0, 50, 0)); b.velocity = Vec3(30, 0, 0)
        var c = b; c.velocity = Vec3(30, 0, 0)
        var cfg = BallPhysicsConfig(); cfg.airDragK = 0
        _ = run(&b, seconds: 0.5)
        _ = run(&c, seconds: 0.5, physics: BallPhysics(config: cfg))
        XCTAssertLessThan(b.velocity.x, c.velocity.x - 1)
    }

    func testMagnusCurvesBall() {
        var cfg = BallPhysicsConfig(); cfg.magnusK = 0.004
        let p = BallPhysics(config: cfg)
        var b = BallState(position: Vec3(0, 30, 0)); b.velocity = Vec3(25, 0, 0)
        b.curveSpin = Vec3(0, 60, 0)  // sidespin
        _ = run(&b, seconds: 0.8, physics: p)
        XCTAssertGreaterThan(abs(b.velocity.z), 0.2)
    }

    func testResultIsDeterministic() {
        func sim() -> BallState {
            var b = BallState(position: Vec3(10, 1, 3)); b.velocity = Vec3(20, 6, -2)
            _ = run(&b, seconds: 5); return b
        }
        let a = sim(), c = sim()
        XCTAssertEqual(a.position, c.position)
        XCTAssertEqual(a.velocity, c.velocity)
    }

    func testStepSizeIndependenceOfFlight() {
        // Same flight with 120 Hz vs 60 Hz steps lands close together (sub-stepping keeps it stable).
        var cfg = BallPhysicsConfig(); cfg.substeps = 8
        let p = BallPhysics(config: cfg)
        var a = BallState(position: Vec3(0, 0.5, 0)); a.velocity = Vec3(15, 8, 0)
        var b = a
        for _ in 0..<120 { p.step(&a, dt: 1.0 / 120) }
        for _ in 0..<60 { p.step(&b, dt: 1.0 / 60) }
        XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.15)
        XCTAssertEqual(a.position.y, b.position.y, accuracy: 0.15)
    }

    func testFastBallDoesNotTunnelThroughNetBackPanel() {
        var b = BallState(position: Vec3(52.5 - 1, 1.0, 0)); b.velocity = Vec3(40, 0, 0)
        _ = run(&b, seconds: 2)
        XCTAssertLessThan(b.position.x, PitchSpec.halfLength + PitchSpec.goalDepth)
        XCTAssertGreaterThan(b.position.x, PitchSpec.halfLength)   // stayed in net
    }

    func testPostBouncesBallBack() {
        // Aim straight at the +z post (x=52.5, z=3.66) from the pitch.
        var b = BallState(position: Vec3(45, 1.0, 3.66)); b.velocity = Vec3(25, 0, 0)
        let ev = run(&b, seconds: 1.0)
        XCTAssertTrue(ev.contains { if case .woodwork = $0 { return true }; return false })
        XCTAssertLessThan(b.velocity.x, 0)
    }

    func testCrossbarHit() {
        var b = BallState(position: Vec3(45, 2.44, 0)); b.velocity = Vec3(25, 1.5, 0)  // arrives at bar height after gravity
        let ev = run(&b, seconds: 0.6)
        XCTAssertTrue(ev.contains { if case .woodwork = $0 { return true }; return false })
    }

    func testPostCollisionDoesNotAddEnergy() {
        var b = BallState(position: Vec3(50, 1.0, 3.7)); b.velocity = Vec3(30, 0, 0)
        let before = b.speed
        var maxSpeed: Float = 0
        for _ in 0..<120 { _ = physics.step(&b, dt: dt); maxSpeed = max(maxSpeed, b.speed) }
        XCTAssertLessThanOrEqual(maxSpeed, before + 0.5)
    }

    func testGoalDetectionInsideMouth() {
        var b = BallState(position: Vec3(PitchSpec.halfLength + 0.5, 1, 0))
        XCTAssertEqual(GoalDetector.side(of: b), 1)
        b.position = Vec3(-PitchSpec.halfLength - 0.5, 1, 1)
        XCTAssertEqual(GoalDetector.side(of: b), -1)
    }

    func testGoalDetectionRejectsOnLineOverBarAndWide() {
        let r = PitchSpec.ballRadius
        XCTAssertEqual(GoalDetector.side(of: BallState(position: Vec3(PitchSpec.halfLength + r * 0.5, 1, 0))), 0, "not fully across")
        XCTAssertEqual(GoalDetector.side(of: BallState(position: Vec3(PitchSpec.halfLength + 1, 3, 0))), 0, "over the bar")
        XCTAssertEqual(GoalDetector.side(of: BallState(position: Vec3(PitchSpec.halfLength + 1, 1, 4))), 0, "wide")
    }

    func testOutOfPlay() {
        XCTAssertTrue(GoalDetector.isOutOfPlay(BallState(position: Vec3(0, 0.1, 34.5))))
        XCTAssertFalse(GoalDetector.isOutOfPlay(BallState(position: Vec3(0, 0.1, 33.9))))
        XCTAssertTrue(GoalDetector.isOutOfPlay(BallState(position: Vec3(53, 0.1, 10))))
        XCTAssertFalse(GoalDetector.isOutOfPlay(BallState(position: Vec3(53, 0.5, 0))), "inside goal is not out of play")
    }

    func testShotIntoGoalScoresAndSettlesInNet() {
        var b = BallState(position: Vec3(40, 0.11, 0)); b.velocity = Vec3(25, 3, 0)
        var scored = false
        for _ in 0..<(120 * 4) {
            physics.step(&b, dt: dt)
            if GoalDetector.side(of: b) == 1 { scored = true }
        }
        XCTAssertTrue(scored)
        XCTAssertLessThan(b.position.x, PitchSpec.halfLength + PitchSpec.goalDepth)
    }
}
