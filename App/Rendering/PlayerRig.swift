import RealityKit
import AppKit
import simd
import FootballGame
import FootballPhysics

/// Articulated placeholder humanoid (primitives) with a procedural animation state machine:
/// idle / walk / jog / sprint (speed-blended run cycle), kick (contact-synchronised), tackle lunge, slide,
/// fall, goalkeeper dive / hold, celebration. Milestone-4 asset pipeline swaps this for skinned USD models;
/// the pose inputs (`Footballer` state) stay identical.
@MainActor
final class PlayerRig {
    let root = Entity()
    private let pivot = Entity()
    private let hipL = Entity(), hipR = Entity(), kneeL = Entity(), kneeR = Entity()
    private let shoulderL = Entity(), shoulderR = Entity(), elbowL = Entity(), elbowR = Entity()
    private let torsoGroup = Entity()
    private var detailParts: [Entity] = []     // disabled at far LOD
    private let ring: ModelEntity
    private let marker: ModelEntity
    private var phase: Float
    private var lod = 0
    private(set) var rigID: Int
    private var celebrateClock: Float = 0

    static func color(_ c: ColorRGB) -> NSColor { NSColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1) }
    static let skins: [NSColor] = [0.95, 0.85, 0.74, 0.6, 0.46, 0.33].map { NSColor(red: $0, green: $0 * 0.78, blue: $0 * 0.62, alpha: 1) }
    static let hairs: [NSColor] = [NSColor(white: 0.08, alpha: 1), NSColor(red: 0.25, green: 0.15, blue: 0.08, alpha: 1), NSColor(red: 0.55, green: 0.38, blue: 0.18, alpha: 1),
                                   NSColor(red: 0.8, green: 0.65, blue: 0.3, alpha: 1), NSColor(red: 0.45, green: 0.12, blue: 0.08, alpha: 1)]

    init(id: Int, shirt: NSColor, shorts: NSColor, socks: NSColor, number: Int, appearance: Appearance, numberColor: NSColor) {
        rigID = id
        phase = Float(id) * 0.7
        func mat(_ c: NSColor, _ r: Float = 0.75) -> SimpleMaterial { SimpleMaterial(color: c, roughness: .init(floatLiteral: r), isMetallic: false) }
        let skin = Self.skins[min(appearance.skinTone, 5)]
        let hair = Self.hairs[min(appearance.hairColor, 4)]
        let scale = max(0.9, min(1.1, appearance.height / 1.8))
        let broad = 0.9 + appearance.build * 0.25

        let torso = ModelEntity(mesh: .generateBox(size: SIMD3(0.24, 0.52, 0.40 * broad), cornerRadius: 0.06), materials: [mat(shirt)])
        torso.position = SIMD3(0, 1.17, 0)
        let pelvis = ModelEntity(mesh: .generateBox(size: SIMD3(0.23, 0.2, 0.34 * broad), cornerRadius: 0.05), materials: [mat(shorts)])
        pelvis.position = SIMD3(0, 0.86, 0)
        let neck = ModelEntity(mesh: .generateCylinder(height: 0.09, radius: 0.045), materials: [mat(skin)])
        neck.position = SIMD3(0, 1.46, 0)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.112), materials: [mat(skin)])
        head.position = SIMD3(0.01, 1.60, 0)
        let nose = ModelEntity(mesh: .generateBox(size: SIMD3(0.04, 0.035, 0.03)), materials: [mat(skin)])
        nose.position = SIMD3(0.12, 1.58, 0)
        // Hair varies by style: 0 buzz, 1 short, 2 long back, 3 top, 4 bald, 5 tied
        let style = appearance.hairStyle
        if style != 4 {
            let h = ModelEntity(mesh: .generateSphere(radius: style == 0 ? 0.118 : 0.122), materials: [mat(hair, 0.9)])
            h.scale = SIMD3(1.0, style == 0 ? 0.55 : 0.7, 1.0); h.position = SIMD3(-0.005, 1.66 - (style == 0 ? 0.01 : 0), 0)
            detailParts.append(h); torsoGroup.addChild(h)
            if style == 2 || style == 5 {
                let b = ModelEntity(mesh: .generateBox(size: SIMD3(0.06, style == 2 ? 0.22 : 0.12, 0.14), cornerRadius: 0.03), materials: [mat(hair, 0.9)])
                b.position = SIMD3(-0.1, style == 2 ? 1.52 : 1.58, 0); detailParts.append(b); torsoGroup.addChild(b)
            }
        }
        for part in [torso, pelvis, neck, head, nose] { torsoGroup.addChild(part) }
        detailParts.append(nose)

        // Shirt number on the back
        if let numMesh = try? MeshResource.generateText("\(number)", extrusionDepth: 0.004, font: .systemFont(ofSize: 0.17, weight: .heavy),
                                                          containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping) {
            let t = ModelEntity(mesh: numMesh, materials: [UnlitMaterial(color: numberColor)])
            let c = numMesh.bounds.center
            t.position = SIMD3(-0.13, 1.19, -c.x)
            t.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0))
            detailParts.append(t); torsoGroup.addChild(t)
        }

        // Legs with knees
        for (hip, knee, z) in [(hipL, kneeL, Float(-0.095)), (hipR, kneeR, Float(0.095))] {
            hip.position = SIMD3(0, 0.86, z)
            let thigh = ModelEntity(mesh: .generateCylinder(height: 0.44, radius: 0.075), materials: [mat(shorts)])
            thigh.position = SIMD3(0, -0.22, 0)
            knee.position = SIMD3(0, -0.44, 0)
            let shin = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 0.058), materials: [mat(socks)])
            shin.position = SIMD3(0, -0.2, 0)
            let boot = ModelEntity(mesh: .generateBox(size: SIMD3(0.25, 0.07, 0.1), cornerRadius: 0.02), materials: [mat(NSColor(white: 0.06, alpha: 1), 0.4)])
            boot.position = SIMD3(0.05, -0.42, 0)
            knee.addChild(shin); knee.addChild(boot)
            hip.addChild(thigh); hip.addChild(knee)
            detailParts.append(boot)
            pivot.addChild(hip)
        }
        // Arms with elbows
        for (sh, el, z) in [(shoulderL, elbowL, Float(-0.25 * broad)), (shoulderR, elbowR, Float(0.25 * broad))] {
            sh.position = SIMD3(0, 1.38, z)
            let upper = ModelEntity(mesh: .generateCylinder(height: 0.3, radius: 0.048), materials: [mat(shirt)])
            upper.position = SIMD3(0, -0.15, 0)
            el.position = SIMD3(0, -0.3, 0)
            let fore = ModelEntity(mesh: .generateCylinder(height: 0.27, radius: 0.04), materials: [mat(skin)])
            fore.position = SIMD3(0, -0.135, 0)
            el.addChild(fore); sh.addChild(upper); sh.addChild(el)
            detailParts.append(el)
            pivot.addChild(sh)
        }
        pivot.addChild(torsoGroup)
        root.addChild(pivot)
        root.scale = SIMD3(repeating: scale)

        ring = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.85), materials: [UnlitMaterial(color: .yellow)])
        ring.position = SIMD3(0, 0.02, 0); ring.isEnabled = false
        var sm = UnlitMaterial(color: .black); sm.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let blob = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.5), materials: [sm])
        blob.position = SIMD3(0, 0.012, 0)
        marker = ModelEntity(mesh: .generateCone(height: 0.35, radius: 0.14), materials: [UnlitMaterial(color: .white)])
        marker.position = SIMD3(0, 2.35, 0); marker.orientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)); marker.isEnabled = false
        root.addChild(ring); root.addChild(blob); root.addChild(marker)
    }

    func setControlled(_ on: Bool, color: NSColor) {
        ring.isEnabled = on; marker.isEnabled = on
        if on { ring.model?.materials = [UnlitMaterial(color: color)]; marker.model?.materials = [UnlitMaterial(color: color)] }
    }

    func setLOD(_ level: Int) {
        guard level != lod else { return }
        lod = level
        for e in detailParts { e.isEnabled = level == 0 }
    }
    var lodLevel: Int { lod }

    private func q(_ a: Float, _ axis: SIMD3<Float> = SIMD3(0, 0, 1)) -> simd_quatf { simd_quatf(angle: a, axis: axis) }

    func update(_ f: Footballer, dt: Float, hasBall: Bool) {
        root.isEnabled = f.onPitch
        guard f.onPitch else { return }
        root.position = SIMD3(f.pos.x, 0, f.pos.y)
        root.orientation = simd_quatf(angle: -f.heading, axis: SIMD3(0, 1, 0))
        let speed = f.speed
        // Stride frequency fitted to real running pose: steps/s = 1.45 + 0.44 v (SkillCorner body-pose sample, 168 windows; see
        // Datasets/motion/skillcorner_gait.json). One gait cycle = 2 steps.
        let stepsPerSec: Float = speed > 0.3 ? 1.45 + 0.44 * speed : 0
        phase += dt * (Float.pi * stepsPerSec + 0.8)
        let amp = min(speed / 8.6, 1)
        var hl = sin(phase) * amp * 0.95, hr = -hl
        var kl = -(0.1 + 1.15 * amp * max(0, cos(phase))), kr = -(0.1 + 1.15 * amp * max(0, -cos(phase)))
        var sl = -hl * 0.85, sr = -hr * 0.85
        var el = 0.35 + 0.7 * amp, er = el
        var pivotRot = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        var pivotY: Float = 0
        var torsoLean: Float = amp * 0.12
        let breathe = sin(phase * 0.35) * 0.012

        if f.role == .gk && f.state == .goalkeeping && speed < 1.5 && f.diveTime <= 0 && !f.holdingBall {
            // Ready stance
            kl = -0.35; kr = -0.35; hl = 0.25; hr = 0.25; sl = 0.7; sr = 0.7; el = 0.9; er = 0.9; torsoLean = 0.18
        }
        if f.holdingBall { sl = 1.1; sr = 1.1; el = 1.0; er = 1.0 }

        if f.kickAnim > 0 {
            let u = 1 - f.kickAnim / 0.3             // 0 at ball contact -> 1 recovered
            let swing = (1 - u) * (1 - u)
            hr = 1.25 * swing - 0.1 * u; kr = -0.25 * swing - 0.3 * u * (1 - u)
            hl = -0.15 * swing; kl = -0.2 * swing
            sl = 0.7 * swing; sr = -0.6 * swing
            torsoLean = 0.15 * swing
        }
        if f.tackleAnim > 0 && !f.isSliding {
            let u = f.tackleAnim / 0.4
            hr = 1.0 * u; kr = -0.2 * u; torsoLean = 0.35 * u; hl = -0.5 * u; kl = -0.7 * u
        }
        if f.isSliding {
            pivotRot = q(1.2); pivotY = 0.28; hl = 0.9; hr = 0.9; kl = -0.1; kr = -0.05; sl = -0.9; sr = 0.9; el = 0.4; er = 0.4; torsoLean = 0
        }
        if f.isDiving {
            let right = Vec2(-f.facing.y, f.facing.x)
            let side: Float = simd_dot(f.diveDir, right) >= 0 ? 1 : -1
            pivotRot = q(1.25 * side, SIMD3(1, 0, 0)); pivotY = 0.45
            sl = 2.9; sr = 2.9; el = 0.1; er = 0.1; hl = 0.3; hr = -0.2; kl = -0.2; kr = -0.4; torsoLean = 0
        } else if f.isDown && !f.isSliding {
            let s: Float = (f.id % 2 == 0) ? 1 : -1
            pivotRot = q(1.35 * s, SIMD3(1, 0, 0)); pivotY = 0.2; kl = -0.5; kr = -0.2; hl = 0.3; hr = 0.1
        }
        if f.celebrate > 0 {
            celebrateClock += dt * 9
            sl = 2.8 + 0.25 * sin(celebrateClock); sr = 2.8 + 0.25 * sin(celebrateClock + 1); el = 0.2; er = 0.2
            pivotY = abs(sin(celebrateClock * 0.8)) * 0.22; hl = 0.1; hr = 0.1; kl = -0.15; kr = -0.15
        }

        hipL.orientation = q(hl); hipR.orientation = q(hr)
        shoulderL.orientation = q(sl); shoulderR.orientation = q(sr)
        if lod == 0 {
            kneeL.orientation = q(kl); kneeR.orientation = q(kr)
            elbowL.orientation = q(el); elbowR.orientation = q(er)
        }
        torsoGroup.orientation = q(torsoLean)
        torsoGroup.position.y = breathe
        pivot.orientation = pivotRot
        pivot.position = SIMD3(0, pivotY, 0)
    }
}
