import Foundation

/// Procedural audio (original, no samples). Pure functions returning mono Float buffers in [-1, 1].
public enum Synth {
    public static let sampleRate: Double = 44_100

    struct Rng { var s: UInt64; mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 33) & 0xFFFFFF) / Float(0x800000) - 1 } }

    static func n(_ seconds: Double) -> Int { Int(seconds * sampleRate) }
    static func env(_ t: Double, attack: Double, decay: Double) -> Float { Float(min(1, t / attack) * exp(-t / decay)) }
    static func lowpass(_ x: [Float], cutoff: Double) -> [Float] {
        let a = Float(1 - exp(-2 * .pi * cutoff / sampleRate)); var y: Float = 0
        return x.map { y += a * ($0 - y); return y }
    }
    static func highpass(_ x: [Float], cutoff: Double) -> [Float] { zip(x, lowpass(x, cutoff: cutoff)).map { $0 - $1 } }
    static func normalise(_ x: [Float], peak: Float) -> [Float] {
        let m = x.map { abs($0) }.max() ?? 0
        return m > 0 ? x.map { $0 / m * peak } : x
    }

    /// Seamless looping crowd ambience: band-limited noise with slow amplitude swells (cross-faded loop point).
    public static func crowdLoop(seconds: Double = 6, seed: UInt64 = 1) -> [Float] {
        var r = Rng(s: seed)
        let count = n(seconds)
        let raw = (0..<count).map { _ in r.next() }
        let band = highpass(lowpass(raw, cutoff: 1800), cutoff: 180)
        var out = band.enumerated().map { i, v -> Float in
            let t = Double(i) / sampleRate
            let swell = 0.75 + 0.25 * Float(sin(2 * .pi * t / seconds * 2 + 0.7)) + 0.1 * Float(sin(2 * .pi * t * 0.9))
            return v * swell
        }
        let fade = n(0.4)                                   // equal-power cross-fade of the tail into the head for a click-free loop
        for i in 0..<fade {
            let u = Float(i) / Float(fade)
            out[i] = out[i] * sqrt(u) + out[count - fade + i] * sqrt(1 - u)
        }
        return normalise(Array(out.prefix(count - fade)), peak: 0.6)
    }

    /// Ball struck: low thump + short noise click. `power` 0...1.
    public static func kick(power: Float = 0.7) -> [Float] {
        var r = Rng(s: 7)
        let c = n(0.22)
        let f0 = 90 + 60 * Double(power)
        let raw: [Float] = (0..<c).map { i in
            let t = Double(i) / sampleRate
            let thump = Float(sin(2 * .pi * (f0 - 40 * t) * t)) * env(t, attack: 0.002, decay: 0.05)
            let click = r.next() * env(t, attack: 0.0005, decay: 0.012)
            return thump * 0.9 + click * 0.45
        }
        return normalise(raw, peak: 0.35 + 0.55 * power)
    }

    public static func bounce(speed: Float) -> [Float] {
        let c = n(0.16)
        let raw: [Float] = (0..<c).map { i in let t = Double(i) / sampleRate; return Float(sin(2 * .pi * 150 * t)) * env(t, attack: 0.001, decay: 0.035) }
        return normalise(raw, peak: min(0.7, 0.1 + speed * 0.05))
    }

    /// Referee whistle: ~3 kHz tone with trill (pea) amplitude modulation. `blasts` > 1 for the full-time triple.
    public static func whistle(seconds: Double = 0.6, blasts: Int = 1) -> [Float] {
        let gap = 0.12
        let total = Double(blasts) * seconds + Double(blasts - 1) * gap
        var out = [Float](repeating: 0, count: n(total))
        for b in 0..<blasts {
            let start = n(Double(b) * (seconds + gap))
            for i in 0..<n(seconds) {
                let t = Double(i) / sampleRate
                let vib = 1 + 0.012 * sin(2 * .pi * 6 * t)
                let tone = sin(2 * .pi * 2900 * vib * t) + 0.35 * sin(2 * .pi * 5800 * vib * t)
                let trill = 0.65 + 0.35 * sin(2 * .pi * 38 * t)
                let e = Float(min(1, t / 0.02) * min(1, (seconds - t) / 0.04))
                out[start + i] = Float(tone) * Float(trill) * e
            }
        }
        return normalise(out, peak: 0.5)
    }

    /// Goal roar: noise swell with a rising band.
    public static func cheer(seconds: Double = 3.2) -> [Float] {
        var r = Rng(s: 99)
        let c = n(seconds)
        let raw = (0..<c).map { _ in r.next() }
        let b = highpass(lowpass(raw, cutoff: 2600), cutoff: 250)
        let out = b.enumerated().map { i, v -> Float in
            let t = Double(i) / sampleRate
            let e = Float(min(1, t / 0.35) * min(1, (seconds - t) / 0.9))
            return v * e * (0.8 + 0.2 * Float(sin(2 * .pi * t * 5)))
        }
        return normalise(out, peak: 0.8)
    }

    public static func netRustle() -> [Float] {
        var r = Rng(s: 5)
        let c = n(0.5)
        let b = highpass((0..<c).map { _ in r.next() }, cutoff: 2500)
        return normalise(b.enumerated().map { i, v in v * env(Double(i) / sampleRate, attack: 0.01, decay: 0.12) }, peak: 0.3)
    }

    /// Menu/match music: calm original arpeggio over a 4-chord loop (Am - F - C - G), `bpm` 100.
    public static func musicLoop(bars: Int = 8, bpm: Double = 100) -> [Float] {
        let beat = 60 / bpm, total = Double(bars) * 4 * beat
        var out = [Float](repeating: 0, count: n(total))
        let chords: [[Double]] = [[220, 261.63, 329.63], [174.61, 220, 261.63], [261.63, 329.63, 392], [196, 246.94, 293.66]]
        for bar in 0..<bars {
            let chord = chords[bar % chords.count]
            for step in 0..<8 {
                let f = chord[step % 3] * (step >= 4 ? 2 : 1)
                let start = n((Double(bar) * 4 + Double(step) * 0.5) * beat)
                for i in 0..<n(0.9 * beat) where start + i < out.count {
                    let t = Double(i) / sampleRate
                    out[start + i] += Float(sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t)) * env(t, attack: 0.01, decay: 0.35 * beat) * 0.22
                }
            }
            for i in 0..<n(4 * beat) {                       // soft pad
                let t = Double(i) / sampleRate, idx = n(Double(bar) * 4 * beat) + i
                guard idx < out.count else { break }
                out[idx] += Float(sin(2 * .pi * chord[0] / 2 * t)) * 0.08 * Float(min(1, t / 0.5) * min(1, (4 * beat - t) / 0.5))
            }
        }
        return normalise(out, peak: 0.5)
    }

    /// Footstep on grass: short filtered noise burst.
    public static func footstep() -> [Float] {
        var r = Rng(s: 21)
        let c = n(0.09)
        let b = lowpass((0..<c).map { _ in r.next() }, cutoff: 900)
        return normalise(b.enumerated().map { i, v in v * env(Double(i) / sampleRate, attack: 0.004, decay: 0.025) }, peak: 0.25)
    }
}
