import Foundation
import simd
import FootballPhysics

struct TeamContext {
    var inPossession = false
    var ballDepth: Float = 0.5     // 0 own goal ... 1 opposition goal
    var ballLat: Float = 0         // -1 left ... +1 right (team perspective)
    var chaser = -1
    var second = -1
    var offsideLine: Float = 0     // x*attackSign of the second-last opponent
    var carrier = -1
}

struct AdvantageState { var victim: TeamSide; var spot: Vec2; var remaining: Float }

struct PendingKick { var kind: KickKind; var power: Float; var input: PlayerInput; var remaining: Float }

struct TeamRuntime {
    var pendingKick: PendingKick?
    var setup: TeamSetup
    var human: Bool
    var controlled: Int
    var skill: Float
    var ctx = TeamContext()
    var prevInput = PlayerInput()
    var charge: KickCharge?
    var subsUsed = 0
    var sinceSwitch: Float = 10
}

/// Authoritative 11v11 match: 22 players, ball, referee, clock. Pure Swift; no rendering dependency.
public final class MatchSimulation {
    public static let dt: Float = 1.0 / 120.0

    public let config: MatchConfig
    public internal(set) var players: [Footballer] = []
    public internal(set) var ball = BallState()
    public internal(set) var ballOwner: Int?
    public internal(set) var lastTouch: Int?
    public internal(set) var intendedReceiver: Int?
    public internal(set) var score = Score()
    public internal(set) var clock: MatchClock
    public internal(set) var phase: MatchPhase = .playing
    public internal(set) var stats = [TeamStats(), TeamStats()]
    public var kickTuning = KickTuning()

    var teams: [TeamRuntime] = []
    var rng: SplitMix64
    var physics = BallPhysics()
    var events: [GameEvent] = []
    var tick = 0
    var pendingOffside: [Int: Vec2] = [:]
    var pendingTeam: TeamSide = .home
    var overtimeReal: Float = 0
    var stoppageCredit: Float = 0
    var restartKickPending = false
    var advantage: AdvantageState?
    public internal(set) var shootout = ShootoutState()
    var shootoutActive = false
    var forcedTaker: Int?
    public var advantagePending: Bool { advantage != nil }
    var lastKickTeam: TeamSide = .home

    public init(config: MatchConfig) {
        self.config = config
        clock = MatchClock(matchLengthSeconds: config.matchLengthSeconds)
        rng = SplitMix64(seed: config.seed)
        for side in TeamSide.allCases {
            let setup = side == .home ? config.home : config.away
            let human = config.humanTeams.contains(side)
            let skill: Float = human ? 0.85 : (config.difficultyOverride[side] ?? config.difficulty).skill
            let forwardSlot = setup.formation.slots.lastIndex(where: { $0.role == .st }) ?? 10
            teams.append(TeamRuntime(setup: setup, human: human, controlled: human ? side.rawValue * 11 + forwardSlot : -1, skill: skill))
            let slots = setup.formation.slots
            for s in 0..<11 {
                var f = Footballer(id: side.rawValue * 11 + s, team: side, slot: s, role: slots[s].role, profile: setup.players[s])
                f.thinkOffset = s
                players.append(f)
            }
        }
        if config.wetPitch {          // rain: less rolling resistance, livelier bounce
            physics.config.rollingDecel *= 0.82; physics.config.groundRestitution += 0.03
        }
        beginMatch()
    }

    public func drainEvents() -> [GameEvent] { defer { events.removeAll(keepingCapacity: true) }; return events }
    public func controlled(_ side: TeamSide) -> Int? { teams[side.rawValue].human ? teams[side.rawValue].controlled : nil }
    public func charge(_ side: TeamSide) -> KickCharge? { teams[side.rawValue].charge }
    public func teamSetup(_ side: TeamSide) -> TeamSetup { teams[side.rawValue].setup }
    public func formation(_ side: TeamSide) -> Formation { teams[side.rawValue].setup.formation }
    public var possessionPercent: (home: Int, away: Int) {
        let h = stats[0].possessionSeconds, a = stats[1].possessionSeconds
        guard h + a > 0 else { return (50, 50) }
        let ph = Int((h / (h + a) * 100).rounded()); return (ph, 100 - ph)
    }

    // MARK: Setup

    func beginMatch() {
        for i in players.indices { resetPlayerState(i) }
        setupRestart(.kickoff, team: .home, spot: .zero)
    }

    public func restartMatch() {
        score = Score(); clock.reset(); stats = [TeamStats(), TeamStats()]; stoppageCredit = 0; overtimeReal = 0
        for i in players.indices { players[i].onPitch = true; players[i].sentOff = false; players[i].yellowCards = 0; players[i].stamina = 1 }
        beginMatch()
    }

    private func resetPlayerState(_ i: Int) {
        players[i].vel = .zero; players[i].kickLock = 0; players[i].stun = 0; players[i].slideTime = 0; players[i].diveTime = 0
        players[i].fallenTime = 0; players[i].holdingBall = false; players[i].tackleCooldown = 0
    }

    /// Test / tooling hook.
    public func place(player i: Int, at p: Vec2, heading: Float? = nil) {
        players[i].pos = p; players[i].vel = .zero
        if let h = heading { players[i].heading = h }
    }
    public func placeBall(_ p: Vec3, velocity v: Vec3 = .zero) {
        ball = BallState(position: p); ball.velocity = v; ballOwner = nil
    }
    public func forcePhase(_ p: MatchPhase) { phase = p }
    /// Tooling hook: jump straight to the kick-off of the second half.
    public func debugStartSecondHalf() { clock.startSecondHalf(); setupRestart(.kickoff, team: .away, spot: .zero) }

    func anchorWorld(slot: Int, side: TeamSide, ballDepth: Float, inPossession: Bool, ballLat: Float) -> Vec2 {
        let team = teams[side.rawValue]
        let s = team.setup.formation.slots[slot]
        let sign = side.attackSign
        let line = s.role.line
        if line == .goalkeeper { return Vec2(sign * (-PitchSpec.halfLength + 2.5), 0) }
        let tac = team.setup.tactics
        // Block position: the team centroid follows the ball (slope/intercepts fitted to real tracking, see TacticalPriors).
        let bx = (ballDepth - 0.5) * PitchSpec.length
        var cx = (inPossession ? TacticalPriors.centroidInterceptInPossession : TacticalPriors.centroidInterceptOutOfPossession)
            + TacticalPriors.centroidSlope * bx
        cx += (tac.defensiveLine - 0.5) * 8
        // Slot offset inside the block, compressed to the measured team length.
        var keepL = inPossession ? TacticalPriors.lengthKeepInPossession : TacticalPriors.lengthKeepOutOfPossession
        if !inPossession { keepL -= 0.06 * (tac.pressing - 0.5) }
        let off = (s.depth - team.setup.formation.outfieldMeanDepth) * PitchSpec.length * keepL
        var x = cx + off
        x = max(-PitchSpec.halfLength + 6, min(PitchSpec.halfLength - 3.5, x))
        let keepW = (inPossession ? TacticalPriors.widthKeepInPossession : TacticalPriors.widthKeepOutOfPossession) * (0.85 + 0.3 * tac.width)
        var lat = s.lateral * keepW
        lat += ballLat * (1 - abs(s.lateral) * 0.6) * 0.30
        return Vec2(sign * x, sign * lat * PitchSpec.halfWidth * 0.92)
    }

    // MARK: Restarts

    func chooseTaker(_ kind: RestartKind, _ team: TeamSide, _ spot: Vec2) -> Int {
        let mine = players.indices.filter { players[$0].team == team && players[$0].onPitch }
        func best(_ ids: [Int], by score: (Footballer) -> Float) -> Int { ids.max(by: { score(players[$0]) < score(players[$1]) }) ?? ids[0] }
        switch kind {
        case .goalKick: return mine.first(where: { players[$0].role == .gk }) ?? mine[0]
        case .penalty:
            if let f = forcedTaker { forcedTaker = nil; return f }
            return best(mine.filter { players[$0].role != .gk }) { Float($0.attributes.shootingAccuracy + $0.attributes.shotPower) }
        case .kickoff:
            let fw = mine.filter { players[$0].role.line == .forward || players[$0].role == .am }
            return best(fw.isEmpty ? mine : fw) { -simd_distance($0.pos, spot) }
        case .corner:
            let mids = mine.filter { players[$0].role.line == .midfielder || players[$0].role.line == .forward }
            return best(mids.isEmpty ? mine : mids) { Float($0.attributes.longPassing) - simd_distance($0.pos, spot) * 0.8 }
        case .throwIn:
            return best(mine.filter { players[$0].role != .gk }) { -simd_distance($0.pos, spot) }
        case .freeKick, .indirectFreeKick:
            let near = mine.filter { players[$0].role != .gk }.sorted { simd_distance(players[$0].pos, spot) < simd_distance(players[$1].pos, spot) }.prefix(4)
            return best(Array(near)) { Float($0.attributes.shootingAccuracy + $0.attributes.longPassing) }
        }
    }

    public func setupRestart(_ kind: RestartKind, team: TeamSide, spot rawSpot: Vec2) {
        var spot = rawSpot
        spot.x = max(-PitchSpec.halfLength, min(PitchSpec.halfLength, spot.x))
        spot.y = max(-PitchSpec.halfWidth, min(PitchSpec.halfWidth, spot.y))
        ballOwner = nil; intendedReceiver = nil; pendingOffside = [:]; advantage = nil
        for i in players.indices { players[i].holdingBall = false; players[i].diveTime = 0; players[i].slideTime = 0 }
        if kind == .kickoff { placeKickoffFormation(kickoffTeam: team) }
        let taker = chooseTaker(kind, team, spot)
        let sign = team.attackSign
        var tp = spot, heading: Float = sign > 0 ? 0 : .pi
        switch kind {
        case .throwIn: tp = Vec2(spot.x, spot.y + (spot.y > 0 ? -0.2 : 0.2)); heading = spot.y > 0 ? -.pi / 2 : .pi / 2
        case .corner:
            tp = Vec2(spot.x - (spot.x > 0 ? 0.6 : -0.6), spot.y - (spot.y > 0 ? 0.6 : -0.6))
            let tgt = Vec2(spot.x * 0.88, 0) - tp; heading = atan2(tgt.y, tgt.x)
        default: tp = spot - Vec2(sign * 0.8, 0)
        }
        players[taker].pos = tp; players[taker].vel = .zero; players[taker].heading = heading
        ball = BallState(position: Vec3(spot.x, PitchSpec.ballRadius, spot.y))
        let wait: Float = kind == .kickoff ? 1.5 : (kind == .penalty ? 2.0 : 1.2)
        phase = .restart(RestartInfo(kind: kind, team: team, spot: spot, taker: taker, elapsed: 0, minWait: wait))
        if teams[team.rawValue].human { teams[team.rawValue].controlled = taker }
        if kind == .corner { stats[team.rawValue].corners += 1 }
        events.append(.restart(kind, team))
    }

    func placeKickoffFormation(kickoffTeam: TeamSide) {
        for i in players.indices where players[i].onPitch {
            let p = players[i]
            var a = anchorWorld(slot: p.slot, side: p.team, ballDepth: 0.5, inPossession: false, ballLat: 0)
            let sign = p.team.attackSign
            if a.x * sign > -0.5 { a.x = -0.5 * sign }
            if p.team != kickoffTeam, simd_length(a) < PitchSpec.centreCircleRadius + 0.5 {
                a = simd_normalize(a + Vec2(-sign * 0.01, 0)) * (PitchSpec.centreCircleRadius + 0.6)
                if a.x * sign > -0.5 { a.x = -0.6 * sign }
            }
            players[i].pos = a; players[i].vel = .zero; players[i].heading = sign > 0 ? 0 : .pi
        }
    }

    // MARK: Step

    public func step(_ inputs: [TeamSide: PlayerInput] = [:]) {
        tick += 1
        let dt = Self.dt
        for t in 0..<2 { teams[t].sinceSwitch += dt }
        switch phase {
        case .playing: if shootoutActive { shootoutPlayStep(dt) } else { playStep(inputs, dt) }
        case .shootout: shootoutPause(dt)
        case .restart(let info): restartStep(info, inputs, dt)
        case .goalCelebration(let rem, let by):
            idleStep(dt)
            let r = rem - dt
            if r <= 0 {
                if clock.isHalfOver { endHalfOrMatch() } else { setupRestart(.kickoff, team: by.opponent, spot: .zero) }
            } else { phase = .goalCelebration(remaining: r, scoredBy: by) }
        case .halfTime(let rem):
            let r = rem - dt
            if r <= 0 { startNextPeriod() } else { phase = .halfTime(remaining: r) }
        case .fullTime:
            idleStep(dt)
        }
    }

    func idleStep(_ dt: Float) {
        for i in players.indices { players[i].desiredDir = .zero; players[i].wantSprint = false; integrate(i, dt); if players[i].celebrate > 0 { players[i].celebrate -= dt } }
        updateBallControl(dt)
        stepBall(dt)
    }

    private func playStep(_ inputs: [TeamSide: PlayerInput], _ dt: Float) {
        clock.tick(dt)
        if clock.addedSeconds == 0, clock.gameSeconds >= clock.nominalEnd - 8 {
            clock.addedSeconds = clock.inExtraTime || clock.half >= 3 ? 30 : max(60, min(300, (60 * (0.5 + stoppageCredit)).rounded()))
        }
        if clock.isHalfOver {
            overtimeReal += dt
            if overtimeReal > 8 || ballOwner == nil || abs(ball.position.x) < 28 { endHalfOrMatch(); return }
        }
        if tick % 6 == 0 { updateContexts() }
        for side in TeamSide.allCases where teams[side.rawValue].human { humanControl(side, inputs[side] ?? PlayerInput(), dt) }
        runAI(dt)
        for i in players.indices { integrate(i, dt) }
        separatePlayers()
        goalkeepersStep(dt)
        updateBallControl(dt)
        autoAerial()
        stepBall(dt)
        updateAdvantage(dt)
        if case .playing = phase { checkBallState() }
        if let o = ballOwner { stats[players[o].team.rawValue].possessionSeconds += dt * clock.timeScale / 15 }
    }

    func endHalfOrMatch() {
        overtimeReal = 0; stoppageCredit = 0; advantage = nil
        let level = score.home == score.away
        switch clock.half {
        case 1: phase = .halfTime(remaining: 10); events.append(.halfTime)
        case 2:
            if config.knockout && level { phase = .halfTime(remaining: 6); events.append(.halfTime) }
            else { phase = .fullTime; events.append(.fullTime) }
        case 3: phase = .halfTime(remaining: 3); events.append(.halfTime)
        default:
            if config.knockout && level { startShootout() } else { phase = .fullTime; events.append(.fullTime) }
        }
        ballOwner = nil
    }

    /// After a break: second half, or extra-time periods (knockout only). Kick-off alternates.
    func startNextPeriod() {
        if clock.half == 1 { clock.startSecondHalf(); setupRestart(.kickoff, team: .away, spot: .zero); return }
        clock.startNextPeriod()
        if clock.half == 3 { events.append(.extraTimeStart) }
        setupRestart(.kickoff, team: clock.half == 3 ? .home : .away, spot: .zero)
    }

    // MARK: Players

    func integrate(_ i: Int, _ dt: Float) {
        guard players[i].onPitch else { return }
        var p = players[i]
        p.kickLock = max(0, p.kickLock - dt); p.tackleCooldown = max(0, p.tackleCooldown - dt)
        p.stun = max(0, p.stun - dt); p.kickAnim = max(0, p.kickAnim - dt); p.tackleAnim = max(0, p.tackleAnim - dt)
        p.fallenTime = max(0, p.fallenTime - dt); p.saveCooldown = max(0, p.saveCooldown - dt)
        p.headAnim = max(0, p.headAnim - dt); p.skillAnim = max(0, p.skillAnim - dt); p.evade = max(0, p.evade - dt); p.skillCooldown = max(0, p.skillCooldown - dt)
        if p.skillAnim <= 0 { p.skillOffset = .zero }
        let a = p.attributes
        if p.diveTime > 0 {
            p.diveTime -= dt
            p.pos += p.vel * dt
            p.vel *= max(0, 1 - 1.8 * dt)
            if p.diveTime <= 0 { p.fallenTime = 0.5 }
        } else if p.slideTime > 0 {
            p.slideTime -= dt
            p.vel = p.slideDir * (9 * max(0, p.slideTime / 0.55) + 1)
            p.pos += p.vel * dt
            if p.slideTime <= 0 { p.stun = 0.6; p.fallenTime = 0.6; p.vel *= 0.3 }
        } else {
            let len = simd_length(p.desiredDir)
            let hasInput = len > 0.05 && p.stun <= 0 && p.fallenTime <= 0
            if p.stamina <= 0 { p.sprintLocked = true }
            if p.stamina > 0.25 { p.sprintLocked = false }
            let sprinting = p.wantSprint && hasInput && !p.sprintLocked
            p.isSprinting = sprinting
            var maxS = sprinting ? a.sprintMS : a.jogMS
            if ballOwner == i { maxS *= a.dribbleFactor }
            if p.role == .gk { maxS *= 0.85 }
            if p.jockey { maxS *= (ballOwner == i ? 0.75 : 0.62) }          // jockey (defending) / shield (carrying)
            maxS *= teamSpeedScale(p.team)
            let dir = hasInput ? p.desiredDir / max(1, len) : .zero
            let desired = dir * maxS * min(1, len)
            let dv = desired - p.vel
            let accelerating = simd_length(desired) >= simd_length(p.vel) - 0.01
            let maxDV = (accelerating ? a.accelMS2 : 22) * dt * (p.stun > 0 ? 0.3 : 1)
            let dl = simd_length(dv)
            p.vel += dl > maxDV ? dv / dl * maxDV : dv
            if p.jockey && ballOwner != i {                       // jockeying defenders keep facing the ball
                let tb = Vec2(ball.position.x, ball.position.z) - p.pos
                var d = atan2(tb.y, tb.x) - p.heading
                while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                let m = a.turnRate * dt; p.heading += max(-m, min(m, d))
            } else if hasInput {
                var d = atan2(dir.y, dir.x) - p.heading
                while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                let m = a.turnRate * dt
                p.heading += max(-m, min(m, d))
            }
            p.pos += p.vel * dt
            if sprinting && simd_length(p.vel) > 1 { p.stamina = max(0, p.stamina - a.sprintDrain * dt) }
            else { p.stamina = min(1, p.stamina + a.staminaRecovery * dt) }
        }
        let lim = Vec2(PitchSpec.halfLength + 4, PitchSpec.halfWidth + 4)
        p.pos = simd_clamp(p.pos, -lim, lim)
        players[i] = p
    }

    func teamSpeedScale(_ side: TeamSide) -> Float { 0.90 + 0.10 * teams[side.rawValue].skill }

    func separatePlayers() {
        let n = players.count
        for i in 0..<n where players[i].onPitch {
            for j in (i + 1)..<n where players[j].onPitch {
                let d = players[j].pos - players[i].pos
                let l = simd_length(d)
                if l < 0.7 && l > 1e-4 {
                    let push = d / l * ((0.7 - l) * 0.5)
                    let si = players[i].isSliding || players[i].isDiving, sj = players[j].isSliding || players[j].isDiving
                    if !si && !sj { players[i].pos -= push; players[j].pos += push }
                }
            }
        }
    }

    // MARK: Ball ownership & dribbling

    func updateBallControl(_ dt: Float) {
        let r = PitchSpec.ballRadius
        let bxz = Vec2(ball.position.x, ball.position.z)
        if let o = ballOwner {
            let p = players[o]
            if p.holdingBall {
                ball.position = Vec3(p.pos.x + p.facing.x * 0.3, 1.0, p.pos.y + p.facing.y * 0.3); ball.velocity = .zero
                return
            }
            if !p.onPitch || p.kickLock > 0 || p.stun > 0 || p.fallenTime > 0 || ball.position.y > 0.75 || simd_distance(bxz, p.pos) > 1.9 {
                ballOwner = nil
            }
        }
        if ballOwner == nil {
            var best = -1; var bestD = Float.infinity
            for i in players.indices {
                let p = players[i]
                guard p.onPitch, p.kickLock <= 0, p.stun <= 0, p.fallenTime <= 0, p.diveTime <= 0, ball.position.y < 0.55 else { continue }
                if case .restart = phase { continue }
                let d = simd_distance(bxz, p.pos)
                let limit: Float = 0.9 + 0.002 * Float(p.attributes.ballControl) + (p.isSliding ? 0.5 : 0)
                let rel = simd_length(ball.horizontalVelocity - p.vel)
                if d < limit, rel < p.attributes.trapLimit, d < bestD { best = i; bestD = d }
            }
            if best >= 0 { takeOwnership(best) }
        }
        if let o = ballOwner {
            let p = players[o]
            let ahead: Float = 0.8 + 0.04 * p.speed
            let right = Vec2(-p.facing.y, p.facing.x)
            let target = p.pos + p.facing * ahead + right * 0.3 + p.skillOffset * min(1, p.skillAnim / 0.25)
            var desired = p.vel + (target - bxz) * 9
            let rel = desired - p.vel
            let rl = simd_length(rel)
            if rl > 7 { desired = p.vel + rel / rl * 7 }
            let k = min(1, p.attributes.dribbleGain * dt)
            let cur = ball.horizontalVelocity
            let nv = cur + (desired - cur) * k
            ball.velocity.x = nv.x; ball.velocity.z = nv.y
            players[o].possessionTime += dt
        }
        // Body collisions for every other player (deflections count as touches).
        for i in players.indices where i != ballOwner && players[i].onPitch {
            let p = players[i]
            if p.role == .gk && p.diveTime > 0 { continue }
            let toBall = bxz - p.pos
            let dist = simd_length(toBall)
            let minDist = 0.42 + r + (p.isSliding ? 0.5 : 0)
            if dist < minDist && ball.position.y < 1.8 && dist > 1e-4 {
                let n = toBall / dist
                ball.position.x += n.x * (minDist - dist); ball.position.z += n.y * (minDist - dist)
                let rel = simd_dot(ball.horizontalVelocity - p.vel, n)
                if rel < 0 {
                    let j = -(1 + 0.35) * rel
                    ball.velocity.x += n.x * j; ball.velocity.z += n.y * j
                    if rel < -1.5 { noteTouch(i) }
                }
            }
        }
    }

    /// An opponent (or any) touch that is not a controlled reception.
    func noteTouch(_ i: Int) {
        if let l = lastTouch, players[l].team != players[i].team { intendedReceiver = nil; pendingOffside = [:] }
        lastTouch = i
    }

    func takeOwnership(_ i: Int) {
        let p = players[i]
        // Offside is judged on the first touch of a player who was in an offside position when the ball was played.
        if pendingTeam == p.team, let pos = pendingOffside[i] {
            pendingOffside = [:]
            callOffside(i, at: pos)
            return
        }
        let prevTeam = lastTouch.map { players[$0].team }
        if let prev = lastTouch {
            if players[prev].team == p.team {
                if intendedReceiver != nil && (prev != i || intendedReceiver == i) && lastKickTeam == p.team {
                    stats[p.team.rawValue].passesCompleted += 1
                    events.append(.passCompleted(from: prev, to: i))
                    if teams[p.team.rawValue].human && teams[p.team.rawValue].controlled == prev && !players[i].role.isGK { switchControl(p.team, to: i) }
                }
            }
        }
        if prevTeam != p.team { events.append(.possession(p.team)) }
        ballOwner = i; lastTouch = i; intendedReceiver = nil; pendingOffside = [:]
        players[i].possessionTime = 0
    }

    func switchControl(_ side: TeamSide, to i: Int) {
        guard teams[side.rawValue].human, teams[side.rawValue].controlled != i else { return }
        teams[side.rawValue].controlled = i; teams[side.rawValue].sinceSwitch = 0
        events.append(.switched(side, to: i))
    }

    // MARK: Ball stepping, goals & out of play

    func stepBall(_ dt: Float) {
        for e in physics.step(&ball, dt: dt) { events.append(.ball(e)) }
    }

    func checkBallState() {
        let side = GoalDetector.side(of: ball)
        if side != 0 {
            let scorer: TeamSide = side > 0 ? .home : .away
            score[scorer] += 1; advantage = nil
            stoppageCredit += 0.5
            phase = .goalCelebration(remaining: 4, scoredBy: scorer)
            if let l = lastTouch { if players[l].team == scorer { players[l].celebrate = 3.5 } }
            events.append(.goal(scorer, scorer: lastTouch))
            ballOwner = nil
        } else if GoalDetector.isOutOfPlay(ball) {
            let team = lastTouch.map { players[$0].team } ?? .home
            let r = Laws.restartAfterBallOut(exit: ball.position, lastTouch: team)
            setupRestart(r.kind, team: r.team, spot: r.spot)
        }
    }

    // MARK: Referee: offside and fouls

    func callOffside(_ i: Int, at pos: Vec2) {
        stats[players[i].team.rawValue].offsides += 1
        events.append(.offside(player: i))
        setupRestart(.indirectFreeKick, team: players[i].team.opponent, spot: pos)
    }

    func callFoul(by i: Int, on o: Int, severity: Float, fromBehind: Bool) {
        let fouler = players[i].team
        let spot = players[o].pos
        stats[fouler.rawValue].fouls += 1
        stoppageCredit += 0.25
        var card: Card?
        let yellowP = 0.05 + 0.35 * severity * (fromBehind ? 1.3 : 1)
        let redP = 0.005 + 0.05 * severity * (fromBehind ? 1.5 : 1)
        let roll = rng.float()
        if roll < redP { card = .red }
        else if roll < yellowP { card = .yellow }
        if card == .yellow {
            players[i].yellowCards += 1
            stats[fouler.rawValue].yellowCards += 1
            if players[i].yellowCards >= 2 { card = .red }
        }
        if card == .red { sendOff(i); stats[fouler.rawValue].redCards += 1 }
        stoppageCredit += card == nil ? 0 : 0.5
        let inBox = Laws.inPenaltyArea(spot, defending: fouler)
        let victim = fouler.opponent
        // Advantage (Law 5): if the fouled side keeps the ball outside the box, play on; the foul is called back if they lose it within ~2 s.
        if !inBox, card != .red, advantage == nil, let owner = ballOwner, players[owner].team == victim {
            advantage = AdvantageState(victim: victim, spot: spot, remaining: 2.2)
            events.append(.foul(by: i, on: o, card: card, penalty: false)); events.append(.advantage(victim))
            return
        }
        players[o].fallenTime = 1.0
        events.append(.foul(by: i, on: o, card: card, penalty: inBox))
        if inBox { setupRestart(.penalty, team: fouler.opponent, spot: Laws.penaltySpot(defending: fouler)) }
        else { setupRestart(.freeKick, team: fouler.opponent, spot: spot) }
    }

    /// A dismissed goalkeeper is replaced by the bench keeper, who takes the place of the team's weakest forward (outfield player if none).
    func replaceKeeper(for side: TeamSide) {
        let cands = players.indices.filter { players[$0].team == side && players[$0].onPitch && players[$0].role != .gk }
        guard let off = cands.filter({ players[$0].role.line == .forward }).min(by: { players[$0].attributes.overall < players[$1].attributes.overall })
                ?? cands.min(by: { players[$0].attributes.overall < players[$1].attributes.overall }) else { return }
        let bench = teams[side.rawValue].setup.players.dropFirst(11).first { $0.role == .gk }
        let oldNumber = players[off].number
        if let b = bench {
            players[off].name = b.name; players[off].number = b.number; players[off].attributes = b.attributes; players[off].appearance = b.appearance
        } else { players[off].attributes.goalkeeping = max(players[off].attributes.goalkeeping, 40) }
        players[off].role = .gk; players[off].stamina = 1
        events.append(.substitution(side, out: oldNumber, in: players[off].number))
    }

    func sendOff(_ i: Int) {
        let keeper = players[i].role == .gk
        defer { if keeper { replaceKeeper(for: players[i].team) } }
        players[i].onPitch = false; players[i].sentOff = true; players[i].pos = Vec2(0, PitchSpec.halfWidth + 8)
        players[i].vel = .zero
        if teams[players[i].team.rawValue].controlled == i { teams[players[i].team.rawValue].controlled = nearestOutfield(players[i].team, to: Vec2(ball.position.x, ball.position.z)) ?? -1 }
    }

    func nearestOutfield(_ side: TeamSide, to p: Vec2, excluding: Int = -1) -> Int? {
        players.indices.filter { players[$0].team == side && players[$0].onPitch && players[$0].role != .gk && $0 != excluding }
            .min(by: { simd_distance(players[$0].pos, p) < simd_distance(players[$1].pos, p) })
    }

    // MARK: Substitutions

    @discardableResult
    public func substitute(_ side: TeamSide, slot: Int, with bench: Int) -> Bool {
        let t = side.rawValue
        guard teams[t].subsUsed < 5, slot > 0, slot < 11, 11 + bench < teams[t].setup.players.count else { return false }
        let prof = teams[t].setup.players[11 + bench]
        let i = t * 11 + slot
        let old = players[i].number
        players[i].name = prof.name; players[i].number = prof.number; players[i].attributes = prof.attributes
        players[i].appearance = prof.appearance; players[i].stamina = 1
        teams[t].subsUsed += 1
        events.append(.substitution(side, out: old, in: prof.number))
        return true
    }
    public func substitutionsUsed(_ side: TeamSide) -> Int { teams[side.rawValue].subsUsed }
}

extension Role { var isGK: Bool { self == .gk } }
