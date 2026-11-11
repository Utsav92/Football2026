import Foundation

/// Compressed two-half clock. `matchLengthSeconds` real seconds map to 90 game minutes; stoppage time is added per half.
public struct MatchClock {
    public static let halfSeconds: Float = 45 * 60
    public var matchLengthSeconds: Float
    public private(set) var gameSeconds: Float = 0
    public private(set) var half = 1
    public var addedSeconds: Float = 0   // for the current half

    public init(matchLengthSeconds: Float = 360) { self.matchLengthSeconds = matchLengthSeconds }

    public var timeScale: Float { 5400 / matchLengthSeconds }
    public var inExtraTime: Bool { half >= 3 }
    public var nominalEnd: Float { half <= 2 ? Self.halfSeconds * Float(half) : (half == 3 ? 6300 : 7200) }
    public var inAddedTime: Bool { gameSeconds >= nominalEnd }
    public var isHalfOver: Bool { gameSeconds >= nominalEnd + addedSeconds }
    public var minutes: Int { Int(gameSeconds) / 60 }
    public var display: String {
        if inAddedTime {
            let extra = Int(gameSeconds - nominalEnd) / 60 + 1
            return String(format: "%d+%d", Int(nominalEnd) / 60, min(extra, max(1, Int((addedSeconds / 60).rounded(.up)))))
        }
        return String(format: "%02d:%02d", minutes, Int(gameSeconds) % 60)
    }

    public mutating func tick(_ realDT: Float) { gameSeconds += realDT * timeScale }
    public mutating func startSecondHalf() { half = 2; gameSeconds = Self.halfSeconds; addedSeconds = 0 }
    /// Starts extra-time period 1 (half 3) or 2 (half 4).
    public mutating func startNextPeriod() { half += 1; gameSeconds = half == 3 ? 5400 : 6300; addedSeconds = 0 }
    public mutating func reset() { gameSeconds = 0; half = 1; addedSeconds = 0 }
}

/// Converts variable frame time into whole fixed simulation steps.
public struct FixedStepper {
    public let step: Float
    public let maxFrameTime: Float
    private var accumulator: Float = 0
    public init(step: Float = 1.0 / 120.0, maxFrameTime: Float = 0.25) { self.step = step; self.maxFrameTime = maxFrameTime }
    public mutating func advance(frameTime: Float) -> Int {
        accumulator += min(max(frameTime, 0), maxFrameTime)
        let n = Int(accumulator / step + 1e-4)
        accumulator = max(0, accumulator - Float(n) * step)
        return n
    }
    public var alpha: Float { accumulator / step }
}
