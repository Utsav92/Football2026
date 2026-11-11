import simd
import FootballGame
import FootballPhysics

enum CameraMode: Int, CaseIterable {
    case broadcast, teleBroadcast, dynamic, endToEnd, playerFollow, training, replay, tactical, penalty, freeKick
    var name: String {
        ["Broadcast", "Tele-Broadcast", "Dynamic", "End-to-End", "Player Follow", "Training", "Replay", "Tactical", "Penalty", "Free Kick"][rawValue]
    }
    /// Modes the user can cycle through with the camera key (replay is entered automatically).
    static var selectable: [CameraMode] { [.broadcast, .teleBroadcast, .dynamic, .endToEnd, .playerFollow, .tactical, .training] }
}

/// Smooth, framing-aware match cameras. The rig only reads the simulation; it never mutates it.
struct CameraRig {
    var mode: CameraMode = .broadcast
    private(set) var position = SIMD3<Float>(0, 25, 45)
    private(set) var lookTarget = SIMD3<Float>(0, 0, 0)
    private(set) var fov: Float = 38
    private var focus = SIMD3<Float>(0, 0, 0)
    private var spread: Float = 20
    private var smoothFov: Float = 38

    /// Screen-right / screen-up expressed in world (x, z), so controls follow the camera.
    var inputRight: Vec2 { attackSign > 0 ? (isBehind ? Vec2(0, 1) : Vec2(1, 0)) : (isBehind ? Vec2(0, -1) : Vec2(1, 0)) }
    var inputUp: Vec2 { isBehind ? Vec2(attackSign, 0) : Vec2(0, -1) }
    private var isBehind: Bool { effective == .endToEnd || effective == .playerFollow || effective == .penalty || effective == .freeKick }
    /// Mode actually in use (set pieces temporarily override the chosen mode).
    private(set) var effective: CameraMode = .broadcast
    var autoSetPiece = true
    var attackSign: Float = 1

    mutating func snap(_ sim: MatchSimulation, side: TeamSide?) {
        attackSign = side?.attackSign ?? 1
        update(sim, side: side, dt: 10)
    }

    mutating func update(_ sim: MatchSimulation, side: TeamSide?, dt: Float, restart: RestartInfo? = nil, flip: Bool = false) {
        attackSign = (side?.attackSign ?? 1) * (flip ? -1 : 1)
        effective = mode
        var setPiece: (spot: Vec2, dir: Float)?
        if autoSetPiece, mode != .replay, let r = restart {
            let dir = r.team.attackSign * (flip ? -1 : 1)
            if r.kind == .penalty { effective = .penalty; setPiece = (r.spot, dir) }
            else if r.kind == .freeKick, abs(r.spot.x - dir * PitchSpec.halfLength) < 32 { effective = .freeKick; setPiece = (r.spot, dir) }
        }
        if let sp = setPiece { attackSign = sp.dir }
        // Framing set: ball (heavy weight), the controlled player and the ball owner.
        let b = SIMD3<Float>(sim.ball.position.x, 0, sim.ball.position.z)
        let ahead = SIMD3<Float>(simd_clamp(sim.ball.velocity.x * 0.35, -10, 10), 0, simd_clamp(sim.ball.velocity.z * 0.2, -4, 4))
        var pts: [SIMD3<Float>] = [b + ahead]
        var weights: [Float] = [2.5]
        var ctrl = b
        if let s = side, let c = sim.controlled(s) { let p = sim.players[c].pos; ctrl = SIMD3(p.x, 0, p.y); pts.append(ctrl); weights.append(1.2) }
        if let o = sim.ballOwner { let p = sim.players[o].pos; pts.append(SIMD3(p.x, 0, p.y)); weights.append(1) }
        let wsum = weights.reduce(0, +)
        var f = SIMD3<Float>(0, 0, 0)
        for (p, w) in zip(pts, weights) { f += p * w }
        f /= wsum
        var sp: Float = 0
        for p in pts { sp = max(sp, simd_distance(SIMD2(p.x, p.z), SIMD2(f.x, f.z))) }

        let k = 1 - exp(-(mode == .replay ? 2.0 : 3.2) * dt)
        focus += (f - focus) * k
        spread += (sp - spread) * k

        let fx = simd_clamp(focus.x, -PitchSpec.halfLength + 4, PitchSpec.halfLength - 4)
        let fz = simd_clamp(focus.z, -PitchSpec.halfWidth + 3, PitchSpec.halfWidth - 3)
        var pos: SIMD3<Float>, look: SIMD3<Float>, targetFov: Float
        switch effective {
        case .broadcast:
            let d = simd_clamp(36 + spread * 1.0, 38, 60)
            pos = SIMD3(fx, d * 0.52, fz * 0.55 + d); look = SIMD3(fx, 0, fz * 0.6); targetFov = 38
        case .teleBroadcast:
            let d = simd_clamp(62 + spread * 1.2, 66, 90)
            pos = SIMD3(fx, d * 0.5, fz * 0.5 + d); look = SIMD3(fx, 0, fz * 0.6); targetFov = 26
        case .dynamic:
            let d = simd_clamp(22 + spread * 0.7, 24, 38)
            pos = SIMD3(fx - attackSign * 7, d * 0.42, fz * 0.7 + d); look = SIMD3(fx + attackSign * 4, 0, fz); targetFov = 52
        case .endToEnd:
            let d = simd_clamp(30 + spread * 0.6, 32, 48)
            pos = SIMD3(fx - attackSign * d, d * 0.5, fz * 0.8); look = SIMD3(fx + attackSign * 12, 0, fz); targetFov = 48
        case .playerFollow:
            let c = sideControlled(sim, side) ?? SIMD3(fx, 0, fz)
            pos = SIMD3(c.x - attackSign * 10, 6.5, c.z * 0.95); look = SIMD3(c.x + attackSign * 9, 0.5, c.z); targetFov = 62
        case .training:
            pos = SIMD3(fx, 42, fz + 16); look = SIMD3(fx, 0, fz); targetFov = 50
        case .tactical:
            pos = SIMD3(fx, 62, fz + 20); look = SIMD3(fx, 0, fz); targetFov = 45
        case .penalty:
            let sp = setPiece?.spot ?? Vec2(0, 0), d = setPiece?.dir ?? 1
            pos = SIMD3(sp.x - d * 9, 2.4, sp.y * 0.5); look = SIMD3(d * PitchSpec.halfLength, 1.2, 0); targetFov = 42
        case .freeKick:
            let sp = setPiece?.spot ?? Vec2(0, 0), d = setPiece?.dir ?? 1
            pos = SIMD3(sp.x - d * 12, 4.6, sp.y * 0.7); look = SIMD3(d * PitchSpec.halfLength, 1.5, 0); targetFov = 46
        case .replay:
            let d = simd_clamp(28 + spread * 0.8, 30, 48)
            pos = SIMD3(fx + attackSign * 6, d * 0.4, fz * 0.5 + d); look = SIMD3(fx, 0, fz * 0.6); targetFov = 40
        }
        let kp = 1 - exp(-((effective == .playerFollow || effective == .penalty || effective == .freeKick) ? 6.0 : 4.0) * dt)
        position += (pos - position) * kp
        lookTarget += (look - lookTarget) * kp
        smoothFov += (targetFov - smoothFov) * (1 - exp(-3 * dt))
        fov = smoothFov
    }

    private func sideControlled(_ sim: MatchSimulation, _ side: TeamSide?) -> SIMD3<Float>? {
        guard let s = side, let c = sim.controlled(s) else { return nil }
        let p = sim.players[c].pos
        return SIMD3(p.x, 0, p.y)
    }

    mutating func cycle() {
        let m = CameraMode.selectable
        let i = m.firstIndex(of: mode) ?? -1
        mode = m[(i + 1) % m.count]
    }
}
