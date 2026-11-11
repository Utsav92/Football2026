import Foundation
import simd
import FootballPhysics

@inline(__always) func rot(_ v: Vec2, _ a: Float) -> Vec2 { let c = cos(a), s = sin(a); return Vec2(c * v.x - s * v.y, s * v.x + c * v.y) }
@inline(__always) func unit(_ v: Vec2) -> Vec2 { let l = simd_length(v); return l > 1e-5 ? v / l : Vec2(1, 0) }

extension MatchSimulation {
    // MARK: Kick primitives

    /// Speed a ground ball needs at the foot to arrive at `arrive` m/s after `d` metres (integrates the real rolling + drag model backwards).
    func groundPassSpeed(distance d: Float, arrive: Float) -> Float {
        let cfg = physics.config
        var v = arrive, x: Float = 0
        let h: Float = 0.01
        while x < d && v < 45 { v += (cfg.rollingDecel + cfg.airDragK * v * v) * h; x += v * h }
        return v
    }

    func kickBall(_ i: Int, velocity v: Vec3, spin: Vec3 = .zero, kind: KickKind, power: Float, target: Int? = nil, countsAsShot: Bool = false) {
        let p = players[i]
        var restartKind: RestartKind?
        if case .restart(let info) = phase { restartKind = info.kind; phase = .playing }
        ball.velocity = v; ball.curveSpin = spin
        if restartKind == .throwIn { ball.position.y = 2.0 }
        players[i].kickLock = kickTuning.lockout; players[i].kickAnim = 0.3; players[i].holdingBall = false
        ballOwner = nil; lastTouch = i; intendedReceiver = target; lastKickTeam = p.team
        pendingOffside = [:]; pendingTeam = p.team
        let free = restartKind == .throwIn || restartKind == .goalKick || restartKind == .corner || restartKind == .kickoff && false
        if !free && !(kind == .shot || countsAsShot) {
            let opp = players.indices.filter { players[$0].team == p.team.opponent && players[$0].onPitch }.map { players[$0].pos.x }
            for j in players.indices where players[j].team == p.team && j != i && players[j].onPitch {
                if Laws.isOffside(receiverX: players[j].pos.x, ballX: ball.position.x, opponentXs: opp, attackSign: p.team.attackSign) {
                    pendingOffside[j] = players[j].pos
                }
            }
        }
        let t = p.team.rawValue
        if kind == .shot || countsAsShot {
            stats[t].shots += 1
            if let c = predictGoalCrossing(towards: p.team.attackSign), abs(c.z) < PitchSpec.goalWidth / 2 && c.y < PitchSpec.goalHeight { stats[t].shotsOnTarget += 1 }
        } else if target != nil { stats[t].passes += 1 }
        events.append(.kick(player: i, kind: kind, power: power))
    }

    func predictGoalCrossing(towards sign: Float, maxT: Float = 2.5) -> (t: Float, z: Float, y: Float)? {
        var b = ball
        let dt: Float = 1.0 / 60, lineX = sign * PitchSpec.halfLength
        var t: Float = 0
        while t < maxT {
            physics.step(&b, dt: dt); t += dt
            if (b.position.x - lineX) * sign >= 0 { return (t, b.position.z, b.position.y) }
            if b.speed < 0.3 && b.position.y < 0.2 { break }
        }
        return nil
    }

    func clampToPitch(_ p: Vec2, margin: Float = 1) -> Vec2 {
        Vec2(max(-PitchSpec.halfLength + margin, min(PitchSpec.halfLength - margin, p.x)),
             max(-PitchSpec.halfWidth + margin, min(PitchSpec.halfWidth - margin, p.y)))
    }

    // MARK: Passing

    /// `human`: stick-assisted passes get a smaller error and a power-driven arrival speed.
    func executePass(_ i: Int, to j: Int, kind: KickKind, power: Float?, human: Bool) {
        let p = players[i], r = players[j]
        let a = p.attributes
        let sign = p.team.attackSign
        var t = simd_distance(r.pos, p.pos) / 14
        var tgt = r.pos + r.vel * t
        if kind == .through { tgt = r.pos + Vec2(sign * 6, 0) + r.vel * (t + 0.4) }
        tgt = clampToPitch(tgt, margin: 0.5)
        let d = simd_distance(tgt, p.pos)
        t = d / 14
        let arrive: Float = kind == .through ? 9 : (power.map { 6 + 8 * $0 } ?? 7.5)
        if kind == .lob { executeLob(i, to: tgt, target: j, human: human, power: power ?? 0.6); return }
        var speed = min(groundPassSpeed(distance: d, arrive: arrive), a.maxPassSpeed)
        var dir = unit(tgt - p.pos)
        let errMul: Float = human ? 0.7 : (2.5 - 1.7 * teams[p.team.rawValue].skill)
        dir = rot(dir, rng.gaussian() * a.passError(long: d > 25) * (1 + d / 30) * errMul)
        speed *= 1 + rng.gaussian() * 0.03
        var v = Vec3(dir.x * speed, 0, dir.y * speed)
        if case .restart(let info) = phase, info.kind == .throwIn { let s = min(speed, 16); v = Vec3(dir.x * s, 4.0, dir.y * s) }
        kickBall(i, velocity: v, kind: kind, power: power ?? 0.5, target: j)
    }

    func executeLob(_ i: Int, to point: Vec2, target: Int?, human: Bool, power: Float, loft: Float = 0.62) {
        let p = players[i]
        let d = max(2, simd_distance(point, p.pos))
        var v = (d * PitchSpec.gravity / sin(2 * loft)).squareRoot() * (1.06 + d * 0.0018)
        v = min(v, p.attributes.maxPassSpeed + 8)
        var dir = unit(point - p.pos)
        let errMul: Float = human ? 0.8 : (2.5 - 1.7 * teams[p.team.rawValue].skill)
        dir = rot(dir, rng.gaussian() * p.attributes.passError(long: true) * (1 + d / 25) * errMul)
        var vel = Vec3(dir.x * v * cos(loft), v * sin(loft), dir.y * v * cos(loft))
        if case .restart(let info) = phase, info.kind == .throwIn { vel = Vec3(dir.x * min(v, 15) * 0.8, 4, dir.y * min(v, 15) * 0.8) }
        kickBall(i, velocity: vel, kind: .lob, power: power, target: target)
    }

    // MARK: Shooting

    func executeShot(_ i: Int, power: Float, aim: Vec2?, human: Bool, finesse: Bool = false) {
        let p = players[i]
        let a = p.attributes
        let sign = p.team.attackSign
        let goalX = sign * PitchSpec.halfLength
        var speed = 13 + (a.maxShotSpeed - 13) * power
        var dirXZ: Vec2
        var vy: Float
        let distGoal = abs(goalX - p.pos.x)
        let facing = aim ?? p.facing
        if human {
            dirXZ = unit(facing)
            if dirXZ.x * sign > 0.05 {
                let t = (goalX - p.pos.x) / dirXZ.x
                let zLine = p.pos.y + dirXZ.y * t
                if abs(zLine) < PitchSpec.goalWidth / 2 + 5 {
                    let aimZ = max(-3.0, min(3.0, zLine))
                    dirXZ = unit(dirXZ * 0.15 + unit(Vec2(goalX - p.pos.x, aimZ - p.pos.y)) * 0.85)
                }
            }
            let loft = 0.04 + 0.13 * power
            vy = speed * sin(loft); speed *= cos(loft)
        } else {
            let gk = players.first(where: { $0.team == p.team.opponent && $0.role == .gk })
            let side: Float = (gk?.pos.y ?? 0) >= 0 ? -1 : 1
            let aimZ = side * rng.range(2.2, 3.4)
            let aimY = rng.range(0.25, distGoal > 18 ? 1.0 : 1.7)
            let hd = simd_distance(Vec2(goalX, aimZ), p.pos)
            var vh = speed
            var tt = hd / vh
            for _ in 0..<2 { vh = speed - 0.5 * physics.config.airDragK * speed * speed * tt; tt = hd / max(vh, 5) }
            dirXZ = unit(Vec2(goalX, aimZ) - p.pos)
            vy = (aimY - PitchSpec.ballRadius) / tt + 0.5 * PitchSpec.gravity * tt
            vy = min(vy, 11)
        }
        // Volley: struck on the full (ball in the air or moving fast just off the ground): harder, but much less accurate.
        let volley = ball.position.y > 0.3 && ball.speed > 5
        if volley { speed *= 1.06 }
        var errMul: Float = human ? 0.8 : (3.2 - 2.2 * teams[p.team.rawValue].skill)
        if volley { errMul *= 1.8 }
        let err = a.shotError * (1 + distGoal / 25) * errMul
        var spin = Vec3.zero
        if finesse && human && distGoal > 8 && dirXZ.x * sign > 0.05 {
            // Finesse: aim just outside the far post and curl back in with sidespin (Magnus force bends the path towards the goal).
            let t = (goalX - p.pos.x) / dirXZ.x
            let zLine = p.pos.y + dirXZ.y * t
            let curlSide: Float = zLine >= 0 ? 1 : -1
            dirXZ = unit(Vec2(goalX - p.pos.x, curlSide * (PitchSpec.goalWidth / 2 + 1.1) - p.pos.y))
            spin = Vec3(0, curlSide * sign * 42, 0)
            speed *= 0.88
        }
        dirXZ = rot(dirXZ, rng.gaussian() * err)
        vy *= 1 + rng.gaussian() * err * 2
        kickBall(i, velocity: Vec3(dirXZ.x * speed, vy, dirXZ.y * speed), spin: spin, kind: volley ? .volley : .shot, power: power, countsAsShot: true)
    }

    // MARK: Tackling

    func attemptTackle(_ i: Int, slide: Bool) {
        guard players[i].tackleCooldown <= 0, players[i].stun <= 0, !players[i].isSliding, players[i].fallenTime <= 0, players[i].role != .gk else { return }
        players[i].tackleAnim = 0.4
        if slide {
            players[i].tackleCooldown = 1.6
            players[i].slideDir = players[i].facing; players[i].slideTime = 0.55
            players[i].vel = players[i].facing * 8
            return
        }
        players[i].tackleCooldown = 0.7
        if let o = ballOwner, players[o].team != players[i].team, simd_distance(players[o].pos, players[i].pos) < 1.35 {
            players[i].tackleCooldown = 1.1
            resolveTackle(i, o, slide: false)
        }
    }

    func slideContact(_ i: Int) {
        guard players[i].isSliding else { return }
        if let o = ballOwner, players[o].team != players[i].team, simd_distance(players[o].pos, players[i].pos) < 1.4 {
            players[i].slideTime = min(players[i].slideTime, 0.25)
            resolveTackle(i, o, slide: true)
        } else if ballOwner == nil, ball.position.y < 0.4, simd_distance(Vec2(ball.position.x, ball.position.z), players[i].pos) < 1.2, players[i].kickLock <= 0 {
            ball.velocity = Vec3(players[i].slideDir.x * 8, 0.5, players[i].slideDir.y * 8)
            noteTouch(i); players[i].kickLock = 0.3
        }
    }

    func resolveTackle(_ i: Int, _ o: Int, slide: Bool) {
        let a = players[i].attributes, d = players[o].attributes
        let atk = 0.55 * Float(a.tackling) + 0.2 * Float(a.strength) + 0.25 * Float(a.defensiveAwareness)
        let def = 0.5 * Float(d.dribbling) + 0.25 * Float(d.balance) + 0.25 * Float(d.strength)
        var pWin = max(0.12, min(0.85, 0.45 + 0.012 * (atk - def - (players[o].jockey ? 18 : 0)) - (slide ? 0.05 : 0)))
        if players[o].evade > 0 { pWin *= 0.35 }          // a skill move beats the challenge
        let toTackler = unit(players[i].pos - players[o].pos)
        let fromBehind = simd_dot(players[o].facing, toTackler) < -0.3
        let t = players[i].team.rawValue
        stats[t].tackles += 1
        if rng.float() < pWin {
            stats[t].tacklesWon += 1
            let f = players[i].facing
            ball.velocity = Vec3(f.x * 4, 0.6, f.y * 4)
            ballOwner = nil; lastTouch = i
            players[o].stun = 0.45; players[o].kickLock = 0.5
            events.append(.tackle(by: i, on: o, won: true))
        } else {
            let foulP = (slide ? 0.5 : 0.16) * (1 - 0.003 * Float(a.defensiveAwareness)) * (fromBehind ? 1.7 : 1)
            events.append(.tackle(by: i, on: o, won: false))
            if rng.float() < foulP { callFoul(by: i, on: o, severity: slide ? 1 : 0.5, fromBehind: fromBehind) }
            else { players[i].stun = max(players[i].stun, 0.4) }
        }
    }

    // MARK: Human control

    func humanControl(_ side: TeamSide, _ input: PlayerInput, _ dt: Float) {
        let ti = side.rawValue
        var c = teams[ti].controlled
        let bxz = Vec2(ball.position.x, ball.position.z)
        if c < 0 || !players[c].onPitch || players[c].role == .gk { c = nearestOutfield(side, to: bxz) ?? c; teams[ti].controlled = c }
        guard c >= 0 else { return }
        let prev = teams[ti].prevInput
        if input.switchPressed && !prev.switchPressed, let n = pickSwitch(side, input.move) {
            switchControl(side, to: n); c = n
        } else if teams[ti].sinceSwitch > 0.8, ballOwner == nil || players[ballOwner!].team != side {
            // Auto-switch to the closest teammate when the ball is clearly nearer to someone else.
            if let n = nearestOutfield(side, to: bxz), n != c,
               simd_distance(players[n].pos, bxz) + 4 < simd_distance(players[c].pos, bxz) { switchControl(side, to: n); c = n }
        }
        var frozen = false
        if case .restart(let info) = phase, info.taker == c { frozen = true }
        for k in players.indices where players[k].team == side && k != c && players[k].state == .controlled { players[k].state = .idle }
        players[c].state = .controlled
        players[c].jockey = input.jockeyHeld
        humanSkill(c, input)
        let len = simd_length(input.move)
        if frozen {
            players[c].desiredDir = .zero
            if len > 0.2 { players[c].heading = atan2(input.move.y, input.move.x) }
        } else {
            players[c].desiredDir = input.move
            players[c].wantSprint = input.sprint
        }
        if input.tackleHeld && !prev.tackleHeld { attemptTackle(c, slide: false) }
        if input.slideHeld && !prev.slideHeld { attemptTackle(c, slide: true) }
        if players[c].isSliding { slideContact(c) }

        // Buffered kick: fire as soon as the ball is within range, drop it when the window expires.
        if var pk = teams[ti].pendingKick {
            pk.remaining -= dt
            let bxz2 = Vec2(ball.position.x, ball.position.z)
            if simd_distance(bxz2, players[c].pos) < kickTuning.range, ball.position.y < 1.0 { teams[ti].pendingKick = nil; humanKick(c, pk.kind, power: pk.power, input: pk.input) }
            else if pk.remaining <= 0 { teams[ti].pendingKick = nil } else { teams[ti].pendingKick = pk }
        }
        // Charged kicks
        let k = kickTuning
        if teams[ti].charge == nil {
            if input.passHeld && !prev.passHeld { teams[ti].charge = KickCharge(kind: .pass, time: 0, level: 0) }
            else if input.throughHeld && !prev.throughHeld { teams[ti].charge = KickCharge(kind: .through, time: 0, level: 0) }
            else if input.lobHeld && !prev.lobHeld { teams[ti].charge = KickCharge(kind: .lob, time: 0, level: 0) }
            else if input.shootHeld && !prev.shootHeld { teams[ti].charge = KickCharge(kind: .shot, time: 0, level: 0) }
        } else if var ch = teams[ti].charge {
            ch.time += dt; ch.level = min(1, ch.time / k.chargeTime)
            let held: Bool
            switch ch.kind { case .pass: held = input.passHeld; case .through: held = input.throughHeld; case .lob: held = input.lobHeld; case .shot: held = input.shootHeld; case .header, .volley: held = false }
            if held { teams[ti].charge = ch }
            else { teams[ti].charge = nil; humanKick(c, ch.kind, power: k.minPower + (1 - k.minPower) * ch.level, input: input) }
        }
        teams[ti].prevInput = input
    }

    func pickSwitch(_ side: TeamSide, _ stick: Vec2) -> Int? {
        let cur = teams[side.rawValue].controlled
        let bxz = Vec2(ball.position.x, ball.position.z)
        let cands = players.indices.filter { players[$0].team == side && players[$0].onPitch && players[$0].role != .gk && $0 != cur }
        return cands.min(by: { a, b in
            func score(_ k: Int) -> Float {
                var s = simd_distance(players[k].pos, bxz)
                if simd_length(stick) > 0.3 { s -= 6 * simd_dot(unit(players[k].pos - players[cur].pos), unit(stick)) }
                return s
            }
            return score(a) < score(b)
        })
    }

    func humanKick(_ c: Int, _ kind: KickKind, power: Float, input: PlayerInput) {
        let p = players[c]
        let bxz = Vec2(ball.position.x, ball.position.z)
        if ball.position.y >= 1.0, ball.position.y < 2.3, simd_distance(bxz, p.pos) < 1.2, p.role != .gk, p.kickLock <= 0 {
            performHeader(c, human: true, aim: simd_length(input.move) > 0.3 ? unit(input.move) : p.facing, shot: kind == .shot, power: power)
            return
        }
        guard simd_distance(bxz, p.pos) < kickTuning.range, ball.position.y < 1.0 else {
            // Input buffering: remember the request for a short window so an early press still counts when the ball arrives.
            teams[p.team.rawValue].pendingKick = PendingKick(kind: kind, power: power, input: input, remaining: kickTuning.bufferWindow)
            return
        }
        teams[p.team.rawValue].pendingKick = nil
        let dir = simd_length(input.move) > 0.3 ? unit(input.move) : p.facing
        let sign = p.team.attackSign
        switch kind {
        case .shot: executeShot(c, power: power, aim: dir, human: true, finesse: input.finesseHeld)
        case .header, .volley: break
        case .pass, .through, .lob:
            var best = -1; var bestS = -Float.infinity
            for pass in 0..<2 {
                for j in players.indices where players[j].team == p.team && j != c && players[j].onPitch && players[j].role != .gk {
                    let v = players[j].pos - p.pos
                    let d = simd_length(v)
                    guard d > 3, d < 50 else { continue }
                    let cs = simd_dot(v / d, dir)
                    guard cs > (pass == 0 ? 0.75 : 0.5) else { continue }
                    var s = cs * 2 - d / 40
                    if kind == .through { s += (v.x * sign) / 25 }
                    if s > bestS { bestS = s; best = j }
                }
                if best >= 0 { break }
            }
            if best >= 0 { executePass(c, to: best, kind: kind, power: power, human: true) }
            else if kind == .lob {
                executeLob(c, to: clampToPitch(p.pos + dir * (10 + 30 * power)), target: nil, human: true, power: power)
            } else {
                let speed = 8 + 14 * power
                var v = Vec3(dir.x * speed, 0, dir.y * speed)
                if case .restart(let info) = phase, info.kind == .throwIn { v = Vec3(dir.x * min(speed, 14), 4, dir.y * min(speed, 14)) }
                kickBall(c, velocity: v, kind: kind, power: power, target: nil)
            }
        }
    }

    // MARK: Restart handling

    func restartStep(_ infoIn: RestartInfo, _ inputs: [TeamSide: PlayerInput], _ dt: Float) {
        var info = infoIn
        info.elapsed += dt
        phase = .restart(info)
        if tick % 6 == 0 { updateContexts() }
        for side in TeamSide.allCases where teams[side.rawValue].human { humanControl(side, inputs[side] ?? PlayerInput(), dt) }
        // Taker is rooted at the spot; everyone else follows set-piece positioning.
        for i in players.indices where players[i].onPitch {
            if i == info.taker { players[i].desiredDir = .zero; players[i].state = .setPiece; continue }
            if teams[players[i].team.rawValue].controlled == i && teams[players[i].team.rawValue].human { continue }
            if shootoutActive && players[i].role != .gk { players[i].desiredDir = .zero; players[i].state = .idle; continue }
            setPieceThink(i, info)
        }
        for i in players.indices { integrate(i, dt) }
        enforceRestartConstraints(info)
        separatePlayers()
        goalkeepersStep(dt)
        // Hold the ball on its spot until it is kicked.
        if case .restart = phase {
            ball.position = Vec3(info.spot.x, PitchSpec.ballRadius, info.spot.y); ball.velocity = .zero
            let taker = players[info.taker]
            let humanTaker = teams[taker.team.rawValue].human
            let limit: Float = humanTaker ? 9 : 0
            if info.elapsed >= info.minWait && (!humanTaker || info.elapsed >= limit) { aiTakeRestart(info) }
        }
    }

    func enforceRestartConstraints(_ info: RestartInfo) {
        let spot = info.spot
        let opp = info.team.opponent
        for i in players.indices where players[i].onPitch && i != info.taker {
            var p = players[i].pos
            switch info.kind {
            case .corner, .freeKick, .indirectFreeKick:
                if players[i].team == opp {
                    let d = simd_distance(p, spot)
                    if d < Laws.wallDistance {
                        p = spot + unit(p - spot) * (Laws.wallDistance + 0.05)
                    }
                }
            case .goalKick:
                if players[i].team == opp && Laws.inPenaltyArea(p, defending: info.team) {
                    p.x = info.team.attackSign * (-PitchSpec.halfLength + PitchSpec.penaltyAreaDepth + 1)
                }
            case .kickoff:
                let s = players[i].team.attackSign
                if p.x * s > -0.3 { p.x = -0.3 * s }
                if players[i].team == opp, simd_length(p) < Laws.wallDistance { p = unit(p) * (Laws.wallDistance + 0.1); if p.x * s > -0.3 { p.x = -0.3 * s } }
            case .penalty:
                let defending = opp
                let isGK = players[i].role == .gk && players[i].team == defending
                if isGK { p = Vec2(defending.attackSign * (-PitchSpec.halfLength + 0.3), max(-3.5, min(3.5, p.y))) }
                else {
                    let ps = Laws.penaltySpot(defending: defending)
                    let outside = defending == .home ? ps.x + 0.01 : ps.x - 0.01
                    // Everyone else stays outside the box and at least 9.15 m from the spot.
                    if Laws.inPenaltyArea(p, defending: defending) || simd_distance(p, ps) < Laws.wallDistance {
                        let dirOut: Float = defending == .home ? 1 : -1
                        p.x = (defending == .home ? -1 : 1) * (PitchSpec.halfLength - PitchSpec.penaltyAreaDepth) + dirOut * 1.5
                        _ = outside
                    }
                }
            case .throwIn: break
            }
            players[i].pos = p
        }
    }
}

extension MatchSimulation {
    // MARK: Skill moves (right stick)
    /// Feint / drag-back / side-step. Each gives a short window where tackles on the carrier mostly fail (`evade`).
    func humanSkill(_ c: Int, _ input: PlayerInput) {
        guard ballOwner == c, players[c].skillCooldown <= 0, simd_length(input.skill) > 0.7 else { return }
        let d = unit(input.skill)
        let f = players[c].facing, right = Vec2(-f.y, f.x)
        let dotF = simd_dot(d, f), dotR = simd_dot(d, right)
        if dotF > 0.6 {                                    // step-over feint, small burst
            players[c].vel += f * 1.2
        } else if dotF < -0.6 {                            // drag back
            players[c].skillOffset = -f * 1.25
            players[c].vel *= 0.4
        } else {                                           // side-step
            let side: Float = dotR >= 0 ? 1 : -1
            players[c].skillOffset = right * side * 1.5
            players[c].vel += right * side * 2.2
        }
        players[c].evade = 0.6; players[c].skillAnim = 0.45; players[c].skillCooldown = 1.0
        events.append(.skillMove(player: c))
    }

    // MARK: Headers
    /// Aerial contact. `shot` heads towards goal, otherwise a header pass / clearance.
    func performHeader(_ i: Int, human: Bool, aim: Vec2?, shot: Bool?, power: Float) {
        let p = players[i]
        let sign = p.team.attackSign
        let a = p.attributes
        let goal = Vec2(sign * PitchSpec.halfLength, 0)
        let distGoal = simd_distance(goal, p.pos)
        let incoming = ball.horizontalVelocity
        var dir = aim ?? p.facing
        let wantShot = shot ?? (distGoal < 17 && (goal.x - p.pos.x) * sign > 0)
        var target: Int?
        var speed = min(17, max(6, simd_length(incoming) * 0.55 + 6)) * (0.9 + 0.2 * Float(a.strength) / 100) * (0.6 + 0.8 * power)
        var vy: Float
        if wantShot {
            let aimZ = max(-3.0, min(3.0, p.pos.y * 0.3)) + rng.range(-1.2, 1.2)
            dir = unit(Vec2(goal.x - p.pos.x, aimZ - p.pos.y))
            speed = min(21, speed * 1.25 + 3)
            vy = -1.2
        } else {
            if !human, let opt = bestPassOption(i) { target = opt.target; dir = unit(players[opt.target].pos - p.pos); speed = min(14, simd_distance(players[opt.target].pos, p.pos) * 0.7 + 4) }
            else if !human { dir = Vec2(sign, p.pos.y >= 0 ? 0.6 : -0.6); dir = unit(dir); speed = 13 }
            vy = 3.2
        }
        let err = a.shotError * 1.6 * (human ? 0.9 : (2.4 - 1.4 * teams[p.team.rawValue].skill))
        dir = rot(dir, rng.gaussian() * err * (wantShot ? 1 : 0.7))
        kickBall(i, velocity: Vec3(dir.x * speed, vy, dir.y * speed), kind: .header, power: power, target: target, countsAsShot: wantShot)
        players[i].headAnim = 0.6; players[i].kickAnim = 0
    }

    /// Automatic aerial contests: the best-placed player (strength, balance, closeness) heads a ball arriving at head height.
    func autoAerial() {
        guard ball.position.y >= 1.0, ball.position.y < 2.3, ball.speed > 1.5, ballOwner == nil else { return }
        let bxz = Vec2(ball.position.x, ball.position.z)
        var best = -1; var bestScore = -Float.infinity
        for i in players.indices {
            let p = players[i]
            guard p.onPitch, p.role != .gk, p.kickLock <= 0, p.stun <= 0, p.fallenTime <= 0, !p.isSliding else { continue }
            let d = simd_distance(bxz, p.pos)
            guard d < 0.8 else { continue }
            let t = teams[p.team.rawValue]
            if t.human && t.controlled == i && (t.prevInput.passHeld || t.prevInput.shootHeld || t.prevInput.lobHeld || t.prevInput.throughHeld) { continue }   // the human's press handles it
            let score = Float(p.attributes.strength) * 0.5 + Float(p.attributes.balance) * 0.3 + Float(p.attributes.positioning) * 0.2 - d * 25
            if score > bestScore { bestScore = score; best = i }
        }
        guard best >= 0 else { return }
        let human = teams[players[best].team.rawValue].human && teams[players[best].team.rawValue].controlled == best
        performHeader(best, human: human, aim: nil, shot: nil, power: 0.6)
    }
}
