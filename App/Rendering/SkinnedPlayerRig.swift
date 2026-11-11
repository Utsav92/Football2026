import RealityKit
import AppKit
import simd
import FootballGame
import FootballPhysics

/// Common interface so the scene can use either the skinned athlete or the procedural placeholder.
@MainActor
protocol PlayerRenderable: AnyObject {
    var root: Entity { get }
    func update(_ f: Footballer, dt: Float, hasBall: Bool)
    func setControlled(_ on: Bool, color: NSColor)
    func setLOD(_ level: Int)
    var lodLevel: Int { get }
    var currentClip: String { get }
}
extension PlayerRig: PlayerRenderable { var currentClip: String { "procedural" } }

/// Skinned Blender athlete with an animation state machine: locomotion blended by speed, plus action clips
/// (kick, tackle, slide, fall, celebrate, goalkeeper ready/dive/catch). Transitions are RealityKit cross-fades.
@MainActor
final class SkinnedPlayerRig: PlayerRenderable {
    let root = Entity()
    private let holder = Entity()                     // rotates the USD (-Z forward) model to the game's +X forward
    private var lods: [Int: Entity] = [:]
    private(set) var lodLevel = 0
    private let ring: ModelEntity
    private let marker: ModelEntity
    private var controller: AnimationPlaybackController?
    private(set) var currentClip = ""
    private var locomotion = "idle"
    private var lastKick: Float = 0, lastTackle: Float = 0, lastHead: Float = 0
    private var oneShotUntil: Float = 0
    private var clock: Float = 0
    private let assets = CharacterAssets.shared

    private static let refSpeed: [String: Float] = ["walk": 1.6, "jog": 4.6, "sprint": 8.0]

    init(shirt: NSColor, shorts: NSColor, socks: NSColor, appearance: Appearance) {
        let skin = PlayerRig.skins[min(appearance.skinTone, 5)], hair = PlayerRig.hairs[min(appearance.hairColor, 4)]
        for lod in 0...2 {
            let e = assets.lodTemplates[lod]!.clone(recursive: true)
            CharacterAssets.applyKit(e, skin: skin, shirt: shirt, shorts: shorts, socks: socks, hair: hair)
            e.isEnabled = lod == 0
            holder.addChild(e); lods[lod] = e
        }
        holder.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0))
        let s = max(0.9, min(1.1, appearance.height / 1.84))
        holder.scale = SIMD3(repeating: s * (1.0 + (appearance.build - 0.5) * 0.0))
        root.addChild(holder)

        ring = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.85), materials: [UnlitMaterial(color: .yellow)])
        ring.position = SIMD3(0, 0.02, 0); ring.isEnabled = false
        var sm = UnlitMaterial(color: .black); sm.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let blob = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.5), materials: [sm]); blob.position = SIMD3(0, 0.012, 0)
        marker = ModelEntity(mesh: .generateCone(height: 0.35, radius: 0.14), materials: [UnlitMaterial(color: .white)])
        marker.position = SIMD3(0, 2.35, 0); marker.orientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)); marker.isEnabled = false
        root.addChild(ring); root.addChild(blob); root.addChild(marker)
        play("idle", transition: 0)
    }

    func setControlled(_ on: Bool, color: NSColor) {
        ring.isEnabled = on; marker.isEnabled = on
        if on { ring.model?.materials = [UnlitMaterial(color: color)]; marker.model?.materials = [UnlitMaterial(color: color)] }
    }

    func setLOD(_ level: Int) {
        guard level != lodLevel, lods[level] != nil else { return }
        controller?.stop()
        lods[lodLevel]?.isEnabled = false
        lodLevel = level
        lods[level]?.isEnabled = true
        let c = currentClip; currentClip = ""; play(c, transition: 0)
    }

    private func play(_ name: String, transition: TimeInterval = 0.2) {
        guard name != currentClip, let res = assets.clips[name], let e = lods[lodLevel] else { return }
        currentClip = name
        controller = e.playAnimation(res, transitionDuration: transition, startsPaused: false)
    }

    private func pickLocomotion(_ f: Footballer) -> String {
        let v = f.speed
        // Hysteresis around each threshold avoids flicker between neighbouring gaits.
        func up(_ t: Float, _ cur: Bool) -> Bool { v > (cur ? t - 0.35 : t + 0.1) }
        var l = "idle"
        if up(0.35, locomotion != "idle") { l = "walk" }
        if up(2.4, locomotion == "jog" || locomotion == "sprint") { l = "jog" }
        if up(5.6, locomotion == "sprint") { l = "sprint" }
        locomotion = l
        return l
    }

    func update(_ f: Footballer, dt: Float, hasBall: Bool) {
        root.isEnabled = f.onPitch
        guard f.onPitch else { return }
        clock += dt
        root.position = SIMD3(f.pos.x, 0, f.pos.y)
        root.orientation = simd_quatf(angle: -f.heading, axis: SIMD3(0, 1, 0))

        // Edge-triggered actions: the sim stamps kickAnim = 0.3 s at the instant the ball is struck, and the kick clip's contact pose
        // is its 3rd frame (0.1 s), so contact is visually within ~0.1 s of the ball leaving the foot.
        var want: String
        var oneShot = false
        if f.isDiving {
            let right = Vec2(-f.facing.y, f.facing.x)
            want = simd_dot(f.diveDir, right) >= 0 ? "gk_dive_right" : "gk_dive_left"; oneShot = true
        } else if f.isSliding { want = "slide"; oneShot = true }
        else if f.isDown { want = "fall"; oneShot = true }
        else if f.celebrate > 0 { want = "celebrate" }
        else if f.headAnim > lastHead + 0.05 || (f.headAnim > 0 && currentClip == "jump_header") { want = "jump_header"; oneShot = true }
        else if f.kickAnim > lastKick + 0.05 || (f.kickAnim > 0 && currentClip == "kick") { want = "kick"; oneShot = true }
        else if f.tackleAnim > lastTackle + 0.05 || (f.tackleAnim > 0 && currentClip == "tackle") { want = "tackle"; oneShot = true }
        else if f.holdingBall { want = "gk_catch" }
        else if f.role == .gk && f.state == .goalkeeping && f.speed < 1.5 { want = "gk_ready" }
        else { want = pickLocomotion(f) }
        lastKick = f.kickAnim; lastTackle = f.tackleAnim; lastHead = f.headAnim
        if oneShot && want != currentClip { oneShotUntil = clock + 0.25 }
        // Do not cut a freshly started one-shot short with locomotion for a few frames.
        if !oneShot && clock < oneShotUntil && ["kick", "tackle"].contains(currentClip) { want = currentClip }
        let transition: TimeInterval = oneShot ? 0.06 : 0.22
        play(want, transition: transition)
        if let c = controller, let ref = Self.refSpeed[currentClip] { c.speed = max(0.6, min(1.5, f.speed / ref)) }
        else if currentClip != "" { controller?.speed = 1 }
    }
}
