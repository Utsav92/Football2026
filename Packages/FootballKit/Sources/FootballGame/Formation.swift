import Foundation
import FootballPhysics

public struct FormationSlot: Equatable {
    public let role: Role
    /// 0 = own goal line ... 1 = opposition goal line (base shape with the ball at midfield).
    public let depth: Float
    /// -1 = left ... +1 = right, from the team's own attacking perspective.
    public let lateral: Float
}

public enum Formation: String, CaseIterable, Codable {
    case f433 = "4-3-3", f442 = "4-4-2", f4231 = "4-2-3-1", f352 = "3-5-2", f532 = "5-3-2", f4141 = "4-1-4-1"

    private static func s(_ r: Role, _ d: Float, _ l: Float) -> FormationSlot { FormationSlot(role: r, depth: d, lateral: l) }

    /// Slot 0 is always the goalkeeper. Always exactly 11 slots.
    public var slots: [FormationSlot] {
        let gk = Self.s(.gk, 0.03, 0)
        let back4 = [Self.s(.lb, 0.22, -0.8), Self.s(.cb, 0.19, -0.28), Self.s(.cb, 0.19, 0.28), Self.s(.rb, 0.22, 0.8)]
        switch self {
        case .f433:
            return [gk] + back4 + [Self.s(.cm, 0.42, -0.4), Self.s(.dm, 0.37, 0), Self.s(.cm, 0.42, 0.4),
                                   Self.s(.lw, 0.68, -0.72), Self.s(.st, 0.75, 0), Self.s(.rw, 0.68, 0.72)]
        case .f442:
            return [gk] + back4 + [Self.s(.lm, 0.46, -0.8), Self.s(.cm, 0.41, -0.25), Self.s(.cm, 0.41, 0.25), Self.s(.rm, 0.46, 0.8),
                                   Self.s(.st, 0.72, -0.2), Self.s(.st, 0.72, 0.2)]
        case .f4231:
            return [gk] + back4 + [Self.s(.dm, 0.36, -0.25), Self.s(.dm, 0.36, 0.25),
                                   Self.s(.lm, 0.56, -0.7), Self.s(.am, 0.59, 0), Self.s(.rm, 0.56, 0.7), Self.s(.st, 0.75, 0)]
        case .f352:
            return [gk, Self.s(.cb, 0.2, -0.42), Self.s(.cb, 0.17, 0), Self.s(.cb, 0.2, 0.42),
                    Self.s(.lm, 0.44, -0.85), Self.s(.cm, 0.4, -0.3), Self.s(.dm, 0.33, 0), Self.s(.cm, 0.4, 0.3), Self.s(.rm, 0.44, 0.85),
                    Self.s(.st, 0.72, -0.2), Self.s(.st, 0.72, 0.2)]
        case .f532:
            return [gk, Self.s(.lb, 0.26, -0.85), Self.s(.cb, 0.2, -0.42), Self.s(.cb, 0.17, 0), Self.s(.cb, 0.2, 0.42), Self.s(.rb, 0.26, 0.85),
                    Self.s(.cm, 0.43, -0.35), Self.s(.cm, 0.4, 0), Self.s(.cm, 0.43, 0.35),
                    Self.s(.st, 0.72, -0.2), Self.s(.st, 0.72, 0.2)]
        case .f4141:
            return [gk] + back4 + [Self.s(.dm, 0.33, 0), Self.s(.lm, 0.5, -0.8), Self.s(.cm, 0.47, -0.25), Self.s(.cm, 0.47, 0.25),
                                   Self.s(.rm, 0.5, 0.8), Self.s(.st, 0.74, 0)]
        }
    }
}

extension Formation {
    /// Mean depth (0...1) of the ten outfield slots: the formation's own centroid.
    public var outfieldMeanDepth: Float {
        let o = slots.dropFirst()
        return o.map { $0.depth }.reduce(0, +) / Float(o.count)
    }
}

/// Team-shape constants fitted to real tracking data by Tools/analyze_formations.py
/// (SkillCorner Open Data, A-League 2024/25 match 1925299, MIT licence, credit SkillCorner). The values are fitted on SkillCorner ONLY.
/// A second public sample (Metrica; it has no licence, so nothing derived from it is shipped) was used locally as a cross-check only and
/// agreed within ~0.1 on slopes. Re-fit with `python3 Tools/analyze_formations.py`.
public enum TacticalPriors {
    /// team centroid x (own-goal origin = -52.5, attack = +x, metres) = intercept + slope * ball x (team coordinates)
    public static let centroidSlope: Float = 0.64
    public static let centroidInterceptInPossession: Float = 2.4
    public static let centroidInterceptOutOfPossession: Float = -9.1
    /// Fraction of the base formation's length / width kept (real: length 28.4 / 23.4 m and width 30.9 / 25.5 m
    /// in / out of possession, against ~52 m / ~50 m for the uncompressed base shapes).
    public static let lengthKeepInPossession: Float = 0.56
    public static let lengthKeepOutOfPossession: Float = 0.45
    public static let widthKeepInPossession: Float = 0.62
    public static let widthKeepOutOfPossession: Float = 0.52

    // Shot model: logistic regression on 43,078 real shots (4,492 goals), Wyscout public dataset (CC BY 4.0,
    // Pappalardo et al., Scientific Data 6:236, 2019). Penalties and free kicks excluded. Fitted by Tools/preprocess_events.py.
    public static let xgIntercept: Float = -1.2393
    public static let xgDistance: Float = -0.10017   // per metre
    public static let xgAngle: Float = 1.71337       // per radian subtended by the posts
    public static let xgHeader: Float = -0.98381

    /// Expected-goal probability for a shot from (dx metres along the pitch to the goal line, dy across) of the goal centre.
    public static func xG(dx: Float, dy: Float, header: Bool = false) -> Float {
        let dist = (dx * dx + dy * dy).squareRoot()
        var a = atan2(7.32 * dx, dx * dx + dy * dy - 3.66 * 3.66)
        if a < 0 { a += .pi }
        let z = xgIntercept + xgDistance * dist + xgAngle * a + (header ? xgHeader : 0)
        return 1 / (1 + exp(-z))
    }
}

public struct TeamTactics: Codable, Equatable {
    public var pressing: Float = 0.5        // 0 low block ... 1 high press
    public var defensiveLine: Float = 0.5   // 0 deep ... 1 high
    public var width: Float = 0.5
    public var directness: Float = 0.5      // 0 short build-up ... 1 direct/long
    public init(pressing: Float = 0.5, defensiveLine: Float = 0.5, width: Float = 0.5, directness: Float = 0.5) {
        self.pressing = pressing; self.defensiveLine = defensiveLine; self.width = width; self.directness = directness
    }
}

public struct ColorRGB: Codable, Equatable {
    public var r: Float, g: Float, b: Float
    public init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }
}

public struct Appearance: Codable, Equatable {
    public var skinTone = 3        // 0...5
    public var hairStyle = 0       // 0...5
    public var hairColor = 0       // 0...4
    public var height: Float = 1.8
    public var build: Float = 0.5  // 0 lean ... 1 stocky
    public init() {}
}

public struct PlayerProfile: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var number: Int
    public var role: Role
    public var attributes: PlayerAttributes
    public var appearance = Appearance()
    public init(id: Int, name: String, number: Int, role: Role, attributes: PlayerAttributes, appearance: Appearance = Appearance()) {
        self.id = id; self.name = name; self.number = number; self.role = role; self.attributes = attributes; self.appearance = appearance
    }
}

public struct TeamSetup: Codable, Equatable {
    public var name: String
    public var shortName: String
    public var formation: Formation
    public var tactics: TeamTactics
    public var primary: ColorRGB
    public var secondary: ColorRGB
    /// Starting XI in formation-slot order (index 0 = goalkeeper), followed by substitutes.
    public var players: [PlayerProfile]

    public init(name: String, shortName: String, formation: Formation = .f433, tactics: TeamTactics = .init(),
                primary: ColorRGB, secondary: ColorRGB, players: [PlayerProfile]) {
        self.name = name; self.shortName = shortName; self.formation = formation; self.tactics = tactics
        self.primary = primary; self.secondary = secondary; self.players = players
    }

    /// Deterministic fictional squad (11 starters in slot order + 5 subs) for tests and defaults.
    public static func generated(name: String, short: String, quality: Int, formation: Formation = .f433, seed: UInt64,
                                 primary: ColorRGB, secondary: ColorRGB, idBase: Int = 0) -> TeamSetup {
        var rng = SplitMix64(seed: seed)
        var ps: [PlayerProfile] = []
        let surnames = ["Alder", "Brook", "Castell", "Dorn", "Ebner", "Fairn", "Gaunt", "Holt", "Ivers", "Jory", "Kestrel", "Lund", "Marsh", "Nyland", "Orsay", "Pryce", "Quill", "Rowan", "Sable", "Thorne"]
        func make(_ i: Int, _ role: Role) -> PlayerProfile {
            var ap = Appearance(); ap.skinTone = rng.int(6); ap.hairStyle = rng.int(6); ap.hairColor = rng.int(5)
            ap.height = role == .gk ? rng.range(1.85, 1.98) : rng.range(1.70, 1.92); ap.build = rng.float()
            return PlayerProfile(id: idBase + i, name: "\(String(UnicodeScalar(65 + UInt8(rng.int(26))))). \(surnames[rng.int(surnames.count)])",
                                 number: i == 0 ? 1 : i + 1, role: role,
                                 attributes: .generated(role: role, quality: quality, rng: &rng), appearance: ap)
        }
        for (i, slot) in formation.slots.enumerated() { ps.append(make(i, slot.role)) }
        let subRoles: [Role] = [.gk, .cb, .cm, .lw, .st]
        for (j, r) in subRoles.enumerated() { ps.append(make(11 + j, r)) }
        return TeamSetup(name: name, shortName: short, formation: formation, primary: primary, secondary: secondary, players: ps)
    }
}

public enum Difficulty: Int, CaseIterable, Codable {
    case beginner, amateur, semipro, professional, worldClass
    public var name: String { ["Beginner", "Amateur", "Semi-Pro", "Professional", "World Class"][rawValue] }
    /// 0.35 ... 1.0 scalar used across AI decision quality.
    public var skill: Float { [0.35, 0.5, 0.65, 0.82, 1.0][rawValue] }
}
