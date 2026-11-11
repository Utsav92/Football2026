import Foundation
/// Deterministic SplitMix64 generator: all match randomness flows through this so matches replay exactly from a seed.
public struct SplitMix64 {
    public var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func float() -> Float { Float(next() >> 40) / Float(1 << 24) }
    public mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * float() }
    public mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    public mutating func gaussian() -> Float {
        let u1 = max(float(), 1e-6), u2 = float()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
