import Foundation
import simd
import FootballPhysics

public enum TeamSide: Int, Codable, CaseIterable {
    case home = 0, away = 1
    public var opponent: TeamSide { self == .home ? .away : .home }
    /// +1: attacks the +X goal. -1: attacks the -X goal.
    public var attackSign: Float { self == .home ? 1 : -1 }
}

public enum KickKind: Equatable { case pass, through, lob, shot, header, volley }
public enum Card: Equatable { case yellow, red }
public enum RestartKind: Equatable { case kickoff, throwIn, goalKick, corner, freeKick, indirectFreeKick, penalty }

/// One controller's worth of input, already converted to world space (+X = home attacking direction).
public struct PlayerInput: Equatable {
    public var move: Vec2 = .zero
    public var sprint = false
    public var passHeld = false
    public var throughHeld = false
    public var lobHeld = false
    public var shootHeld = false
    public var tackleHeld = false
    public var slideHeld = false
    public var switchPressed = false
    /// Modifier with shoot: curled (finesse) shot using Magnus spin.
    public var finesseHeld = false
    /// Defending: stay goal-side and slow; attacking: shield the ball.
    public var jockeyHeld = false
    /// Right stick: skill move direction (relative to screen basis already converted to world).
    public var skill: Vec2 = .zero
    public init(move: Vec2 = .zero, sprint: Bool = false, passHeld: Bool = false, throughHeld: Bool = false,
                lobHeld: Bool = false, shootHeld: Bool = false, tackleHeld: Bool = false, slideHeld: Bool = false,
                switchPressed: Bool = false, finesseHeld: Bool = false, jockeyHeld: Bool = false, skill: Vec2 = .zero) {
        self.finesseHeld = finesseHeld; self.jockeyHeld = jockeyHeld; self.skill = skill
        self.move = move; self.sprint = sprint; self.passHeld = passHeld; self.throughHeld = throughHeld
        self.lobHeld = lobHeld; self.shootHeld = shootHeld; self.tackleHeld = tackleHeld
        self.slideHeld = slideHeld; self.switchPressed = switchPressed
    }
}

public struct KickCharge: Equatable {
    public var kind: KickKind
    public var time: Float
    public var level: Float
}

public struct KickTuning {
    public var chargeTime: Float = 0.9
    public var minPower: Float = 0.25
    public var range: Float = 1.7
    public var lockout: Float = 0.3
    /// Input-buffer window (s): a kick pressed this soon before the ball is in range still fires.
    public var bufferWindow: Float = 0.18
    public init() {}
}

public struct Score: Equatable {
    public var home = 0
    public var away = 0
    public init() {}
    public subscript(side: TeamSide) -> Int {
        get { side == .home ? home : away }
        set { if side == .home { home = newValue } else { away = newValue } }
    }
}

public struct ShootoutState: Equatable {
    public var taken = [0, 0]
    public var scored = [0, 0]
    public var next: TeamSide = .home
    public var winner: TeamSide?
    public var inFlight = false
    public var timer: Float = 0
    public init() {}
}

public struct TeamStats: Equatable {
    public var possessionSeconds: Float = 0
    public var shots = 0, shotsOnTarget = 0
    public var passes = 0, passesCompleted = 0
    public var tackles = 0, tacklesWon = 0
    public var fouls = 0, yellowCards = 0, redCards = 0
    public var corners = 0, offsides = 0, saves = 0
    public init() {}
}

public enum AIState: UInt8, CaseIterable {
    case idle, positioning, supporting, pressing, marking, intercepting, dribbling, passing, shooting, tackling, recovering, goalkeeping, controlled, setPiece
    public var label: String {
        switch self {
        case .idle: return "IDLE"; case .positioning: return "POSITIONING"; case .supporting: return "SUPPORTING"
        case .pressing: return "PRESSING"; case .marking: return "MARKING"; case .intercepting: return "INTERCEPTING"
        case .dribbling: return "DRIBBLING"; case .passing: return "PASSING"; case .shooting: return "SHOOTING"
        case .tackling: return "TACKLING"; case .recovering: return "RECOVERING"; case .goalkeeping: return "GOALKEEPING"
        case .controlled: return "HUMAN"; case .setPiece: return "SET PIECE"
        }
    }
}

public struct Footballer {
    public let id: Int
    public let team: TeamSide
    public let slot: Int
    public var role: Role
    public var name: String
    public var number: Int
    public var attributes: PlayerAttributes
    public var appearance: Appearance

    public var pos: Vec2 = .zero
    public var vel: Vec2 = .zero
    public var heading: Float = 0
    public var stamina: Float = 1
    public var isSprinting = false
    public var onPitch = true
    public var yellowCards = 0
    public var sentOff = false
    public var state: AIState = .idle
    /// Why the AI chose its current state/target: a short code shown by the debug overlay.
    public var target: Vec2 = .zero
    public var reason: String = ""

    // Animation-facing timers (seconds remaining / elapsed)
    public var kickAnim: Float = 0
    public var tackleAnim: Float = 0
    public var celebrate: Float = 0
    public var diveTime: Float = 0
    public var diveDir: Vec2 = .zero
    public var fallenTime: Float = 0
    public var holdingBall = false
    public var headAnim: Float = 0
    public var skillAnim: Float = 0

    // Engine-internal
    var desiredDir: Vec2 = .zero
    var wantSprint = false
    var sprintLocked = false
    var kickLock: Float = 0
    var tackleCooldown: Float = 0
    var stun: Float = 0
    var slideTime: Float = 0
    var slideDir: Vec2 = .zero
    var thinkOffset = 0
    var holdTimer: Float = 0
    var reactTimer: Float = 0
    var saveCooldown: Float = 0
    var possessionTime: Float = 0
    var markTarget: Int = -1
    var jockey = false
    var skillOffset: Vec2 = .zero
    var evade: Float = 0
    var skillCooldown: Float = 0

    public var facing: Vec2 { Vec2(cos(heading), sin(heading)) }
    public var speed: Float { simd_length(vel) }
    public var isSliding: Bool { slideTime > 0 }
    public var isDiving: Bool { diveTime > 0 }
    public var isDown: Bool { fallenTime > 0 }

    init(id: Int, team: TeamSide, slot: Int, role: Role, profile: PlayerProfile) {
        self.id = id; self.team = team; self.slot = slot; self.role = role
        name = profile.name; number = profile.number; attributes = profile.attributes; appearance = profile.appearance
    }
}

public struct RestartInfo: Equatable {
    public var kind: RestartKind
    public var team: TeamSide
    public var spot: Vec2
    public var taker: Int
    public var elapsed: Float = 0
    public var minWait: Float
}

public enum MatchPhase: Equatable {
    case playing
    case goalCelebration(remaining: Float, scoredBy: TeamSide)
    case restart(RestartInfo)
    case halfTime(remaining: Float)
    case shootout
    case fullTime
}

public enum GameEvent: Equatable {
    case kick(player: Int, kind: KickKind, power: Float)
    case possession(TeamSide)
    case passCompleted(from: Int, to: Int)
    case tackle(by: Int, on: Int, won: Bool)
    case foul(by: Int, on: Int, card: Card?, penalty: Bool)
    case offside(player: Int)
    case save(keeper: Int, caught: Bool)
    case goal(TeamSide, scorer: Int?)
    case ball(BallEvent)
    case restart(RestartKind, TeamSide)
    case halfTime, fullTime, extraTimeStart, shootoutStart
    case advantage(TeamSide)
    case skillMove(player: Int)
    case shootoutKick(team: TeamSide, scored: Bool)
    case switched(TeamSide, to: Int)
    case substitution(TeamSide, out: Int, in: Int)
}

public struct MatchConfig {
    public var home: TeamSetup
    public var away: TeamSetup
    public var matchLengthSeconds: Float = 360
    public var difficulty: Difficulty = .professional
    /// Optional per-side override (e.g. a strong AI home side vs a weak AI away side).
    public var difficultyOverride: [TeamSide: Difficulty] = [:]
    public var humanTeams: Set<TeamSide> = [.home]
    public var seed: UInt64 = 1
    /// Wet pitch (rain): changes ball physics (rolling resistance and bounce).
    public var wetPitch = false
    /// Knockout rules: a draw after 90 minutes goes to extra time and then a penalty shootout.
    public var knockout = false
    public init(home: TeamSetup, away: TeamSetup, matchLengthSeconds: Float = 360, difficulty: Difficulty = .professional,
                humanTeams: Set<TeamSide> = [.home], seed: UInt64 = 1) {
        self.home = home; self.away = away; self.matchLengthSeconds = matchLengthSeconds
        self.difficulty = difficulty; self.humanTeams = humanTeams; self.seed = seed
    }
}
