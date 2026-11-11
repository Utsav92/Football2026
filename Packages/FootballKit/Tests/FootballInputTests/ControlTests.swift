import XCTest
import simd
@testable import FootballInput
import FootballGame
import FootballPhysics

final class ControlMapperTests: XCTestCase {
    func pad(_ b: PadButton...) -> PadState { var p = PadState(); p.pressed = Set(b); return p }

    func testDeadZoneRemovesDriftAndFullDeflectionIsUnit() {
        let s = ControllerSettings()
        XCTAssertEqual(ControlMapper.shape(Vec2(0.1, 0.05), s), .zero)
        XCTAssertEqual(simd_length(ControlMapper.shape(Vec2(1, 0), s)), 1, accuracy: 1e-4)
        let half = simd_length(ControlMapper.shape(Vec2(0.6, 0), s))
        XCTAssertLessThan(half, 0.6, "response curve gives finer control near the centre")
        XCTAssertGreaterThan(half, 0)
    }

    func testAnalogStrengthIsMonotonicAndPreservesDirection() {
        let s = ControllerSettings()
        var last: Float = 0
        for m in stride(from: Float(0.2), through: 1, by: 0.1) {
            let v = ControlMapper.shape(Vec2(m, m) / Float(2).squareRoot(), s)
            XCTAssertGreaterThanOrEqual(simd_length(v), last); last = simd_length(v)
            XCTAssertEqual(v.x, v.y, accuracy: 1e-4)
        }
    }

    func testAttackLayoutMatchesPlayStationDefaults() {
        let b = ControlBindings.standard
        XCTAssertTrue(ControlMapper.map(pad(.cross), context: .attack, bindings: b).pass)
        XCTAssertTrue(ControlMapper.map(pad(.circle), context: .attack, bindings: b).shoot)
        XCTAssertTrue(ControlMapper.map(pad(.square), context: .attack, bindings: b).lob)
        XCTAssertTrue(ControlMapper.map(pad(.triangle), context: .attack, bindings: b).through)
        XCTAssertTrue(ControlMapper.map(pad(.l1), context: .attack, bindings: b).switchPlayer)
        XCTAssertTrue(ControlMapper.map(pad(.options), context: .attack, bindings: b).pauseToggle)
    }

    func testDefenceLayoutIsContextSensitive() {
        let b = ControlBindings.standard
        let d = ControlMapper.map(pad(.cross), context: .defense, bindings: b)
        XCTAssertTrue(d.tackle); XCTAssertFalse(d.pass)
        XCTAssertTrue(ControlMapper.map(pad(.circle), context: .defense, bindings: b).slide)
        XCTAssertFalse(ControlMapper.map(pad(.circle), context: .defense, bindings: b).shoot)
    }

    func testTriggersActAsSprintAboveThresholdOnly() {
        var p = PadState(); p.r2 = 0.2
        XCTAssertFalse(ControlMapper.map(p, context: .attack, bindings: .standard).sprint)
        p.r2 = 0.8
        XCTAssertTrue(ControlMapper.map(p, context: .attack, bindings: .standard).sprint)
        p.l2 = 0.9
        XCTAssertTrue(ControlMapper.map(p, context: .attack, bindings: .standard).jockey)
    }

    func testRemappingMovesActionAndClearsDuplicates() {
        var b = ControlBindings.standard
        b.remap(.l2, to: .shoot, in: .attack)
        XCTAssertEqual(b.attack[.l2], .shoot)
        XCTAssertNil(b.attack[.circle], "circle no longer shoots: an action has one button per context")
        XCTAssertTrue(ControlMapper.map(pad(.l2), context: .attack, bindings: b).shoot)
        XCTAssertEqual(b.defense[.circle], .slide, "defence layout untouched")
        // bindings survive a save/load round trip
        let d = try! JSONEncoder().encode(b)
        XCTAssertEqual(try! JSONDecoder().decode(ControlBindings.self, from: d), b)
    }

    func testPlayerInputUsesCameraBasis() {
        var c = ControlState(); c.stick = Vec2(1, 0); c.sprint = true; c.pass = true
        let broadcast = c.playerInput(right: Vec2(1, 0), up: Vec2(0, -1))
        XCTAssertEqual(broadcast.move, Vec2(1, 0)); XCTAssertTrue(broadcast.passHeld); XCTAssertTrue(broadcast.sprint)
        c.stick = Vec2(0, 1)
        XCTAssertEqual(c.playerInput(right: Vec2(1, 0), up: Vec2(0, -1)).move, Vec2(0, -1), "stick up = away from a +z broadcast camera")
        XCTAssertEqual(c.playerInput(right: Vec2(0, 1), up: Vec2(1, 0)).move, Vec2(1, 0), "behind-the-player camera: up = +x")
    }

    func testButtonBufferHoldsThenExpires() {
        var b = ButtonBuffer(window: 0.15)
        b.press(.pass)
        XCTAssertTrue(b.isBuffered(.pass))
        b.tick(0.1); XCTAssertTrue(b.isBuffered(.pass))
        b.tick(0.1); XCTAssertFalse(b.isBuffered(.pass))
        b.press(.shoot); XCTAssertTrue(b.consume(.shoot)); XCTAssertFalse(b.consume(.shoot))
    }

    func testTwoControllerAssignmentAndReconnection() {
        var a = PlayerAssignments()
        a.connect(slot: 0, versus: true); a.connect(slot: 1, versus: true)
        XCTAssertEqual(a.teamForSlot[0], .home); XCTAssertEqual(a.teamForSlot[1], .away)
        a.disconnect(slot: 1)
        XCTAssertTrue(a.needsReconnect); XCTAssertFalse(a.connected.contains(1))
        a.connect(slot: 1, versus: true)
        XCTAssertFalse(a.needsReconnect)
        XCTAssertEqual(a.teamForSlot[1], .away, "a reconnecting pad keeps its team")
        var single = PlayerAssignments(); single.connect(slot: 0, versus: false); single.connect(slot: 1, versus: false)
        XCTAssertEqual(single.teamForSlot[1], .home, "co-op/single-player: both on the home side")
    }
}
