import XCTest
import simd
@testable import FootballGame
import FootballPhysics

final class LawsTests: XCTestCase {
    func testOffsideBasics() {
        // Home attacks +X. Opponents (incl. GK) at x = 50 (GK) and 30 (last defender).
        XCTAssertTrue(Laws.isOffside(receiverX: 40, ballX: 20, opponentXs: [50, 30, 10], attackSign: 1))
        XCTAssertFalse(Laws.isOffside(receiverX: 25, ballX: 20, opponentXs: [50, 30, 10], attackSign: 1), "behind last defender")
        XCTAssertFalse(Laws.isOffside(receiverX: 40, ballX: 45, opponentXs: [50, 30, 10], attackSign: 1), "behind the ball")
        XCTAssertFalse(Laws.isOffside(receiverX: -5, ballX: -20, opponentXs: [-3, -10, -30], attackSign: 1), "own half")
        XCTAssertFalse(Laws.isOffside(receiverX: 30, ballX: 10, opponentXs: [50, 30, 10], attackSign: 1) && false)
    }
    func testOffsideLevelWithSecondLastIsOnside() {
        XCTAssertFalse(Laws.isOffside(receiverX: 30, ballX: 10, opponentXs: [50, 30, 10], attackSign: 1))
    }
    func testOffsideAwayTeamMirrors() {
        XCTAssertTrue(Laws.isOffside(receiverX: -40, ballX: -20, opponentXs: [-50, -30, -10], attackSign: -1))
        XCTAssertFalse(Laws.isOffside(receiverX: -25, ballX: -20, opponentXs: [-50, -30, -10], attackSign: -1))
    }
    func testPenaltyArea() {
        XCTAssertTrue(Laws.inPenaltyArea(Vec2(-45, 5), defending: .home))
        XCTAssertFalse(Laws.inPenaltyArea(Vec2(-30, 0), defending: .home))
        XCTAssertFalse(Laws.inPenaltyArea(Vec2(-45, 25), defending: .home), "outside width")
        XCTAssertTrue(Laws.inPenaltyArea(Vec2(45, -5), defending: .away))
        XCTAssertFalse(Laws.inPenaltyArea(Vec2(45, -5), defending: .home))
        XCTAssertEqual(Laws.penaltySpot(defending: .away), Vec2(41.5, 0))
    }
    func testThrowIn() {
        let r = Laws.restartAfterBallOut(exit: Vec3(10, 0.1, 34.5), lastTouch: .home)
        XCTAssertEqual(r.kind, .throwIn); XCTAssertEqual(r.team, .away); XCTAssertEqual(r.spot.y, 34)
    }
    func testGoalKickAndCorner() {
        // Home attacker puts it behind the +X goal line (away defends): goal kick for away.
        var r = Laws.restartAfterBallOut(exit: Vec3(53, 0.1, 15), lastTouch: .home)
        XCTAssertEqual(r.kind, .goalKick); XCTAssertEqual(r.team, .away)
        // Away defender last touch behind own goal line: corner to home.
        r = Laws.restartAfterBallOut(exit: Vec3(53, 0.1, -15), lastTouch: .away)
        XCTAssertEqual(r.kind, .corner); XCTAssertEqual(r.team, .home); XCTAssertEqual(r.spot, Vec2(52.5, -34))
        r = Laws.restartAfterBallOut(exit: Vec3(-53, 0.1, 3), lastTouch: .away)
        XCTAssertEqual(r.kind, .goalKick); XCTAssertEqual(r.team, .home)
    }
}
