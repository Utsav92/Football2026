import Foundation
import simd
import FootballPhysics

/// Tactical AI: team contexts, hierarchical decisions (team state -> role behaviour -> utility choice), steering.
/// Every decision records `state`, `target` and `reason` so the debug overlay and tests can explain it.
extension MatchSimulation {
    // MARK: Team context

    func predictBallXZ(_ t: Float) -> Vec2 {
        let k: Float = 0.3
        let v = ball.horizontalVelocity
        return Vec2(ball.position.x, ball.position.z) + v * ((1 - exp(-k * t)) / k)
    }

    func timeToBall(_ i: Int) -> Float {
        let p = players[i]
        let sp = max(3, p.attributes.sprintMS * 0.95)
        var t: Float = 0
        for _ in 0..<3 { let d = max(0, simd_distance(p.pos, predictBallXZ(t)) - 0.6); t = d / sp + 0.15 }
        return t
    }

    func updateContexts() {
        let ownerTeam = ballOwner.map { players[$0].team }
        let lastTeam = lastTouch.map { players[$0].team }
        for side in TeamSide.allCases {
            let ti = side.rawValue, sign = side.attackSign
            var c = TeamContext()
            if let o = ballOwner, ownerTeam == side { c.carrier = o }
            c.inPossession = ownerTeam == side || (ownerTeam == nil && lastTeam == side && intendedReceiver != nil)
            c.ballDepth = max(0, min(1, (ball.position.x * sign + PitchSpec.halfLength) / PitchSpec.length))
            c.ballLat = max(-1, min(1, ball.position.z * sign / PitchSpec.halfWidth))
            let oppA = players.indices.filter { players[$0].team == side.opponent && players[$0].onPitch }
                .map { players[$0].pos.x * sign }.sorted(by: >)
            c.offsideLine = max(oppA.count >= 2 ? oppA[1] : 0, ball.position.x * sign, 0)
            var ranked: [(Int, Float)] = []
            for i in players.indices where players[i].team == side && players[i].onPitch && players[i].role != .gk {
                ranked.append((i, timeToBall(i)))
            }
            ranked.sort { $0.1 < $1.1 }
            c.chaser = ranked.first?.0 ?? -1
            c.second = ranked.count > 1 ? ranked[1].0 : -1
            teams[ti].ctx = c
        }
        assignMarking()
    }

    /// Greedy man-marking: most dangerous opponents (closest to my goal) get the nearest free defender/midfielder.
    func assignMarking() {
        for side in TeamSide.allCases {
            let ctx = teams[side.rawValue].ctx
            let sign = side.attackSign
            for i in players.indices where players[i].team == side { players[i].markTarget = -1 }
            guard !ctx.inPossession else { continue }
            let ownGoal = Vec2(-sign * PitchSpec.halfLength, 0)
            let threats = players.indices.filter { players[$0].team == side.opponent && players[$0].onPitch && players[$0].role != .gk && $0 != ballOwner }
                .sorted { simd_distance(players[$0].pos, ownGoal) < simd_distance(players[$1].pos, ownGoal) }.prefix(6)
            var free = players.indices.filter {
                players[$0].team == side && players[$0].onPitch && $0 != ctx.chaser && players[$0].role.line != .goalkeeper
                    && players[$0].role.line != .forward && !(teams[side.rawValue].human && teams[side.rawValue].controlled == $0)
            }
            for o in threats {
                guard !free.isEmpty else { break }
                let anchorBall = ctx
                var bestJ = -1; var bestD = Float.infinity
                for j in free {
                    let a = anchorWorld(slot: players[j].slot, side: side, ballDepth: anchorBall.ballDepth, inPossession: false, ballLat: anchorBall.ballLat)
                    let d = simd_distance(a, players[o].pos)
                    if d < bestD { bestD = d; bestJ = j }
                }
                if bestJ >= 0 && bestD < 18 { players[bestJ].markTarget = o; free.removeAll { $0 == bestJ } }
            }
        }
    }

    // MARK: AI driver

    func runAI(_ dt: Float) {
        for i in players.indices where players[i].onPitch && players[i].role != .gk {
            let side = players[i].team
            if teams[side.rawValue].human && teams[side.rawValue].controlled == i { continue }
            if (tick + players[i].thinkOffset) % 6 == 0 { aiThink(i) }
            steer(i)
            if players[i].isSliding { slideContact(i) }
        }
    }

    func steer(_ i: Int) {
        let p = players[i]
        let to = p.target - p.pos
        let d = simd_length(to)
        var dir = d > 0.25 ? to / d : Vec2.zero
        dir *= min(1, d / 1.5)
        var sep = Vec2.zero
        for j in players.indices where j != i && players[j].team == p.team && players[j].onPitch {
            let dd = p.pos - players[j].pos
            let l = simd_length(dd)
            if l < 4 && l > 0.01 { sep += dd / l * ((4 - l) / 4) }
        }
        var out = dir + sep * 0.5
        let l = simd_length(out)
        if l > 1 { out /= l }
        if d < 0.25 && l < 0.15 {
            out = .zero
            let toBall = Vec2(ball.position.x, ball.position.z) - p.pos
            if simd_length(toBall) > 0.5 {
                var dh = atan2(toBall.y, toBall.x) - p.heading
                while dh > .pi { dh -= 2 * .pi }; while dh < -.pi { dh += 2 * .pi }
                players[i].heading += max(-0.08, min(0.08, dh * 0.2))
            }
        }
        players[i].desiredDir = out
    }

    func setT(_ i: Int, _ target: Vec2, _ state: AIState, sprint: Bool, _ why: String) {
        players[i].target = clampToPitch(target, margin: 0.3); players[i].state = state
        players[i].wantSprint = sprint; players[i].reason = why
    }

    // MARK: Decisions

    func aiThink(_ i: Int) {
        let p = players[i]
        if p.stun > 0 || p.isSliding || p.fallenTime > 0 { return }
        let side = p.team
        let ctx = teams[side.rawValue].ctx
        if ballOwner == i { carrierThink(i); return }
        if intendedReceiver == i, ballOwner == nil {
            let t = timeToBall(i)
            setT(i, predictBallXZ(t), .intercepting, sprint: true, "receive pass")
            return
        }
        let ownerTeam = ballOwner.map { players[$0].team }
        if ctx.inPossession { attackThink(i, ctx) }
        else if ownerTeam == side.opponent { defendThink(i, ctx) }
        else { looseBallThink(i, ctx) }
    }

    func positionThink(_ i: Int, _ ctx: TeamContext, possession: Bool) {
        let p = players[i]
        let a = anchorWorld(slot: p.slot, side: p.team, ballDepth: ctx.ballDepth, inPossession: possession, ballLat: ctx.ballLat)
        let behind = (a.x - p.pos.x) * p.team.attackSign < -12
        if !possession && simd_distance(a, p.pos) > 10 && behind { setT(i, a, .recovering, sprint: true, "recover to shape") }
        else { setT(i, a, .positioning, sprint: simd_distance(a, p.pos) > 14, "hold formation") }
    }

    func looseBallThink(_ i: Int, _ ctx: TeamContext) {
        if ctx.chaser == i {
            let t = timeToBall(i)
            setT(i, predictBallXZ(t), .intercepting, sprint: true, "closest to loose ball")
        } else { positionThink(i, ctx, possession: false) }
    }

    func defendThink(_ i: Int, _ ctx: TeamContext) {
        let p = players[i]
        let side = p.team
        let sign = side.attackSign
        let tac = teams[side.rawValue].setup.tactics
        guard let o = ballOwner else { return }
        let owner = players[o]
        let ownGoal = Vec2(-sign * PitchSpec.halfLength, 0)
        let skill = teams[side.rawValue].skill
        let pressLine = 0.45 + 0.5 * tac.pressing
        if ctx.chaser == i {
            let d = simd_distance(p.pos, owner.pos)
            let goalSide = unit(ownGoal - owner.pos)
            if ctx.ballDepth > pressLine {
                setT(i, owner.pos + goalSide * 4, .pressing, sprint: false, "contain: ball beyond press line")
            } else if d > 3 {
                setT(i, owner.pos + owner.vel * 0.25 + goalSide * 1.0, .pressing, sprint: d > 5, "press carrier")
            } else {
                setT(i, owner.pos + owner.vel * 0.15, .tackling, sprint: false, "close down & tackle")
                if d < 1.3 && p.tackleCooldown <= 0 && rng.float() < 0.5 * skill * (0.5 + 0.5 * Float(p.attributes.defensiveAwareness) / 100) {
                    attemptTackle(i, slide: d > 1.1 && rng.float() < 0.1)
                }
            }
            return
        }
        if ctx.second == i && tac.pressing > 0.55 && ctx.ballDepth <= pressLine && p.role.line != .goalkeeper {
            // Cut the passing lane to the most advanced opponent.
            let mates = players.indices.filter { players[$0].team == side.opponent && players[$0].onPitch && $0 != o && players[$0].role != .gk }
            if let m = mates.min(by: { simd_distance(players[$0].pos, ownGoal) < simd_distance(players[$1].pos, ownGoal) }) {
                setT(i, owner.pos + (players[m].pos - owner.pos) * 0.4, .pressing, sprint: true, "cover: cut lane")
                return
            }
        }
        if p.markTarget >= 0, players[p.markTarget].onPitch {
            let m = players[p.markTarget]
            let goalSide = unit(ownGoal - m.pos)
            let toBall = unit(owner.pos - m.pos)
            setT(i, m.pos + goalSide * 1.4 + toBall * 0.5, .marking, sprint: simd_distance(p.pos, m.pos) > 10, "mark #\(m.number)")
            return
        }
        positionThink(i, ctx, possession: false)
    }

    func attackThink(_ i: Int, _ ctx: TeamContext) {
        let p = players[i]
        let side = p.team, sign = side.attackSign
        let anchor = anchorWorld(slot: p.slot, side: side, ballDepth: ctx.ballDepth, inPossession: true, ballLat: ctx.ballLat)
        guard ctx.carrier >= 0 else { positionThink(i, ctx, possession: true); return }
        let c = players[ctx.carrier]
        let line = p.role.line
        if line == .goalkeeper { return }
        let myLatSign: Float = (p.role == .lb || p.role == .lm || p.role == .lw) ? -1 : ((p.role == .rb || p.role == .rm || p.role == .rw) ? 1 : 0)
        // How many teammates are closer to the carrier? The two closest give close support.
        var rank = 0
        let dC = simd_distance(p.pos, c.pos)
        for j in players.indices where j != i && j != ctx.carrier && players[j].team == side && players[j].onPitch && players[j].role != .gk {
            if simd_distance(players[j].pos, c.pos) < dC { rank += 1 }
        }
        let carrierWide: Float = c.pos.y * sign > 8 ? 1 : (c.pos.y * sign < -8 ? -1 : 0)
        // Overlapping run by the full-back behind a winger.
        if (p.role == .lb || p.role == .rb), carrierWide != 0, carrierWide == myLatSign, (c.pos.x - p.pos.x) * sign < 12, c.role.isWide {
            setT(i, Vec2(c.pos.x + sign * 9, sign * myLatSign * (PitchSpec.halfWidth - 4)), .supporting, sprint: true, "overlap run")
            return
        }
        let aOffside = ctx.offsideLine
        if line == .forward || p.role == .am {
            var a = max(anchor.x * sign, c.pos.x * sign + 10)
            a = min(a, aOffside - 0.8)
            var z = anchor.y
            if ctx.ballDepth > 0.62 { z = z * 0.4 + (rng.float() < 0.5 ? 0 : 0) + (z >= 0 ? 4 : -4) * 0.5 }
            setT(i, Vec2(a * sign, z), .supporting, sprint: true, ctx.ballDepth > 0.62 ? "diagonal run into box" : "run in behind (onside)")
            return
        }
        if rank < 2 && line != .defender {
            let side2: Float = (i % 2 == 0) ? 1 : -1
            let open = openSide(from: c.pos, preferred: side2)
            setT(i, Vec2(c.pos.x + sign * 5, c.pos.y + open * 9), .supporting, sprint: dC > 12, "support carrier")
            return
        }
        // Width for wide midfielders.
        if p.role.isWide { var t = anchor; t.y = (t.y >= 0 ? 1 : -1) * PitchSpec.halfWidth * 0.82; setT(i, t, .supporting, sprint: false, "hold width"); return }
        positionThink(i, ctx, possession: true)
    }

    func openSide(from p: Vec2, preferred: Float) -> Float {
        func crowd(_ s: Float) -> Float {
            players.indices.reduce(0) { acc, j in
                guard players[j].onPitch else { return acc }
                let q = players[j].pos
                return acc + (simd_distance(q, p + Vec2(0, s * 9)) < 8 ? 1 : 0)
            }
        }
        let a = crowd(preferred), b = crowd(-preferred)
        return a <= b ? preferred : -preferred
    }

    // MARK: Ball carrier

    func nearestOpponentDistance(to p: Vec2, of side: TeamSide) -> Float {
        var m = Float.infinity
        for j in players.indices where players[j].team != side && players[j].onPitch { m = min(m, simd_distance(players[j].pos, p)) }
        return m
    }

    func laneRisk(_ a: Vec2, _ b: Vec2, side: TeamSide) -> Float {
        let ab = b - a
        let len2 = max(simd_dot(ab, ab), 1e-4), len = len2.squareRoot()
        var risk: Float = 0
        for j in players.indices where players[j].team != side && players[j].onPitch {
            let o = players[j]
            let s = max(0, min(1, simd_dot(o.pos - a, ab) / len2))
            let q = a + ab * s
            let dq = simd_distance(o.pos, q)
            if dq > 3.5 { continue }
            let tBall = s * len / 13
            let tOpp = max(0, dq - 0.5) / max(3, o.attributes.sprintMS * 0.9) + 0.2
            if tOpp < tBall + 0.2 { risk = max(risk, 1 - dq / 3.5) }
        }
        return risk
    }

    struct PassOption { var target: Int; var kind: KickKind; var utility: Float }

    func bestPassOption(_ i: Int, long: Bool = false) -> PassOption? {
        let p = players[i]
        let side = p.team, sign = side.attackSign
        let tac = teams[side.rawValue].setup.tactics
        let pressure = nearestOpponentDistance(to: p.pos, of: side)
        var best: PassOption?
        for j in players.indices where players[j].team == side && j != i && players[j].onPitch {
            let r = players[j]
            let d = simd_distance(r.pos, p.pos)
            guard d > 4, d < 48 else { continue }
            if r.role == .gk && !(pressure < 3 && p.pos.x * sign < -10) { continue }
            let progress = (r.pos.x - p.pos.x) * sign
            let progN = max(-0.4, min(1, progress / 25))
            let risk = laneRisk(p.pos, r.pos, side: side)
            let open = min(10, nearestOpponentDistance(to: r.pos, of: side)) / 10
            var u = 0.35 * progN * (0.6 + 0.8 * tac.directness) + 0.3 * open + 0.3 * (1 - risk) + 0.1
            if d > 12 { u -= 0.016 * (d - 12) }
            if risk > 0.45 && pressure > 2.5 { continue }
            if r.pos.x * sign > PitchSpec.halfLength - 20 { u += 0.15 }
            if progress < -5 { u -= pressure < 2.5 ? -0.05 : 0.08 }
            if long { u += d > 25 ? 0.2 : -0.1 }
            var kind: KickKind = .pass
            if progress > 10 && risk < 0.35 && simd_dot(r.vel, Vec2(sign, 0)) > 2 && r.role.line != .defender { kind = .through }
            else if (risk > 0.5 && open > 0.5 && p.attributes.longPassing > 45) || d > 32 { kind = .lob; if risk > 0.5 { u -= 0.1 } }
            u *= (1 - 0.85 * risk)
            // Race to the ball: can an opponent reach the receiving point before the receiver does?
            let nearOpp = nearestOpponentDistance(to: r.pos, of: side)
            u *= min(1, 0.45 + 0.22 * nearOpp)
            var fastestOpp = Float.infinity
            for o in players.indices where players[o].team != side && players[o].onPitch {
                fastestOpp = min(fastestOpp, max(0, simd_distance(players[o].pos, r.pos) - 0.6) / max(3, players[o].attributes.sprintMS * 0.9))
            }
            let recvT = simd_distance(r.pos, r.pos + r.vel * 0.5) / max(3, r.attributes.sprintMS) + d / 15
            if fastestOpp < recvT * 0.5 && nearOpp < 3 { u *= 0.5 }
            u *= 0.7 + 0.3 * Float(kind == .lob ? p.attributes.longPassing : p.attributes.shortPassing) / 100
            if best == nil || u > best!.utility { best = PassOption(target: j, kind: kind, utility: u) }
        }
        return best
    }

    func shootUtility(_ i: Int) -> Float {
        let p = players[i], sign = p.team.attackSign
        let goal = Vec2(sign * PitchSpec.halfLength, 0)
        let dist = simd_distance(goal, p.pos)
        guard dist < 32, (goal.x - p.pos.x) * sign > 0 else { return 0 }
        let xg = TacticalPriors.xG(dx: abs(goal.x - p.pos.x), dy: p.pos.y)
        let block = laneRisk(p.pos, goal, side: p.team)
        return 2.4 * xg * (1 - 0.6 * block) * (0.6 + 0.4 * Float(p.attributes.shootingAccuracy) / 100)
    }

    func carrierThink(_ i: Int) {
        let p = players[i]
        let side = p.team, sign = side.attackSign
        let skill = teams[side.rawValue].skill
        let pressure = nearestOpponentDistance(to: p.pos, of: side)
        let delay = p.attributes.decisionDelay * (2.2 - 1.3 * skill)
        let goal = Vec2(sign * PitchSpec.halfLength, 0)
        // Dribble direction: towards goal, repelled by nearby opponents ahead.
        var rep = Vec2.zero
        var free: Float = 12
        let aimDir = unit(Vec2(goal.x - p.pos.x, p.pos.y * -0.25))
        for j in players.indices where players[j].team != side && players[j].onPitch {
            let d = simd_distance(players[j].pos, p.pos)
            if d < 8 { let u = unit(players[j].pos - p.pos); if simd_dot(u, aimDir) > 0.2 { rep -= u * (1 - d / 8); free = min(free, d) } }
        }
        var dir = unit(aimDir + rep * 1.6)
        if abs(p.pos.y) > PitchSpec.halfWidth - 4 { dir.y -= (p.pos.y > 0 ? 1 : -1) * 0.8; dir = unit(dir) }
        if p.possessionTime < (pressure < 2.5 ? 0.1 : delay) {
            setT(i, p.pos + dir * 8, .dribbling, sprint: false, "control & look")
            return
        }
        let shoot = shootUtility(i)
        let pass = bestPassOption(i, long: p.pos.x * sign < -25 && pressure < 3)
        let dribble = 0.15 + 0.35 * (free / 12) * (0.5 + Float(p.attributes.dribbling) / 100)
        let noise = rng.gaussian() * 0.1 * (1 - skill)
        let passU = (pass?.utility ?? 0) + noise
        let distGoal = simd_distance(goal, p.pos)
        if shoot >= 0.28 || shoot >= max(0.12, passU * 0.7) || (shoot > 0.05 && pressure < 1.8 && distGoal < 25 && passU < 0.4) {
            setT(i, goal, .shooting, sprint: false, "shot (xG-utility \(String(format: "%.2f", shoot)))")
            executeShot(i, power: rng.range(0.7, 1.0), aim: nil, human: false)
            return
        }
        if let pass, passU > dribble && passU > 0.3 || (pressure < 1.6 && passU > 0.2) {
            setT(i, players[pass.target].pos, .passing, sprint: false, "pass \(pass.kind) to #\(players[pass.target].number) (u \(String(format: "%.2f", passU)))")
            executePass(i, to: pass.target, kind: pass.kind, power: nil, human: false)
            return
        }
        if pressure < 2 && p.pos.x * sign < -PitchSpec.halfLength + 25 {
            let tgt = Vec2(p.pos.x + sign * 32, p.pos.y >= 0 ? 26 : -26)
            setT(i, tgt, .passing, sprint: false, "clearance")
            executeLob(i, to: clampToPitch(tgt), target: nil, human: false, power: 0.8)
            return
        }
        setT(i, p.pos + dir * 8, .dribbling, sprint: free > 6 && p.stamina > 0.3, "dribble (space \(String(format: "%.1f", free))m)")
    }

    // MARK: Set pieces

    func setPieceThink(_ i: Int, _ info: RestartInfo) {
        let p = players[i]
        let side = p.team
        let sign = side.attackSign
        let attacking = side == info.team
        var ctx = teams[side.rawValue].ctx
        let spotDepth = max(0, min(1, (info.spot.x * sign + PitchSpec.halfLength) / PitchSpec.length))
        ctx.ballDepth = spotDepth; ctx.ballLat = max(-1, min(1, info.spot.y * sign / PitchSpec.halfWidth))
        var t = anchorWorld(slot: p.slot, side: side, ballDepth: spotDepth, inPossession: attacking, ballLat: ctx.ballLat)
        let goalX = (attacking ? sign : -sign) * PitchSpec.halfLength     // the goal being attacked at this set piece
        let attackGoalX = info.team.attackSign * PitchSpec.halfLength
        let slot = p.slot
        if p.role == .gk { if p.team != info.team || info.kind != .goalKick { t = anchorWorld(slot: slot, side: side, ballDepth: spotDepth, inPossession: false, ballLat: 0) }; players[i].desiredDir = .zero }
        switch info.kind {
        case .corner:
            let boxer = [Role.st, .lw, .rw, .am, .cb, .cm].contains(p.role) && slot % 2 == 0 || p.role == .st
            if attacking && boxer && p.role != .gk {
                t = Vec2(attackGoalX - info.team.attackSign * (7 + Float(slot % 3) * 2), Float(slot % 4 - 1) * 3 - 1.5)
            } else if !attacking && p.role != .gk && p.role.line != .forward {
                t = Vec2(attackGoalX - info.team.attackSign * (5 + Float(slot % 3) * 2), Float(slot % 5 - 2) * 3)
            }
        case .freeKick:
            let dGoal = abs(attackGoalX - info.spot.x)
            if attacking && dGoal < 32 && p.role.line == .forward && i != info.taker {
                t = Vec2(attackGoalX - info.team.attackSign * 9, Float(slot % 3 - 1) * 4)
            } else if !attacking && p.role.line == .defender && p.role != .gk {
                // Wall: three nearest defenders stand 9.3 m from the ball on the ball-goal line.
                let ownGoal = Vec2(attackGoalX, 0)
                let defenders = players.indices.filter { players[$0].team == side && players[$0].role.line == .defender && players[$0].onPitch }
                    .sorted { simd_distance(players[$0].pos, info.spot) < simd_distance(players[$1].pos, info.spot) }
                if let k = defenders.prefix(3).firstIndex(of: i), dGoal < 32 {
                    let dir = unit(ownGoal - info.spot)
                    let perp = Vec2(-dir.y, dir.x)
                    t = info.spot + dir * 9.4 + perp * (Float(k) - 1) * 0.8
                }
            }
        case .penalty:
            if p.role != .gk { t = Vec2(attackGoalX - info.team.attackSign * 20, Float(slot % 6 - 3) * 5) }
        case .throwIn:
            if attacking && p.role != .gk {
                let near = players.indices.filter { players[$0].team == side && players[$0].onPitch && players[$0].role != .gk && $0 != info.taker }
                    .sorted { simd_distance(players[$0].pos, info.spot) < simd_distance(players[$1].pos, info.spot) }.prefix(3)
                if let k = near.firstIndex(of: i) {
                    let inward: Float = info.spot.y > 0 ? -1 : 1
                    t = Vec2(info.spot.x + sign * Float(k) * 6 - 3, info.spot.y + inward * (7 + Float(k) * 4))
                }
            }
        default: break
        }
        if p.role == .gk && !(p.team == info.team && info.kind == .goalKick) { setT(i, t, .goalkeeping, sprint: false, "set-piece position"); return }
        _ = goalX
        setT(i, t, .setPiece, sprint: simd_distance(p.pos, t) > 12, "set piece \(info.kind)")
    }

    func aiTakeRestart(_ info: RestartInfo) {
        let i = info.taker
        let p = players[i], sign = p.team.attackSign
        let attackGoalX = sign * PitchSpec.halfLength
        switch info.kind {
        case .kickoff:
            let mates = players.indices.filter { players[$0].team == p.team && $0 != i && players[$0].onPitch && players[$0].role != .gk }
            if let j = mates.min(by: { simd_distance(players[$0].pos, p.pos) < simd_distance(players[$1].pos, p.pos) }) {
                executePass(i, to: j, kind: .pass, power: 0.3, human: false)
            }
        case .goalKick:
            if let opt = bestPassOption(i, long: true) {
                if opt.kind == .lob || simd_distance(players[opt.target].pos, p.pos) > 28 { executePass(i, to: opt.target, kind: .lob, power: 0.8, human: false) }
                else { executePass(i, to: opt.target, kind: opt.kind, power: 0.6, human: false) }
            } else { executeLob(i, to: Vec2(p.pos.x + sign * 38, 0), target: nil, human: false, power: 0.9) }
        case .throwIn, .indirectFreeKick:
            if let opt = bestPassOption(i) { executePass(i, to: opt.target, kind: opt.kind == .through ? .pass : opt.kind, power: 0.5, human: false) }
            else { executeLob(i, to: clampToPitch(p.pos + Vec2(sign * 12, 0)), target: nil, human: false, power: 0.5) }
        case .corner:
            let spotT = Vec2(attackGoalX - sign * rng.range(6, 10), rng.range(-4, 4))
            let near = players.indices.filter { players[$0].team == p.team && $0 != i && players[$0].onPitch && players[$0].role != .gk }
                .min(by: { simd_distance(players[$0].pos, spotT) < simd_distance(players[$1].pos, spotT) })
            executeLob(i, to: spotT, target: near, human: false, power: 0.8, loft: 0.75)
        case .freeKick:
            let dGoal = simd_distance(Vec2(attackGoalX, 0), p.pos)
            if dGoal < 28 { executeShot(i, power: 0.85, aim: nil, human: false) }
            else if let opt = bestPassOption(i, long: dGoal < 50) { executePass(i, to: opt.target, kind: opt.kind == .through ? .pass : opt.kind, power: 0.6, human: false) }
            else { executeLob(i, to: Vec2(attackGoalX - sign * 10, 0), target: nil, human: false, power: 0.7) }
        case .penalty:
            executeShot(i, power: 0.9, aim: nil, human: false)
        }
    }

    // MARK: Goalkeepers

    func goalkeepersStep(_ dt: Float) {
        for g in players.indices where players[g].role == .gk && players[g].onPitch { goalkeeperStep(g, dt) }
    }

    func goalkeeperStep(_ g: Int, _ dt: Float) {
        let p = players[g]
        let side = p.team
        let sign = side.attackSign
        let goalDir = Vec2(sign, 0)
        let ownGoalX = -sign * PitchSpec.halfLength
        let goalCentre = Vec2(ownGoalX, 0)
        let bxz = Vec2(ball.position.x, ball.position.z)
        players[g].state = .goalkeeping
        if case .restart(let info) = phase, info.taker == g { return }
        if p.diveTime > 0 { checkSave(g); return }

        if p.holdingBall {
            players[g].desiredDir = .zero
            players[g].holdTimer -= dt
            if players[g].holdTimer <= 0 { distribute(g) }
            return
        }
        if ballOwner == g { // controlled at feet: play it out quickly
            players[g].desiredDir = .zero
            if players[g].possessionTime > 0.7 { distribute(g) }
            return
        }

        var target = goalCentre + goalDir * 2
        var sprint = false
        var why = "angle positioning"
        // Shot threat from trajectory prediction.
        let towardsGoal = ball.velocity.x * (-sign) > 3
        var cross: (t: Float, z: Float, y: Float)?
        if towardsGoal && ballOwner == nil { cross = predictGoalCrossing(towards: -sign) }
        if let c = cross, abs(c.z) < PitchSpec.goalWidth / 2 + 1.5, c.y < 3.0 {
            if players[g].reactTimer == 0 { players[g].reactTimer = 0.1 + Float(100 - p.attributes.reactionTime) * 0.002 + 0.0001 }
            players[g].reactTimer -= dt
            if players[g].reactTimer <= 0.0 || players[g].reactTimer == 0 {
                target = Vec2(ownGoalX + goalDir.x * 0.6, max(-5, min(5, c.z)))
                sprint = true; why = "track shot (cross z=\(String(format: "%.1f", c.z)) in \(String(format: "%.2f", c.t))s)"
                let dist = simd_distance(target, p.pos)
                if c.t < 0.75 && dist > 0.9 && p.diveTime <= 0 {
                    let dir = unit(target - p.pos)
                    players[g].diveTime = 0.6; players[g].vel = dir * min(8.5, dist / max(0.25, c.t) + 1)
                    players[g].diveDir = dir; players[g].state = .goalkeeping; players[g].reason = "dive"
                    return
                }
            } else { players[g].desiredDir = .zero; return }
        } else {
            players[g].reactTimer = 0
            let toBall = bxz - goalCentre
            let d = simd_length(toBall)
            var depth = max(1.5, min(6, 0.8 + 0.1 * d))
            let owner = ballOwner.map { players[$0] }
            if let o = owner, o.team != side, d < 24 { depth = min(d * 0.45, 9); why = "narrow angle / sweep" }
            target = goalCentre + unit(toBall) * depth
            target.y = max(-3.4, min(3.4, target.y))
            // Claim loose balls inside the area.
            if ballOwner == nil, Laws.inPenaltyArea(bxz, defending: side), ball.speed < 6, ball.position.y < 2.4 {
                let closestOpp = nearestOpponentDistance(to: bxz, of: side)
                if simd_distance(p.pos, bxz) < closestOpp + 1.5 { target = bxz; sprint = true; why = "claim loose ball" }
            }
        }
        players[g].target = target; players[g].reason = why
        let to = target - p.pos
        let dd = simd_length(to)
        players[g].desiredDir = dd > 0.2 ? to / dd * min(1, dd / 1.2) : .zero
        players[g].wantSprint = sprint
        let face = unit(bxz - p.pos)
        let fh = atan2(face.y, face.x)
        var dh = fh - players[g].heading
        while dh > .pi { dh -= 2 * .pi }; while dh < -.pi { dh += 2 * .pi }
        if dd < 0.3 { players[g].heading += dh * min(1, 6 * dt) }
        checkSave(g)
    }

    func checkSave(_ g: Int) {
        let p = players[g]
        guard p.saveCooldown <= 0, ballOwner == nil, !p.holdingBall else { return }
        let hands = Vec3(p.pos.x, min(ball.position.y, 2.2), p.pos.y)
        let reachH: Float = 0.75 + (p.diveTime > 0 ? 1.15 : 0.4)
        let hd = simd_distance(Vec2(ball.position.x, ball.position.z), p.pos)
        guard hd < reachH, ball.position.y < (p.diveTime > 0 ? 2.5 : 2.2), simd_distance(hands, ball.position) < reachH + 0.6 else { return }
        if let l = lastTouch, players[l].team == p.team, ball.speed < 8 { return }  // team-mate's slow pass: handled by control
        let sp = ball.speed
        let a = Float(p.attributes.goalkeeping)
        players[g].saveCooldown = 0.4
        let saveP = max(0.25, min(0.97, 0.82 + 0.005 * (a - 60) - 0.012 * max(0, sp - 18)))
        if rng.float() > saveP { return }   // beaten
        let t = p.team.rawValue
        let catchP = max(0.05, min(0.97, 0.9 - 0.035 * max(0, sp - 8) + 0.004 * (a - 60)))
        stats[t].saves += 1
        if rng.float() < catchP && ball.position.y < 2.0 {
            ballOwner = g; lastTouch = g; intendedReceiver = nil; pendingOffside = [:]
            players[g].holdingBall = true; players[g].holdTimer = 0.9 + rng.range(0, 0.8)
            players[g].diveTime = 0; players[g].vel = .zero
            ball.velocity = .zero
            events.append(.save(keeper: g, caught: true))
        } else {
            let out = unit(Vec2(p.team.attackSign, rng.range(-0.9, 0.9)))
            ball.velocity = Vec3(out.x * sp * 0.45, rng.range(1, 4), out.y * sp * 0.45)
            lastTouch = g; intendedReceiver = nil; pendingOffside = [:]
            events.append(.save(keeper: g, caught: false))
        }
    }

    func distribute(_ g: Int) {
        let p = players[g]
        players[g].holdingBall = false
        ball.position = Vec3(p.pos.x + p.facing.x * 0.4, PitchSpec.ballRadius, p.pos.y + p.facing.y * 0.4)
        players[g].holdTimer = 0
        let tac = teams[p.team.rawValue].setup.tactics
        if let opt = bestPassOption(g, long: tac.directness > 0.5) {
            let d = simd_distance(players[opt.target].pos, p.pos)
            if d < 22 && opt.kind != .lob { executePass(g, to: opt.target, kind: .pass, power: 0.5, human: false) }
            else { executePass(g, to: opt.target, kind: .lob, power: 0.8, human: false) }
        } else {
            executeLob(g, to: Vec2(p.pos.x + p.team.attackSign * 35, p.pos.y * 0.5), target: nil, human: false, power: 0.9)
        }
        players[g].kickLock = 0.5
    }
}
