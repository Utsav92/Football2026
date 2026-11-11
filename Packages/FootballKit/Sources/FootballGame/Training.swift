import Foundation
import simd
import FootballPhysics

public enum TrainingKind: String, CaseIterable, Codable {
    case freePractice = "Free Practice", shooting = "Shooting", passing = "Passing", penalties = "Penalties", freeKicks = "Free Kicks"
}

/// Drills built on the real match engine: the opposition is removed (or reduced to a keeper / wall) and attempts reset automatically.
public final class TrainingSession {
    public let kind: TrainingKind
    public let sim: MatchSimulation
    public private(set) var attempts = 0
    public private(set) var goals = 0
    public private(set) var saves = 0
    public private(set) var passesCompleted = 0
    public private(set) var streak = 0
    private var rng: SplitMix64
    private var cooldown: Float = 0
    private var attemptTime: Float = 0
    private var attemptOpen = false

    public init(kind: TrainingKind, home: TeamSetup, away: TeamSetup, seed: UInt64 = 1) {
        self.kind = kind
        rng = SplitMix64(seed: seed &+ 77)
        sim = MatchSimulation(config: MatchConfig(home: home, away: away, matchLengthSeconds: 1_000_000, difficulty: .semipro, humanTeams: [.home], seed: seed))
        configure()
    }

    private var humanID: Int { sim.controlled(.home) ?? 9 }

    private func removeOpposition(keepKeeper: Bool = true) {
        for i in sim.players.indices where sim.players[i].team == .away && (!keepKeeper || sim.players[i].role != .gk) { sim.players[i].onPitch = false }
    }

    private func configure() {
        switch kind {
        case .freePractice:
            removeOpposition()
            sim.forcePhase(.playing); sim.placeBall(Vec3(0, PitchSpec.ballRadius, 0))
        case .shooting:
            removeOpposition()
            for i in sim.players.indices where sim.players[i].team == .home && i != humanID && sim.players[i].role != .gk { sim.players[i].onPitch = false }
            resetShot()
        case .passing:
            removeOpposition(keepKeeper: false)
            sim.forcePhase(.playing)
            let h = humanID
            sim.place(player: h, at: Vec2(-5, 0), heading: 0); sim.placeBall(Vec3(-4.1, PitchSpec.ballRadius, 0.2))
            for (k, i) in sim.players.indices.filter({ sim.players[$0].team == .home && $0 != h && sim.players[$0].role != .gk }).enumerated() {
                if k < 4 { let a = Float(k) * .pi / 2 + 0.5; sim.place(player: i, at: Vec2(-5 + 14 * cos(a), 14 * sin(a))) } else { sim.players[i].onPitch = false }
            }
        case .penalties:
            removeOpposition()
            for i in sim.players.indices where sim.players[i].team == .home && sim.players[i].role != .gk && i != humanID { sim.players[i].onPitch = false }
            startPenalty()
        case .freeKicks:
            startFreeKick()
        }
    }

    private func resetShot() {
        let h = humanID
        let x = rng.range(20, 31), z = rng.range(-14, 14)
        sim.forcePhase(.playing)
        sim.place(player: h, at: Vec2(x, z), heading: atan2(-z, 52.5 - x))
        sim.placeBall(Vec3(x + 0.8, PitchSpec.ballRadius, z))
        sim.place(player: 11, at: Vec2(50, 0), heading: .pi)
        sim.ballOwner = nil
        attemptTime = 0; attemptOpen = true
    }
    private func startPenalty() { sim.setupRestart(.penalty, team: .home, spot: Laws.penaltySpot(defending: .away)); attemptTime = 0; attemptOpen = true }
    private func startFreeKick() {
        sim.forcePhase(.playing)
        let z = rng.range(-14, 14), x = 52.5 - rng.range(18, 28)
        sim.setupRestart(.freeKick, team: .home, spot: Vec2(x, z)); attemptTime = 0; attemptOpen = true
    }

    private func finishAttempt(scored: Bool, saved: Bool = false) {
        guard attemptOpen else { return }
        attemptOpen = false; attempts += 1
        if scored { goals += 1; streak += 1 } else { streak = 0 }
        if saved { saves += 1 }
        cooldown = 1.2
    }

    public func step(_ input: PlayerInput) {
        let dt = MatchSimulation.dt
        if cooldown > 0 {
            sim.step([:])
            cooldown -= dt
            if cooldown <= 0 {
                switch kind { case .shooting: resetShot(); case .penalties: startPenalty(); case .freeKicks: startFreeKick(); default: break }
                _ = sim.drainEvents()
            }
            return
        }
        sim.step([.home: input])
        attemptTime += dt
        for e in sim.drainEvents() {
            switch e {
            case .goal(.home, _): finishAttempt(scored: true)
            case .save: if kind != .passing { finishAttempt(scored: false, saved: true) }
            case .restart(let k, _) where attemptOpen && !(k == .penalty || k == .freeKick): finishAttempt(scored: false)
            case .passCompleted(let from, let to) where kind == .passing && sim.players[from].team == .home && sim.players[to].team == .home: passesCompleted += 1
            default: break
            }
        }
        if kind != .freePractice && kind != .passing && attemptOpen {
            if case .goalCelebration = sim.phase { finishAttempt(scored: true) }
            if attemptTime > 9 { finishAttempt(scored: false) }
        }
        // Free practice: keep the session alive without restarts or goal celebrations.
        if kind == .freePractice, case .goalCelebration = sim.phase { sim.forcePhase(.playing); sim.placeBall(Vec3(0, PitchSpec.ballRadius, 0)) }
        if kind == .passing, case .restart = sim.phase { sim.forcePhase(.playing); sim.placeBall(Vec3(-4, PitchSpec.ballRadius, 0)) }
    }
}
