import Foundation
import simd
import FootballPhysics

extension MatchSimulation {
    // MARK: Advantage
    func updateAdvantage(_ dt: Float) {
        guard var a = advantage else { return }
        a.remaining -= dt
        if let o = ballOwner, players[o].team == a.victim.opponent {         // fouled side lost the ball: bring the play back
            advantage = nil
            setupRestart(.freeKick, team: a.victim, spot: a.spot)
            return
        }
        advantage = a.remaining <= 0 ? nil : a
    }

    // MARK: Penalty shootout (knockout ties after extra time)
    public var shootoutWinner: TeamSide? { shootout.winner }

    func startShootout() {
        shootoutActive = true; shootout = ShootoutState(); advantage = nil
        events.append(.shootoutStart)
        var k = [0, 0]
        for i in players.indices where players[i].onPitch && players[i].role != .gk {         // everyone but the keepers waits at the centre circle
            let t = players[i].team.rawValue
            let a = Float(k[t]) * 0.55 + (t == 0 ? 0 : .pi)
            players[i].pos = Vec2(cos(a) * 5.5, sin(a) * 5.5); players[i].vel = .zero; players[i].desiredDir = .zero; k[t] += 1
        }
        ballOwner = nil
        shootout.timer = 1.5
        phase = .shootout
    }

    func shootoutPause(_ dt: Float) {
        idleStep(dt)
        shootout.timer -= dt
        if shootout.timer <= 0 { nextShootoutKick() }
    }

    private func nextShootoutKick() {
        let team = shootout.next
        let eligible = players.indices.filter { players[$0].team == team && players[$0].onPitch && players[$0].role != .gk }
            .sorted { Int(players[$0].attributes.shootingAccuracy + players[$0].attributes.shotPower) > Int(players[$1].attributes.shootingAccuracy + players[$1].attributes.shotPower) }
        forcedTaker = eligible.isEmpty ? nil : eligible[shootout.taken[team.rawValue] % eligible.count]
        setupRestart(.penalty, team: team, spot: Laws.penaltySpot(defending: team.opponent))
        shootout.inFlight = true; shootout.timer = 0
    }

    /// The kick is in flight: resolve as goal, save, miss or timeout.
    func shootoutPlayStep(_ dt: Float) {
        shootout.timer += dt
        for i in players.indices where players[i].role != .gk { players[i].desiredDir = .zero }
        for i in players.indices { integrate(i, dt) }
        goalkeepersStep(dt)
        updateBallControl(dt)
        stepBall(dt)
        let saved = events.suffix(6).contains { if case .save = $0 { return true }; return false }
        let side = GoalDetector.side(of: ball)
        let scorerSide: Int = shootout.next == .home ? 1 : -1
        if side == scorerSide { resolveShootoutKick(scored: true) }
        else if side != 0 || saved || GoalDetector.isOutOfPlay(ball) || shootout.timer > 5 || (shootout.timer > 1.2 && ball.speed < 0.3) { resolveShootoutKick(scored: false) }
    }

    func resolveShootoutKick(scored: Bool) {
        let t = shootout.next.rawValue
        shootout.taken[t] += 1; if scored { shootout.scored[t] += 1 }
        events.append(.shootoutKick(team: shootout.next, scored: scored))
        let remH = max(0, 5 - shootout.taken[0]), remA = max(0, 5 - shootout.taken[1])
        var winner: TeamSide?
        if shootout.taken[0] >= 5 && shootout.taken[1] >= 5 {
            if shootout.taken[0] == shootout.taken[1], shootout.scored[0] != shootout.scored[1] { winner = shootout.scored[0] > shootout.scored[1] ? .home : .away }
        } else if shootout.scored[0] > shootout.scored[1] + remA { winner = .home }
        else if shootout.scored[1] > shootout.scored[0] + remH { winner = .away }
        ballOwner = nil
        if let w = winner {
            shootout.winner = w; shootoutActive = false; phase = .fullTime; events.append(.fullTime)
        } else {
            shootout.next = shootout.next.opponent; shootout.inFlight = false; shootout.timer = 1.6; phase = .shootout
        }
    }
}
