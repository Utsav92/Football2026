import Foundation
import simd
import FootballPhysics

/// Presentation-only snapshot of one player (everything the renderer/animation system reads).
public struct PlayerSnap: Equatable {
    public var pos: Vec2, vel: Vec2
    public var heading: Float
    public var onPitch: Bool
    public var state: AIState
    public var kickAnim: Float, tackleAnim: Float, celebrate: Float, diveTime: Float, fallenTime: Float
    public var diveDir: Vec2
    public var holdingBall: Bool
    public var sliding: Bool
}

public struct ReplayFrame {
    public var t: Float
    public var ballPosition: Vec3
    public var ballOrientation: simd_quatf
    public var players: [PlayerSnap]
}

/// Ring buffer of recent match state (30 Hz). Used for goal replays: record while playing, play back at any speed.
public struct ReplayRecorder {
    public let hz: Float
    public let capacity: Int
    public private(set) var frames: [ReplayFrame] = []
    private var steps = 0
    private var stride: Int
    private var clock: Float = 0

    public init(seconds: Float = 14, hz: Float = 30, simHz: Float = 120) {
        self.hz = hz; capacity = Int(seconds * hz); stride = max(1, Int(simHz / hz))
    }

    public mutating func record(_ sim: MatchSimulation) {
        steps += 1; clock += MatchSimulation.dt
        guard steps % stride == 0 else { return }
        let ps = sim.players.map { p in
            PlayerSnap(pos: p.pos, vel: p.vel, heading: p.heading, onPitch: p.onPitch, state: p.state, kickAnim: p.kickAnim, tackleAnim: p.tackleAnim,
                       celebrate: p.celebrate, diveTime: p.diveTime, fallenTime: p.fallenTime, diveDir: p.diveDir, holdingBall: p.holdingBall, sliding: p.isSliding)
        }
        frames.append(ReplayFrame(t: clock, ballPosition: sim.ball.position, ballOrientation: sim.ball.orientation, players: ps))
        if frames.count > capacity { frames.removeFirst(frames.count - capacity) }
    }

    /// The last `seconds` of recorded play.
    public func clip(lastSeconds: Float) -> [ReplayFrame] {
        guard let end = frames.last?.t else { return [] }
        return frames.filter { $0.t >= end - lastSeconds }
    }
    public mutating func reset() { frames = []; steps = 0 }
}

public struct ReplayPlayer {
    public let frames: [ReplayFrame]
    public private(set) var time: Float
    public var speed: Float
    public init(frames: [ReplayFrame], speed: Float = 0.5) { self.frames = frames; self.speed = speed; time = frames.first?.t ?? 0 }
    public var isFinished: Bool { frames.isEmpty || time >= frames.last!.t }
    public var duration: Float { frames.isEmpty ? 0 : frames.last!.t - frames.first!.t }
    public mutating func advance(_ dt: Float) { time = min(frames.last?.t ?? 0, time + dt * speed) }

    /// Linearly interpolated frame at the current time (positions/headings interpolate; discrete flags take the earlier frame).
    public func sample() -> ReplayFrame? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if time <= first.t { return first }
        if time >= last.t { return last }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if frames[m].t <= time { lo = m } else { hi = m } }
        let a = frames[lo], b = frames[hi]
        let u = (time - a.t) / max(b.t - a.t, 1e-6)
        var out = a
        out.t = time
        out.ballPosition = a.ballPosition + (b.ballPosition - a.ballPosition) * u
        out.ballOrientation = simd_slerp(a.ballOrientation, b.ballOrientation, u)
        for i in out.players.indices {
            out.players[i].pos = a.players[i].pos + (b.players[i].pos - a.players[i].pos) * u
            out.players[i].vel = a.players[i].vel + (b.players[i].vel - a.players[i].vel) * u
            var d = b.players[i].heading - a.players[i].heading
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            out.players[i].heading = a.players[i].heading + d * u
        }
        return out
    }
}

extension MatchSimulation {
    /// Overwrite this simulation's presentation state with a replay frame. Used on a *separate* viewer instance so the live match is untouched.
    public func apply(_ f: ReplayFrame, mirrored: Bool = false) {
        let m: Float = mirrored ? -1 : 1
        ball.position = Vec3(f.ballPosition.x * m, f.ballPosition.y, f.ballPosition.z * m); ball.orientation = f.ballOrientation
        for (i, s) in f.players.enumerated() where i < players.count {
            players[i].pos = s.pos * m; players[i].vel = s.vel * m; players[i].heading = s.heading + (mirrored ? .pi : 0); players[i].onPitch = s.onPitch; players[i].state = s.state
            players[i].kickAnim = s.kickAnim; players[i].tackleAnim = s.tackleAnim; players[i].celebrate = s.celebrate
            players[i].diveTime = s.diveTime; players[i].fallenTime = s.fallenTime; players[i].diveDir = s.diveDir * m; players[i].holdingBall = s.holdingBall
            players[i].slideTime = s.sliding ? 0.3 : 0
        }
    }
}

extension MatchSimulation {
    /// Presentation for the second half / second extra-time period: teams have changed ends, so the world is shown rotated 180° about the
    /// pitch centre. The authoritative engine never changes direction; this only fills a *viewer* instance used for rendering and cameras.
    public func mirrorPresentation(from o: MatchSimulation, mirrored: Bool) {
        let m: Float = mirrored ? -1 : 1
        for i in players.indices where i < o.players.count {
            let q = o.players[i]
            players[i].pos = q.pos * m; players[i].vel = q.vel * m; players[i].heading = q.heading + (mirrored ? .pi : 0)
            players[i].onPitch = q.onPitch; players[i].state = q.state; players[i].role = q.role; players[i].target = q.target * m
            players[i].kickAnim = q.kickAnim; players[i].tackleAnim = q.tackleAnim; players[i].celebrate = q.celebrate
            players[i].diveTime = q.diveTime; players[i].fallenTime = q.fallenTime; players[i].diveDir = q.diveDir * m
            players[i].holdingBall = q.holdingBall; players[i].headAnim = q.headAnim; players[i].skillAnim = q.skillAnim
            players[i].slideTime = q.isSliding ? 0.3 : 0; players[i].stamina = q.stamina
        }
        ball.position = Vec3(o.ball.position.x * m, o.ball.position.y, o.ball.position.z * m)
        ball.velocity = Vec3(o.ball.velocity.x * m, o.ball.velocity.y, o.ball.velocity.z * m); ball.orientation = o.ball.orientation
        ballOwner = o.ballOwner; lastTouch = o.lastTouch; score = o.score; clock = o.clock
        for t in 0..<2 { teams[t].controlled = o.teams[t].controlled }
    }
}
