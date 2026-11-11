import simd

public struct BallState {
    public var position: Vec3
    public var velocity: Vec3 = .zero
    public var angularVelocity: Vec3 = .zero
    /// Kick-imparted spin that drives Magnus curve (separate from rolling spin, which only affects visuals).
    public var curveSpin: Vec3 = .zero
    public var orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    public init(position: Vec3 = Vec3(0, PitchSpec.ballRadius, 0)) { self.position = position }

    public var horizontalVelocity: Vec2 { Vec2(velocity.x, velocity.z) }
    public var speed: Float { simd_length(velocity) }
    public var isOnGround: Bool { position.y <= PitchSpec.ballRadius + 0.005 && abs(velocity.y) < 0.05 }
}

public enum BallEvent: Equatable {
    case bounce(impactSpeed: Float)
    case woodwork(impactSpeed: Float)   // post or crossbar
    case net(impactSpeed: Float)
}

public struct BallPhysicsConfig {
    public var gravity: Float = PitchSpec.gravity
    /// Quadratic drag: a = -k |v| v. k = 0.5 rho Cd A / m for a size-5 ball (~0.0133 1/m).
    public var airDragK: Float = 0.0133
    /// Sideways force coefficient from spin (Magnus): a = k (omega x v). 0 disables curve.
    public var magnusK: Float = 0.004
    public var groundRestitution: Float = 0.62
    /// Fraction of horizontal speed kept through a bounce.
    public var bounceFriction: Float = 0.9
    /// Rolling deceleration on grass (m/s^2).
    public var rollingDecel: Float = 1.15
    public var woodworkRestitution: Float = 0.6
    public var woodworkFriction: Float = 0.9
    public var netRestitution: Float = 0.0
    public var netFriction: Float = 0.4
    /// Vertical speed below which a bounce is treated as a settle.
    public var restSpeed: Float = 0.7
    public var substeps: Int = 4
    public init() {}
}

/// Ball integrator: gravity, quadratic drag, optional Magnus, ground bounce, rolling friction,
/// goal-frame and net collisions. Deterministic; runs several sub-steps per simulation step.
public struct BallPhysics {
    public var config: BallPhysicsConfig
    public init(config: BallPhysicsConfig = .init()) { self.config = config }

    @discardableResult
    public func step(_ ball: inout BallState, dt: Float) -> [BallEvent] {
        var events: [BallEvent] = []
        let h = dt / Float(config.substeps)
        for _ in 0..<config.substeps { substep(&ball, h, &events) }
        return events
    }

    private func substep(_ b: inout BallState, _ h: Float, _ events: inout [BallEvent]) {
        let r = PitchSpec.ballRadius
        var p = b.position, v = b.velocity

        // Forces
        var a = Vec3(0, -config.gravity, 0)
        let speed = simd_length(v)
        if speed > 1e-4 { a -= v * (speed * config.airDragK) }
        if config.magnusK != 0 && !(p.y <= r + 0.002) { a += config.magnusK * simd_cross(b.curveSpin, v) }
        v += a * h
        p += v * h

        // Ground
        if p.y < r {
            p.y = r
            if v.y < 0 {
                let impact = -v.y
                if impact > config.restSpeed {
                    v.y = impact * config.groundRestitution
                    v.x *= config.bounceFriction; v.z *= config.bounceFriction
                    events.append(.bounce(impactSpeed: impact))
                } else { v.y = 0 }
            }
        }
        let rolling = p.y <= r + 0.002 && abs(v.y) < 0.05
        if rolling {
            let s = simd_length(Vec2(v.x, v.z))
            if s > 0 {
                let ns = max(0, s - config.rollingDecel * h)
                let k = ns / s
                v.x *= k; v.z *= k
                if ns < 0.03 { v.x = 0; v.z = 0 }
            }
        }

        // Goal frame + nets
        for c in GoalGeometry.frames {
            let imp = collide(sphere: &p, velocity: &v, radius: r, capsule: c,
                              restitution: config.woodworkRestitution, friction: config.woodworkFriction)
            if imp > 1 { events.append(.woodwork(impactSpeed: imp)) }
        }
        for box in GoalGeometry.nets {
            let imp = collide(sphere: &p, velocity: &v, radius: r, box: box,
                              restitution: config.netRestitution, friction: config.netFriction)
            if imp > 1 { events.append(.net(impactSpeed: imp)) }
        }

        b.curveSpin *= max(0, 1 - (rolling ? 8 : 0.4) * h)
        // Spin: rolling without slipping on the ground, slow decay in the air.
        if rolling {
            b.angularVelocity = simd_cross(Vec3(0, 1, 0), v) / r
        } else {
            b.angularVelocity *= max(0, 1 - 0.15 * h)
        }
        let w = simd_length(b.angularVelocity)
        if w > 1e-4 {
            b.orientation = simd_normalize(simd_quatf(angle: w * h, axis: b.angularVelocity / w) * b.orientation)
        }

        b.position = p
        b.velocity = v
    }
}

public enum GoalDetector {
    /// Returns +1 if the ball is fully inside the +X goal, -1 for the -X goal, 0 otherwise.
    public static func side(of ball: BallState) -> Int {
        let r = PitchSpec.ballRadius
        let p = ball.position
        guard abs(p.z) < PitchSpec.goalWidth / 2, p.y < PitchSpec.goalHeight else { return 0 }
        if p.x > PitchSpec.halfLength + r { return 1 }
        if p.x < -PitchSpec.halfLength - r { return -1 }
        return 0
    }

    /// True when the ball is wholly beyond a touchline or goal line (and not in a goal).
    public static func isOutOfPlay(_ ball: BallState) -> Bool {
        let r = PitchSpec.ballRadius, p = ball.position
        if side(of: ball) != 0 { return false }
        return abs(p.z) > PitchSpec.halfWidth + r || abs(p.x) > PitchSpec.halfLength + r
    }
}
