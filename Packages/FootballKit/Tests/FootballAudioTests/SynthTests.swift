import XCTest
@testable import FootballAudio

final class SynthTests: XCTestCase {
    func rms(_ x: [Float]) -> Float { (x.map { $0 * $0 }.reduce(0, +) / Float(x.count)).squareRoot() }
    func assertSound(_ x: [Float], seconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(x.count) / Synth.sampleRate, seconds, accuracy: 0.05, file: file, line: line)
        XCTAssertTrue(x.allSatisfy { $0.isFinite && abs($0) <= 1.0 }, "finite and unclipped", file: file, line: line)
        XCTAssertGreaterThan(rms(x), 0.01, "not silent", file: file, line: line)
    }

    func testAllSoundsAreFiniteUnclippedAndAudible() {
        assertSound(Synth.crowdLoop(seconds: 3), seconds: 3 - 0.4)
        assertSound(Synth.kick(power: 0.9), seconds: 0.22)
        assertSound(Synth.bounce(speed: 6), seconds: 0.16)
        assertSound(Synth.whistle(), seconds: 0.6)
        assertSound(Synth.whistle(blasts: 3), seconds: 3 * 0.6 + 2 * 0.12)
        assertSound(Synth.cheer(), seconds: 3.2)
        assertSound(Synth.netRustle(), seconds: 0.5)
        assertSound(Synth.musicLoop(bars: 4), seconds: 4 * 4 * 0.6)
        assertSound(Synth.footstep(), seconds: 0.09)
    }

    func testKickPowerScalesLoudness() { XCTAssertGreaterThan(rms(Synth.kick(power: 1)), rms(Synth.kick(power: 0.1)) * 1.5) }

    func testDeterministic() { XCTAssertEqual(Synth.crowdLoop(seconds: 2, seed: 4), Synth.crowdLoop(seconds: 2, seed: 4)); XCTAssertNotEqual(Synth.crowdLoop(seconds: 2, seed: 4), Synth.crowdLoop(seconds: 2, seed: 5)) }

    func testCrowdLoopIsSeamless() {
        let l = Synth.crowdLoop(seconds: 3)
        let jump = abs(l.last! - l.first!)
        let typical = (1..<2000).map { abs(l[$0] - l[$0 - 1]) }.reduce(0, +) / 1999
        XCTAssertLessThan(jump, typical * 12, "loop point has no click")
    }

    func testWhistleHasEnergyNearThreeKilohertz() {
        let w = Synth.whistle(seconds: 0.4)
        func power(at f: Double) -> Float {
            var re: Float = 0, im: Float = 0
            for (i, v) in w.enumerated() { let a = 2 * Double.pi * f * Double(i) / Synth.sampleRate; re += v * Float(cos(a)); im += v * Float(sin(a)) }
            return re * re + im * im
        }
        XCTAssertGreaterThan(power(at: 2900), power(at: 600) * 50)
    }
}
