import Foundation
import FootballGame
import FootballPhysics

// Usage: SimExport <out.json> [matches=2] [seed=1] [homeFormation=4-3-3] [awayFormation=4-4-2]
// Writes simulated AI-vs-AI tracking in the normalised format used by Tools/analyze_formations.py (5 Hz, metres).
// This is SYNTHETIC data and is labelled as such in `meta.source`.
let args = CommandLine.arguments
if args.contains("--found-parity") {
    var r = SplitMix64(seed: 42)
    for _ in 0..<5 { print("rng", r.next()) }
    for _ in 0..<5 { print(String(format: "float %.7f", r.float())) }
    for _ in 0..<5 { print(String(format: "gauss %.5f", r.gaussian())) }
    print("int", r.int(11), r.int(100), r.int(3))
    for (i, role) in Role.allCases.enumerated() {
        var g = SplitMix64(seed: UInt64(100 + i))
        let a = PlayerAttributes.generated(role: role, quality: 70, rng: &g)
        print("attr", role.rawValue, a.sprintSpeed, a.acceleration, a.stamina, a.strength, a.agility, a.balance, a.dribbling, a.ballControl, a.shortPassing, a.longPassing, a.shootingAccuracy, a.shotPower, a.defensiveAwareness, a.tackling, a.goalkeeping, a.positioning, a.reactionTime, a.overall)
        print(String(format: "derived %@ %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f", role.rawValue, a.sprintMS, a.jogMS, a.accelMS2, a.turnRate, a.sprintDrain, a.staminaRecovery, a.decisionDelay, a.trapLimit, a.dribbleFactor, a.dribbleGain, a.maxShotSpeed, a.maxPassSpeed, a.passError(long: true) + a.passError(long: false) + a.shotError))
    }
    let opp: [Float] = [-52, -10, 5, 12, 20, 25, 30]
    for (rx, bx, sign) in [(30, 10, 1), (22, 25, 1), (12, 5, 1), (-30, -10, -1), (-20, 0, -1), (-5, -10, -1)] as [(Float, Float, Float)] {
        print("offside", Laws.isOffside(receiverX: rx, ballX: bx, opponentXs: opp.map { $0 * sign }, attackSign: sign))
    }
    for p in [Vec3(-30, 0, 20), Vec3(53, 0.1, 3), Vec3(53, 0.1, 20), Vec3(-53, 0.1, 30), Vec3(-53, 0.1, 2), Vec3(60, 0, -34.5)] {
        for lt in TeamSide.allCases {
            let r = Laws.restartAfterBallOut(exit: p, lastTouch: lt)
            print(String(format: "restart %d %d %.3f %.3f", lt.rawValue, [RestartKind.kickoff, .throwIn, .goalKick, .corner, .freeKick, .indirectFreeKick, .penalty].firstIndex(of: r.kind)!, r.spot.x, r.spot.y), r.team.rawValue)
        }
    }
    for (x, y, side) in [(-45, 5, TeamSide.home), (-30, 5, .home), (45, 25, .away), (45, 0, .away), (-52, 19, .home)] as [(Float, Float, TeamSide)] {
        print("pen", Laws.inPenaltyArea(Vec2(x, y), defending: side))
    }
    for len in [360, 600] as [Float] {
        var c = MatchClock(matchLengthSeconds: len)
        var st = FixedStepper()
        var steps = 0
        for f in 0..<1000 { steps += st.advance(frameTime: 0.013 + Float(f % 7) * 0.002); c.tick(0.0083) }
        print(String(format: "clock %.3f %d %.3f %d", c.gameSeconds, c.minutes, c.timeScale, steps))
        c.startSecondHalf(); c.addedSeconds = 120
        print("clock2", c.half, c.gameSeconds, c.nominalEnd, c.inAddedTime, c.isHalfOver)
        c.startNextPeriod(); print("clock3", c.half, c.gameSeconds, c.nominalEnd)
    }
    exit(0)
}
if args.contains("--form-parity") {
    for f in Formation.allCases {
        print("formation", f.rawValue, String(format: "%.5f", f.outfieldMeanDepth), f.slots.map { "\($0.role.rawValue):\($0.depth):\($0.lateral)" }.joined(separator: ","))
    }
    for (dx, dy, h) in [(11, 0, false), (16, 8, false), (6, 2, true), (30, -10, false), (3, 0.5, false), (20, 20, true)] as [(Float, Float, Bool)] {
        print(String(format: "xg %.5f", TacticalPriors.xG(dx: dx, dy: dy, header: h)))
    }
    for (k, f) in Formation.allCases.enumerated() {
        let t = TeamSetup.generated(name: "T", short: "T", quality: 65 + k * 3, formation: f, seed: UInt64(7 + k), primary: ColorRGB(1, 0, 0), secondary: ColorRGB(0, 0, 1), idBase: k * 100)
        for p in t.players { print("player", p.id, p.name, p.number, p.role.rawValue, p.attributes.overall, p.attributes.sprintSpeed, p.attributes.goalkeeping, p.appearance.skinTone, p.appearance.hairStyle, p.appearance.hairColor, String(format: "%.5f %.5f", p.appearance.height, p.appearance.build)) }
    }
    print("difficulty", Difficulty.allCases.map { String(format: "%.2f", $0.skill) }.joined(separator: ","))
    exit(0)
}
if args.contains("--sim-parity") {
    let home = TeamSetup.generated(name: "Home", short: "HOM", quality: 75, formation: .f433, seed: 11, primary: ColorRGB(1, 0, 0), secondary: ColorRGB(1, 1, 1), idBase: 0)
    let away = TeamSetup.generated(name: "Away", short: "AWY", quality: 70, formation: .f442, seed: 22, primary: ColorRGB(0, 0, 1), secondary: ColorRGB(1, 1, 1), idBase: 100)
    var cfg = MatchConfig(home: home, away: away, matchLengthSeconds: 360, difficulty: .professional, humanTeams: [], seed: 5)
    cfg.humanTeams = []
    let sim = MatchSimulation(config: cfg)
    let argInt = { (k: String, d: Int) -> Int in if let i = args.firstIndex(of: k), i + 1 < args.count, let v = Int(args[i + 1]) { return v }; return d }
    let from = argInt("--from", 1), to = argInt("--to", 24000), stride = argInt("--stride", 1200)
    for s in 1...to {
        sim.step()
        if s >= from && s % stride == 0 {
            print(String(format: "snap %d score %d-%d clock %.2f ball %.6f %.6f %.6f p0 %.6f %.6f p15 %.6f %.6f shots %d %d passes %d %d", s, sim.score.home, sim.score.away, sim.clock.gameSeconds, sim.ball.position.x, sim.ball.position.y, sim.ball.position.z, sim.players[0].pos.x, sim.players[0].pos.y, sim.players[15].pos.x, sim.players[15].pos.y, sim.stats[0].shots, sim.stats[1].shots, sim.stats[0].passes, sim.stats[1].passes))
        }
    }
    exit(0)
}
if args.contains("--sim-stats") {
    let n = args.firstIndex(of: "--sim-stats").flatMap { Int(args[$0 + 1]) } ?? 20
    for seed in 1...n {
        let home = TeamSetup.generated(name: "H", short: "HOM", quality: 75, formation: .f433, seed: UInt64(seed * 3), primary: ColorRGB(1, 0, 0), secondary: ColorRGB(1, 1, 1), idBase: 0)
        let away = TeamSetup.generated(name: "A", short: "AWY", quality: 70, formation: .f442, seed: UInt64(seed * 3 + 1), primary: ColorRGB(0, 0, 1), secondary: ColorRGB(1, 1, 1), idBase: 100)
        let cfg = MatchConfig(home: home, away: away, matchLengthSeconds: 360, difficulty: .professional, humanTeams: [], seed: UInt64(seed))
        let sim = MatchSimulation(config: cfg)
        var steps = 0
        while sim.phase != .fullTime && steps < 200_000 { sim.step(); steps += 1 }
        let a = sim.stats[0], b = sim.stats[1]
        print("match", seed, steps, sim.score.home, sim.score.away, a.shots, b.shots, a.shotsOnTarget, b.shotsOnTarget, a.passes, b.passes, a.passesCompleted, b.passesCompleted, a.tackles, b.tackles, a.fouls, b.fouls, a.corners, b.corners, a.offsides, b.offsides, a.saves, b.saves, a.yellowCards + b.yellowCards, a.redCards + b.redCards)
    }
    exit(0)
}
if args.contains("--ball-parity") {
    // Deterministic ball trajectories, printed for comparison with the C++ port (UE/Parity).
    let scenarios: [(String, Vec3, Vec3, Vec3)] = [
        ("lob_curve", Vec3(-20, 0.11, 5), Vec3(18, 9, -3), Vec3(0, 40, 0)),
        ("ground_pass", Vec3(0, 0.11, 0), Vec3(14, 0, 4), .zero),
        ("shot_crossbar", Vec3(35, 0.11, 0.5), Vec3(30, 7.5, 0.3), .zero),
        ("shot_net", Vec3(40, 0.11, 1.0), Vec3(28, 3.0, 0.4), Vec3(0, -15, 0)),
        ("post_hit", Vec3(40, 0.11, -3.0), Vec3(24, 1.0, 0.8), .zero),
    ]
    let phys = BallPhysics()
    for (name, p0, v0, spin) in scenarios {
        var b = BallState(position: p0); b.velocity = v0; b.curveSpin = spin
        for i in 0..<720 {
            phys.step(&b, dt: 1.0 / 120)
            if i % 30 == 29 { print(String(format: "%@ %d %.4f %.4f %.4f %.4f %.4f %.4f", name, i + 1, b.position.x, b.position.y, b.position.z, b.velocity.x, b.velocity.y, b.velocity.z)) }
        }
    }
    exit(0)
}
if args.contains("--bench") {
    // Simulation throughput: full AI-vs-AI 11v11 matches, fixed 120 Hz steps, wall-clock per step.
    var perStep: [Double] = []
    for seed in 1...5 {
        let h = TeamSetup.generated(name: "H", short: "H", quality: 70, formation: .f433, seed: UInt64(seed), primary: ColorRGB(1, 0, 0), secondary: ColorRGB(1, 1, 1))
        let a = TeamSetup.generated(name: "A", short: "A", quality: 70, formation: .f442, seed: UInt64(seed) &+ 50, primary: ColorRGB(0, 0, 1), secondary: ColorRGB(1, 1, 1), idBase: 100)
        let m = MatchSimulation(config: MatchConfig(home: h, away: a, matchLengthSeconds: 360, humanTeams: [], seed: UInt64(seed)))
        var n = 0
        let t0 = DispatchTime.now().uptimeNanoseconds
        while m.phase != .fullTime && n < 120 * 600 { m.step(); n += 1; _ = m.drainEvents() }
        perStep.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / Double(n) / 1000)
    }
    perStep.sort()
    print(String(format: "BENCH 22-player step: median %.2f us/step (best %.2f, worst %.2f) over 5 full matches -> %.0f steps/s; real time needs 120 steps/s = %.3f%% of one core",
                 perStep[2], perStep[0], perStep[4], 1e6 / perStep[2], perStep[2] * 120 / 1e4))
    exit(0)
}
let out = args.count > 1 ? args[1] : "sim_tracking.json"
let matches = args.count > 2 ? Int(args[2]) ?? 2 : 2
let seed0 = args.count > 3 ? UInt64(args[3]) ?? 1 : 1
let hf = args.count > 4 ? Formation(rawValue: args[4]) ?? .f433 : .f433
let af = args.count > 5 ? Formation(rawValue: args[5]) ?? .f442 : .f442

func r2(_ v: Float) -> String { String(format: "%.2f", v) }
var json = "{\"meta\":{\"source\":\"football2026_simulation (SYNTHETIC)\",\"match_id\":\"sim_\(hf.rawValue)_v_\(af.rawValue)\",\"hz\":5,\"pitch\":[105,68],\"dir\":{\"1\":1,\"2\":1},\"license\":\"synthetic, generated by this project\",\"players\":{}},\"frames\":["
var first = true
var frameCount = 0
for k in 0..<matches {
    let h = TeamSetup.generated(name: "H", short: "H", quality: 70, formation: hf, seed: seed0 &* 3 &+ UInt64(k), primary: ColorRGB(1, 0, 0), secondary: ColorRGB(1, 1, 1))
    let a = TeamSetup.generated(name: "A", short: "A", quality: 70, formation: af, seed: seed0 &* 7 &+ UInt64(k), primary: ColorRGB(0, 0, 1), secondary: ColorRGB(1, 1, 1), idBase: 100)
    let m = MatchSimulation(config: MatchConfig(home: h, away: a, matchLengthSeconds: 360, difficulty: .professional, humanTeams: [], seed: seed0 &+ UInt64(k)))
    var n = 0
    while m.phase != .fullTime && n < 120 * 600 {
        m.step(); n += 1; _ = m.drainEvents()
        guard case .playing = m.phase, n % 24 == 0 else { continue }
        let t = Float(frameCount) / 5
        var s = first ? "" : ","
        first = false
        s += "{\"t\":\(r2(t)),\"p\":\(m.clock.half),\"b\":[\(r2(m.ball.position.x)),\(r2(-m.ball.position.z))],"
        func team(_ side: TeamSide) -> String {
            m.players.filter { $0.team == side && $0.onPitch }.map { "[\($0.id),\(r2($0.pos.x)),\(r2(-$0.pos.y))]" }.joined(separator: ",")
        }
        // Simulation y axis is flipped (z) to match the "y up" convention of the real-data files.
        let poss = m.ballOwner.map { m.players[$0].team == .home ? "\"h\"" : "\"a\"" } ?? "null"
        s += "\"h\":[\(team(.home))],\"a\":[\(team(.away))],\"poss\":\(poss)}"
        json += s
        frameCount += 1
    }
}
json += "]}"
try json.write(toFile: out, atomically: true, encoding: .utf8)
print("wrote \(out): \(frameCount) frames from \(matches) match(es)")
