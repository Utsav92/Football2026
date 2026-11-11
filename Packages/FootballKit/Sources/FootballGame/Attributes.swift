import Foundation

public enum Role: String, Codable, CaseIterable {
    case gk, cb, lb, rb, dm, cm, am, lm, rm, lw, rw, st
    public enum Line { case goalkeeper, defender, midfielder, forward }
    public var line: Line {
        switch self {
        case .gk: return .goalkeeper
        case .cb, .lb, .rb: return .defender
        case .dm, .cm, .am, .lm, .rm: return .midfielder
        case .lw, .rw, .st: return .forward
        }
    }
    public var isWide: Bool { [.lb, .rb, .lm, .rm, .lw, .rw].contains(self) }
}

/// The 17 required attributes (1...99). Every one feeds a formula in `Derived` or the match engine.
public struct PlayerAttributes: Codable, Equatable {
    public var sprintSpeed = 60, acceleration = 60, stamina = 60, strength = 60, agility = 60, balance = 60
    public var dribbling = 60, ballControl = 60, shortPassing = 60, longPassing = 60
    public var shootingAccuracy = 60, shotPower = 60
    public var defensiveAwareness = 60, tackling = 60, goalkeeping = 20, positioning = 60, reactionTime = 60
    public init() {}

    public var overall: Int {
        let v = [sprintSpeed, acceleration, stamina, strength, agility, balance, dribbling, ballControl, shortPassing,
                 longPassing, shootingAccuracy, shotPower, defensiveAwareness, tackling, positioning, reactionTime]
        return v.reduce(0, +) / v.count
    }

    // MARK: Derived gameplay quantities (SI units)
    public var sprintMS: Float { 7.4 + 0.026 * Float(sprintSpeed) }            // 50 -> 8.7 m/s, 90 -> 9.7
    public var jogMS: Float { sprintMS * 0.68 }
    public var accelMS2: Float { 9 + 0.1 * Float(acceleration) }
    public var turnRate: Float { 8 + 0.08 * Float(agility) }
    public var sprintDrain: Float { max(0.03, 0.15 - 0.0009 * Float(stamina)) }  // per second
    public var staminaRecovery: Float { 0.03 + 0.0004 * Float(stamina) }
    public var decisionDelay: Float { max(0.08, 0.5 - 0.0035 * Float(reactionTime)) }
    public var trapLimit: Float { 7 + 0.09 * Float(ballControl) }               // max ball speed that can be cushioned
    public var dribbleFactor: Float { 0.86 + 0.0014 * Float(dribbling) }
    public var dribbleGain: Float { 9 + 0.07 * Float(ballControl) }
    public var maxShotSpeed: Float { 22 + 0.14 * Float(shotPower) }
    public var maxPassSpeed: Float { 18 + 0.1 * Float(longPassing) }
    /// Angular pass error (rad, 1 sigma) before distance scaling.
    public func passError(long: Bool) -> Float { 0.02 + 0.0009 * Float(100 - (long ? longPassing : shortPassing)) }
    public var shotError: Float { 0.015 + 0.0007 * Float(100 - shootingAccuracy) }

    public static func generated(role: Role, quality q: Int, rng: inout SplitMix64) -> PlayerAttributes {
        var a = PlayerAttributes()
        func g(_ bias: Int) -> Int { max(25, min(97, q + bias + Int((rng.gaussian() * 6).rounded()))) }
        let line = role.line
        let d = line == .defender, m = line == .midfielder, f = line == .forward, k = line == .goalkeeper
        a.sprintSpeed = g(f ? 6 : d ? -2 : 0); a.acceleration = g(f ? 5 : 0); a.stamina = g(m ? 6 : 0)
        a.strength = g(d ? 6 : f ? 0 : -2); a.agility = g(f ? 4 : 0); a.balance = g(0)
        a.dribbling = g(f ? 6 : m ? 3 : -8); a.ballControl = g(f ? 4 : m ? 4 : -4)
        a.shortPassing = g(m ? 6 : d ? -2 : 0); a.longPassing = g(m ? 3 : d ? 0 : -4)
        a.shootingAccuracy = g(f ? 8 : m ? -2 : -15); a.shotPower = g(f ? 6 : m ? 0 : -8)
        a.defensiveAwareness = g(d ? 8 : m ? 0 : -15); a.tackling = g(d ? 8 : m ? 0 : -15)
        a.positioning = g(0); a.reactionTime = g(0)
        a.goalkeeping = k ? g(8) : max(15, min(40, 25 + Int(rng.gaussian() * 5)))
        if k { a.sprintSpeed = g(-10); a.dribbling = g(-20); a.shootingAccuracy = g(-25) }
        return a
    }
}
