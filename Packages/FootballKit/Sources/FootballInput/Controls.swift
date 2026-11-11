import simd
import Foundation
import FootballGame
import FootballPhysics

/// Device-independent controller state in *screen* space (stick.y > 0 = up on screen).
public struct ControlState: Equatable {
    public var stick: Vec2 = .zero
    public var sprint = false
    public var pass = false, through = false, lob = false, shoot = false
    public var tackle = false, slide = false
    public var switchPlayer = false
    public var jockey = false
    public var finesse = false
    public var skillStick: Vec2 = .zero
    // One-shot edges (consumed when read)
    public var cameraCycle = false, debugToggle = false, pauseToggle = false, restart = false, replay = false, confirm = false
    public init() {}

    /// Convert to simulation input using the camera's screen basis.
    public func playerInput(right: Vec2, up: Vec2) -> PlayerInput {
        PlayerInput(move: right * stick.x + up * stick.y, sprint: sprint, passHeld: pass, throughHeld: through, lobHeld: lob, shootHeld: shoot,
                    tackleHeld: tackle, slideHeld: slide, switchPressed: switchPlayer, finesseHeld: finesse, jockeyHeld: jockey,
                    skill: right * skillStick.x + up * skillStick.y)
    }
}

public enum PadButton: String, Codable, CaseIterable, Hashable {
    case cross, circle, square, triangle, l1, r1, l2, r2, options, dpadUp, dpadDown, dpadLeft, dpadRight, l3, r3
    public var label: String {
        switch self { case .cross: return "Cross (✕)"; case .circle: return "Circle (○)"; case .square: return "Square (□)"; case .triangle: return "Triangle (△)"
        case .l1: return "L1"; case .r1: return "R1"; case .l2: return "L2"; case .r2: return "R2"; case .options: return "Options"
        default: return rawValue }
    }
}

public enum GameAction: String, Codable, CaseIterable {
    case pass, shoot, lob, through, sprint, switchPlayer, tackle, slide, jockey, skill, finesse, pause
}

public enum ControlContext: String, Codable { case attack, defense }

/// Raw pad snapshot (what the GameController adapter produces).
public struct PadState: Equatable {
    public var leftStick: Vec2 = .zero
    public var rightStick: Vec2 = .zero
    public var pressed: Set<PadButton> = []
    public var l2: Float = 0, r2: Float = 0
    public init() {}
}

public struct ControllerSettings: Codable, Equatable {
    public var deadZone: Float = 0.15
    /// Response curve exponent: 1 = linear, >1 = finer control near the centre.
    public var curve: Float = 1.4
    public var triggerThreshold: Float = 0.35
    public init() {}
}

/// Separate attack and defence layouts; both remappable.
public struct ControlBindings: Codable, Equatable {
    public var attack: [PadButton: GameAction]
    public var defense: [PadButton: GameAction]
    public init(attack: [PadButton: GameAction], defense: [PadButton: GameAction]) { self.attack = attack; self.defense = defense }

    public static let standard = ControlBindings(
        attack: [.cross: .pass, .circle: .shoot, .square: .lob, .triangle: .through, .r2: .sprint, .l1: .switchPlayer, .l2: .jockey, .r1: .finesse, .options: .pause],
        defense: [.cross: .tackle, .circle: .slide, .square: .switchPlayer, .triangle: .through, .r2: .sprint, .l1: .switchPlayer, .l2: .jockey, .r1: .tackle, .options: .pause])

    public func bindings(_ c: ControlContext) -> [PadButton: GameAction] { c == .attack ? attack : defense }

    /// Remap: `button` now triggers `action` in `context`; any other button that had `action` there is cleared (no duplicates).
    public mutating func remap(_ button: PadButton, to action: GameAction, in context: ControlContext) {
        var m = bindings(context)
        for (b, a) in m where a == action { m[b] = nil }
        m[button] = action
        if context == .attack { attack = m } else { defense = m }
    }
}

public enum ControlMapper {
    public static func shape(_ v: Vec2, _ s: ControllerSettings) -> Vec2 {
        let m = simd_length(v)
        guard m > s.deadZone else { return .zero }
        let n = min(1, (m - s.deadZone) / (1 - s.deadZone))
        return v / m * pow(n, s.curve)
    }

    public static func map(_ pad: PadState, context: ControlContext, bindings: ControlBindings, settings: ControllerSettings = .init()) -> ControlState {
        var c = ControlState()
        c.stick = shape(pad.leftStick, settings)
        c.skillStick = shape(pad.rightStick, settings)
        var down = pad.pressed
        if pad.l2 > settings.triggerThreshold { down.insert(.l2) }
        if pad.r2 > settings.triggerThreshold { down.insert(.r2) }
        for (button, action) in bindings.bindings(context) where down.contains(button) {
            switch action {
            case .pass: c.pass = true; case .shoot: c.shoot = true; case .lob: c.lob = true; case .through: c.through = true
            case .sprint: c.sprint = true; case .switchPlayer: c.switchPlayer = true; case .tackle: c.tackle = true; case .slide: c.slide = true
            case .jockey: c.jockey = true; case .finesse: c.finesse = true; case .skill: break; case .pause: c.pauseToggle = true
            }
        }
        return c
    }
}

/// Holds a short press alive for a few ticks so an action pressed a moment early still counts (input buffering).
public struct ButtonBuffer {
    public var window: Float
    private var remaining: [GameAction: Float] = [:]
    public init(window: Float = 0.15) { self.window = window }
    public mutating func press(_ a: GameAction) { remaining[a] = window }
    public mutating func tick(_ dt: Float) { for k in remaining.keys { remaining[k]! -= dt; if remaining[k]! <= 0 { remaining[k] = nil } } }
    public func isBuffered(_ a: GameAction) -> Bool { remaining[a] != nil }
    public mutating func consume(_ a: GameAction) -> Bool { defer { remaining[a] = nil }; return remaining[a] != nil }
}

/// Which controller drives which team: keeps assignments stable across disconnect/reconnect (by controller slot id).
public struct PlayerAssignments {
    public private(set) var teamForSlot: [Int: TeamSide] = [:]
    public private(set) var connected: Set<Int> = []
    public private(set) var disconnectedWhilePlaying: Set<Int> = []
    public init() {}

    public mutating func connect(slot: Int, versus: Bool) {
        connected.insert(slot)
        if teamForSlot[slot] == nil {
            let used = Set(teamForSlot.values)
            teamForSlot[slot] = !used.contains(.home) ? .home : (versus ? .away : .home)
        }
        disconnectedWhilePlaying.remove(slot)
    }
    public mutating func disconnect(slot: Int) { connected.remove(slot); disconnectedWhilePlaying.insert(slot) }
    public var needsReconnect: Bool { !disconnectedWhilePlaying.isEmpty }
}
