import RealityKit
import AppKit
import simd
import FootballGame
import FootballPhysics

/// Owns every RealityKit entity. The simulation never touches this; `sync` copies state across.
@MainActor
final class PitchScene {
    let root = Entity()
    let cameraEntity = PerspectiveCamera()
    static let ballVisualScale: Float = 2.0

    private let ball = ModelEntity()
    private let ballShadow = ModelEntity()
    private(set) var rigs: [PlayerRenderable] = []
    private(set) var usingSkinned = false
    private var debugDots: [ModelEntity] = []
    private var debugLines: [ModelEntity] = []
    private let debugRoot = Entity()
    private var lodNear = 0, lodFar = 0
    var debugEnabled = false { didSet { debugRoot.isEnabled = debugEnabled } }
    let stadium = Stadium()
    private let sun = Entity(), fill = Entity()
    private var options = SceneOptions()
    private var elapsed: Float = 0

    struct SceneOptions {
        var preset: GraphicsPreset = .medium
        var timeOfDay: TimeOfDay = .day
        var weather: Weather = .clear
        var home = NSColor.red, away = NSColor.blue
        var homeName = "HOME", awayName = "AWAY"
    }

    func build(sim: MatchSimulation, options: SceneOptions = SceneOptions()) async {
        self.options = options
        buildLighting()
        await buildPitch()
        await stadium.build(preset: options.preset, home: options.home, away: options.away, names: (options.homeName, options.awayName))
        root.addChild(stadium.root)
        applyLook(options.timeOfDay, options.weather)
        buildGoals()
        buildBall()
        buildPlayers(sim)
        buildDebug(sim)
        var cam = PerspectiveCameraComponent()
        cam.fieldOfViewInDegrees = 38; cam.near = 0.3; cam.far = 800
        cameraEntity.camera = cam
        root.addChild(cameraEntity)
    }

    // MARK: Build

    private func buildLighting() {
        var light = DirectionalLightComponent()
        light.color = .white; light.intensity = 2400
        sun.components.set(light)
        if options.preset.shadows { sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 120, depthBias: 2)) }
        sun.look(at: .zero, from: SIMD3(-25, 60, 20), relativeTo: nil)
        root.addChild(sun)
        var f = DirectionalLightComponent()
        f.color = NSColor(white: 0.85, alpha: 1); f.intensity = 800
        fill.components.set(f)
        fill.look(at: .zero, from: SIMD3(30, 30, -20), relativeTo: nil)
        root.addChild(fill)
    }

    /// Time-of-day and weather: sun/moon, fill, sky colour, floodlights, rain.
    func applyLook(_ t: TimeOfDay, _ w: Weather) {
        let l = Stadium.look(t, w)
        var s = sun.components[DirectionalLightComponent.self]!; s.color = l.sunColor; s.intensity = l.sun; sun.components.set(s)
        sun.look(at: .zero, from: l.sunFrom, relativeTo: nil)
        var f = fill.components[DirectionalLightComponent.self]!; f.color = l.fillColor; f.intensity = l.fill; fill.components.set(f)
        stadium.applySky(l.sky); stadium.applyFloodlights(l.flood)
        stadium.setRain(w == .rain, rate: options.preset.rainBirthRate)
    }

    private func buildPitch() async {
        var mat = PhysicallyBasedMaterial()
        if let img = PitchTexture.make(), let tex = try? await TextureResource(image: img, options: .init(semantic: .color)) {
            mat.baseColor = .init(texture: .init(tex))
        } else { mat.baseColor = .init(tint: NSColor(red: 0.18, green: 0.5, blue: 0.18, alpha: 1)) }
        mat.roughness = 1.0; mat.metallic = 0.0
        root.addChild(ModelEntity(mesh: .generatePlane(width: PitchTexture.totalLength, depth: PitchTexture.totalWidth), materials: [mat]))
        let outer = ModelEntity(mesh: .generatePlane(width: 500, depth: 500),
                                materials: [SimpleMaterial(color: NSColor(red: 0.09, green: 0.26, blue: 0.1, alpha: 1), roughness: 1, isMetallic: false)])
        outer.position.y = -0.02
        root.addChild(outer)
    }

    private func buildGoals() {
        let white = SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)
        var net = UnlitMaterial(color: NSColor(white: 1, alpha: 1))
        net.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        let hw = PitchSpec.goalWidth / 2, h = PitchSpec.goalHeight, d = PitchSpec.goalDepth, r = PitchSpec.postRadius
        for s: Float in [-1, 1] {
            let goal = Entity(); goal.position = SIMD3(s * PitchSpec.halfLength, 0, 0); root.addChild(goal)
            for z: Float in [-hw, hw] {
                let post = ModelEntity(mesh: .generateCylinder(height: h + r, radius: r), materials: [white])
                post.position = SIMD3(0, (h + r) / 2 - r / 2, z); goal.addChild(post)
            }
            let bar = ModelEntity(mesh: .generateCylinder(height: PitchSpec.goalWidth + 2 * r, radius: r), materials: [white])
            bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)); bar.position = SIMD3(0, h, 0); goal.addChild(bar)
            func panel(_ size: SIMD3<Float>, _ pos: SIMD3<Float>) { let m = ModelEntity(mesh: .generateBox(size: size), materials: [net]); m.position = pos; goal.addChild(m) }
            panel(SIMD3(0.02, h, PitchSpec.goalWidth), SIMD3(s * d, h / 2, 0))
            panel(SIMD3(d, h, 0.02), SIMD3(s * d / 2, h / 2, -hw)); panel(SIMD3(d, h, 0.02), SIMD3(s * d / 2, h / 2, hw))
            panel(SIMD3(d, 0.02, PitchSpec.goalWidth), SIMD3(s * d / 2, h, 0))
        }
    }

    private func buildBall() {
        var mat = PhysicallyBasedMaterial(); mat.roughness = 0.5; mat.baseColor = .init(tint: .white)
        let m = ModelEntity(mesh: .generateSphere(radius: PitchSpec.ballRadius), materials: [mat])
        if let img = PitchTexture.makeBall() {
            Task { @MainActor in
                if let tex = try? await TextureResource(image: img, options: .init(semantic: .color)) {
                    var pm = PhysicallyBasedMaterial(); pm.baseColor = .init(texture: .init(tex)); pm.roughness = 0.5
                    m.model?.materials = [pm]
                }
            }
        }
        ball.addChild(m); ball.scale = SIMD3(repeating: Self.ballVisualScale); root.addChild(ball)
        var sm = UnlitMaterial(color: .black); sm.blending = .transparent(opacity: .init(floatLiteral: 0.4))
        ballShadow.model = ModelComponent(mesh: .generateCylinder(height: 0.004, radius: 0.16), materials: [sm])
        root.addChild(ballShadow)
    }

    private func buildPlayers(_ sim: MatchSimulation) {
        let assets = CharacterAssets.shared
        usingSkinned = assets.isAvailable && !CommandLine.arguments.contains("--procedural")
        for p in sim.players {
            let setup = sim.teamSetup(p.team)
            let isGK = p.role == .gk
            let shirtC = isGK ? NSColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1) : PlayerRig.color(setup.primary)
            let shortsC = isGK ? NSColor(white: 0.1, alpha: 1) : PlayerRig.color(setup.secondary)
            let socksC = isGK ? NSColor(white: 0.1, alpha: 1) : PlayerRig.color(setup.primary)
            let rig: PlayerRenderable
            if usingSkinned {
                rig = SkinnedPlayerRig(shirt: shirtC, shorts: shortsC, socks: socksC, appearance: p.appearance)
            } else {
                rig = PlayerRig(id: p.id, shirt: shirtC, shorts: shortsC, socks: socksC, number: p.number, appearance: p.appearance,
                                numberColor: isGK ? .black : PlayerRig.color(setup.secondary))
            }
            rigs.append(rig); root.addChild(rig.root)
        }
    }

    // MARK: Debug overlay (state dots + steering target lines)

    static func stateColor(_ s: AIState) -> NSColor {
        switch s {
        case .pressing: return .systemRed; case .marking: return .systemOrange; case .supporting: return .systemGreen
        case .positioning: return .systemGray; case .intercepting: return .systemYellow; case .dribbling: return .systemTeal
        case .passing: return .systemBlue; case .shooting: return .systemPink; case .tackling: return NSColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        case .recovering: return .systemBrown; case .goalkeeping: return .systemPurple; case .controlled: return .white
        case .setPiece: return .systemMint; case .idle: return .darkGray
        }
    }

    private func buildDebug(_ sim: MatchSimulation) {
        for _ in sim.players {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.28), materials: [UnlitMaterial(color: .gray)])
            let line = ModelEntity(mesh: .generateBox(size: SIMD3(1, 0.04, 0.06)), materials: [UnlitMaterial(color: .white)])
            debugRoot.addChild(dot); debugRoot.addChild(line); debugDots.append(dot); debugLines.append(line)
        }
        debugRoot.isEnabled = false
        root.addChild(debugRoot)
    }

    private var lastDebugStates: [AIState] = []

    private func updateDebug(_ sim: MatchSimulation) {
        if lastDebugStates.count != sim.players.count { lastDebugStates = Array(repeating: .idle, count: sim.players.count) }
        for (i, p) in sim.players.enumerated() {
            debugDots[i].isEnabled = p.onPitch; debugLines[i].isEnabled = p.onPitch
            guard p.onPitch else { continue }
            debugDots[i].position = SIMD3(p.pos.x, 2.25, p.pos.y)
            if lastDebugStates[i] != p.state {
                lastDebugStates[i] = p.state
                let c = Self.stateColor(p.state)
                debugDots[i].model?.materials = [UnlitMaterial(color: c)]
                debugLines[i].model?.materials = [UnlitMaterial(color: c)]
            }
            let d = p.target - p.pos
            let len = simd_length(d)
            if len > 0.5 && p.state != .controlled {
                debugLines[i].isEnabled = true
                debugLines[i].scale = SIMD3(len, 1, 1)
                debugLines[i].position = SIMD3(p.pos.x + d.x / 2, 0.08, p.pos.y + d.y / 2)
                debugLines[i].orientation = simd_quatf(angle: -atan2(d.y, d.x), axis: SIMD3(0, 1, 0))
            } else { debugLines[i].isEnabled = false }
        }
    }

    // MARK: Per-frame

    func sync(sim: MatchSimulation, dt: Float, cameraPos: SIMD3<Float>, controlled: [TeamSide: Int], crowd: Float = 0.3) {
        elapsed += dt; stadium.animateCrowd(time: elapsed, intensity: crowd)
        let b = sim.ball
        ball.position = b.position
        ball.position.y = max(b.position.y, PitchSpec.ballRadius * Self.ballVisualScale)
        ball.orientation = b.orientation
        let h = max(0, b.position.y - PitchSpec.ballRadius)
        ballShadow.position = SIMD3(b.position.x, 0.012, b.position.z)
        ballShadow.scale = SIMD3(repeating: max(0.4, 1.6 - h * 0.25))

        var near = 0
        for (i, p) in sim.players.enumerated() {
            let rig = rigs[i]
            rig.update(p, dt: dt, hasBall: sim.ballOwner == i)
            let d = simd_distance(SIMD3(p.pos.x, 0, p.pos.y), cameraPos)
            let sc = options.preset.lodScale
            rig.setLOD(usingSkinned ? (d > 62 * sc ? 2 : (d > 34 * sc ? 1 : 0)) : (d > 48 * sc ? 1 : 0))
            if d <= 34 * sc { near += 1 }
            let side = p.team
            rig.setControlled(controlled[side] == i, color: side == .home ? .yellow : .cyan)
        }
        lodNear = near; lodFar = rigs.count - near
        if debugEnabled { updateDebug(sim) }
    }

    var lodSummary: (near: Int, far: Int) { (lodNear, lodFar) }

    func applyCamera(_ rig: CameraRig) {
        cameraEntity.look(at: rig.lookTarget, from: rig.position, relativeTo: nil)
        var c = cameraEntity.camera
        c.fieldOfViewInDegrees = rig.fov
        cameraEntity.camera = c
    }
}
