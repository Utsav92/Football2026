import simd

struct Capsule { var a: Vec3; var b: Vec3; var radius: Float }
struct Box {
    var min: Vec3
    var max: Vec3
    init(center: Vec3, half: Vec3) { min = center - half; max = center + half }
}

/// Fixed world geometry the ball can hit: goal frames (posts + crossbar) and net panels.
enum GoalGeometry {
    static let frames: [Capsule] = {
        var out: [Capsule] = []
        let hw = PitchSpec.goalWidth / 2, h = PitchSpec.goalHeight, r = PitchSpec.postRadius
        for s: Float in [-1, 1] {
            let x = s * PitchSpec.halfLength
            out.append(Capsule(a: Vec3(x, 0, -hw), b: Vec3(x, h, -hw), radius: r))
            out.append(Capsule(a: Vec3(x, 0, hw), b: Vec3(x, h, hw), radius: r))
            out.append(Capsule(a: Vec3(x, h, -hw), b: Vec3(x, h, hw), radius: r))
        }
        return out
    }()

    /// Thin boxes forming back, sides and roof of each net.
    static let nets: [Box] = {
        var out: [Box] = []
        let hw = PitchSpec.goalWidth / 2, h = PitchSpec.goalHeight, d = PitchSpec.goalDepth
        let t: Float = 0.05  // half-thickness
        for s: Float in [-1, 1] {
            let xl = s * PitchSpec.halfLength
            let xb = s * (PitchSpec.halfLength + d)
            // Side/roof panels start just behind the goal line so they never shadow the posts/crossbar.
            let gap: Float = 0.15
            let xm = (xl + s * gap + xb) / 2
            let hl = (d - gap) / 2
            out.append(Box(center: Vec3(xb + s * t, h / 2, 0), half: Vec3(t, h / 2, hw + 2 * t)))      // back
            out.append(Box(center: Vec3(xm, h / 2, -(hw + t)), half: Vec3(hl, h / 2, t)))           // side -z
            out.append(Box(center: Vec3(xm, h / 2, hw + t), half: Vec3(hl, h / 2, t)))              // side +z
            out.append(Box(center: Vec3(xm, h + t, 0), half: Vec3(hl, t, hw + 2 * t)))              // roof
        }
        return out
    }()
}

/// Sphere vs capsule. Returns impact speed along the normal (0 if no contact).
@inline(__always)
func collide(sphere p: inout Vec3, velocity v: inout Vec3, radius r: Float,
             capsule c: Capsule, restitution e: Float, friction f: Float) -> Float {
    let ab = c.b - c.a
    let t = simd_clamp(simd_dot(p - c.a, ab) / simd_dot(ab, ab), 0, 1)
    let q = c.a + ab * t
    let d = p - q
    let dist = simd_length(d)
    let minDist = r + c.radius
    guard dist < minDist, dist > 1e-6 else { return 0 }
    let n = d / dist
    p = q + n * minDist
    let vn = simd_dot(v, n)
    guard vn < 0 else { return 0 }
    v = (v - vn * n) * f - vn * e * n
    return -vn
}

/// Sphere vs axis-aligned box. Returns impact speed along the normal (0 if no contact).
@inline(__always)
func collide(sphere p: inout Vec3, velocity v: inout Vec3, radius r: Float,
             box: Box, restitution e: Float, friction f: Float) -> Float {
    let c = simd_clamp(p, box.min, box.max)
    let d = p - c
    let dist = simd_length(d)
    guard dist < r else { return 0 }
    var n: Vec3
    if dist > 1e-6 {
        n = d / dist
        p = c + n * r
    } else {
        // Centre inside box: push out through the nearest face.
        let lo = p - box.min, hi = box.max - p
        var best = lo.x; n = Vec3(-1, 0, 0)
        if hi.x < best { best = hi.x; n = Vec3(1, 0, 0) }
        if lo.y < best { best = lo.y; n = Vec3(0, -1, 0) }
        if hi.y < best { best = hi.y; n = Vec3(0, 1, 0) }
        if lo.z < best { best = lo.z; n = Vec3(0, 0, -1) }
        if hi.z < best { best = hi.z; n = Vec3(0, 0, 1) }
        p += n * (best + r)
    }
    let vn = simd_dot(v, n)
    guard vn < 0 else { return 0 }
    v = (v - vn * n) * f - vn * e * n
    return -vn
}
