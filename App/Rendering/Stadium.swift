import RealityKit
import AppKit
import Metal
import simd
import FootballPhysics
import FootballGame

/// Stadium environment: stands, crowd, ad boards, flags, dugouts, tunnel, scoreboard, floodlights, sky, weather.
/// Built from primitives and generated meshes (original). Detail scales with the graphics preset.
@MainActor
final class Stadium {
    let root = Entity()
    private var crowdStands: [(entity: Entity, baseY: Float, phase: Float)] = []
    private var scoreboard = ModelEntity()
    private var spots: [Entity] = []
    private var towerHeads: [ModelEntity] = []
    private let sky = ModelEntity()
    private let rain = Entity()
    private(set) var spectatorCount = 0
    private(set) var triangleCount = 0

    static let sponsors = ["ORBITEL", "NOVA BANK", "AEROLINE", "KESTREL", "FJORD ENERGY", "MERIDIAN", "PULSE SPORT", "ALTAIR"]

    // MARK: Build

    func build(preset: GraphicsPreset, home: NSColor, away: NSColor, names: (String, String) = ("HOME", "AWAY")) async {
        self.names = names
        let concrete = SimpleMaterial(color: NSColor(white: 0.55, alpha: 1), roughness: 0.95, isMetallic: false)
        let rows = preset.standRows
        let hw = PitchSpec.halfWidth, hl = PitchSpec.halfLength
        struct Stand { var origin: SIMD3<Float>; var dir: SIMD3<Float>; var along: SIMD3<Float>; var length: Float }
        // dir = outward direction (away from pitch), along = direction of the rows.
        let stands = [
            Stand(origin: SIMD3(0, 0, hw + 6), dir: SIMD3(0, 0, 1), along: SIMD3(1, 0, 0), length: PitchSpec.length + 30),
            Stand(origin: SIMD3(0, 0, -(hw + 6)), dir: SIMD3(0, 0, -1), along: SIMD3(1, 0, 0), length: PitchSpec.length + 30),
            Stand(origin: SIMD3(hl + 8, 0, 0), dir: SIMD3(1, 0, 0), along: SIMD3(0, 0, 1), length: PitchSpec.width + 16),
            Stand(origin: SIMD3(-(hl + 8), 0, 0), dir: SIMD3(-1, 0, 0), along: SIMD3(0, 0, 1), length: PitchSpec.width + 16),
        ]
        let palette = await makePalette(home: home, away: away)
        var rng = SplitMix64(seed: 20260)
        let perStand = preset.crowdDensity / 4
        for (si, st) in stands.enumerated() {
            // Terraces
            for r in 0..<rows {
                let h = 1.0 + Float(r) * 0.62
                let depth: Float = 0.85
                let c = st.origin + st.dir * (Float(r) * depth)
                let size = abs(st.dir.z) > 0.5 ? SIMD3<Float>(st.length, h, depth) : SIMD3<Float>(depth, h, st.length)
                let step = ModelEntity(mesh: .generateBox(size: size), materials: [concrete])
                step.position = SIMD3(c.x, h / 2, c.z); root.addChild(step)
            }
            // Roof over the side stands (shadow + silhouette) on medium/high
            if preset != .low && st.dir.z < -0.5 {      // far-side roof only: the broadcast camera floats above the near stand
                let top = 1.0 + Float(rows) * 0.62
                let roof = ModelEntity(mesh: .generateBox(size: SIMD3(st.length + 2, 0.4, Float(rows) * 0.85 + 2)),
                                       materials: [SimpleMaterial(color: NSColor(white: 0.25, alpha: 1), roughness: 0.6, isMetallic: true)])
                roof.position = SIMD3(0, top + 5, st.origin.z + st.dir.z * Float(rows) * 0.425); root.addChild(roof)
            }
            // Crowd mesh for this stand
            var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
            func addBox(_ c: SIMD3<Float>, _ s: SIMD3<Float>, _ palIndex: Int) {
                let base = UInt32(pos.count)
                for dx in [-1, 1] as [Float] { for dy in [-1, 1] as [Float] { for dz in [-1, 1] as [Float] {
                    let o = SIMD3<Float>(dx, dy, dz)
                    pos.append(c + o * s / 2); nrm.append(simd_normalize(o)); uv.append(SIMD2((Float(palIndex) + 0.5) / 16, 0.5))
                } } }
                let faces: [[UInt32]] = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
                for f in faces { idx += [base + f[0], base + f[1], base + f[2], base + f[0], base + f[2], base + f[3]] }
            }
            let perRow = max(8, perStand / rows)
            for r in 0..<rows {
                let h = 1.0 + Float(r) * 0.62
                let base = st.origin + st.dir * (Float(r) * 0.85)
                for k in 0..<perRow where rng.float() < 0.86 {
                    let a = (Float(k) + rng.float() * 0.4) / Float(perRow) - 0.5
                    let c = base + st.along * (a * (st.length - 4))
                    let shirt = rng.float() < 0.38 ? 0 : (rng.float() < 0.22 ? 1 : 2 + rng.int(10))
                    let y = h + 0.3
                    addBox(SIMD3(c.x, y, c.z), SIMD3(0.42, 0.6, 0.32), shirt)
                    addBox(SIMD3(c.x, y + 0.45, c.z), SIMD3(0.2, 0.22, 0.2), 12 + rng.int(4))
                    spectatorCount += 1
                }
            }
            if !pos.isEmpty {
                var d = MeshDescriptor(name: "crowd\(si)")
                d.positions = MeshBuffer(pos); d.normals = MeshBuffer(nrm); d.textureCoordinates = MeshBuffer(uv); d.primitives = .triangles(idx)
                if let mesh = try? MeshResource.generate(from: [d]) {
                    var mat = PhysicallyBasedMaterial()
                    if let t = palette { mat.baseColor = .init(texture: .init(t)) }
                    mat.roughness = 0.95
                    let e = ModelEntity(mesh: mesh, materials: [mat]); root.addChild(e)
                    crowdStands.append((e, 0, Float(si) * 1.7)); triangleCount += idx.count / 3
                }
            }
        }
        if preset.adBoards { await buildAdBoards() }
        buildCornerFlags(); buildDugoutsAndTunnel(); await buildScoreboard(); buildTowers(); buildSky()
    }

    private func makePalette(home: NSColor, away: NSColor) async -> TextureResource? {
        guard let ctx = CGContext(data: nil, width: 16, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let cols: [NSColor] = [home, away, .white, NSColor(white: 0.12, alpha: 1), NSColor(red: 0.2, green: 0.35, blue: 0.7, alpha: 1), NSColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1),
                               NSColor(red: 0.25, green: 0.6, blue: 0.3, alpha: 1), NSColor(red: 0.85, green: 0.45, blue: 0.15, alpha: 1), NSColor(white: 0.7, alpha: 1),
                               NSColor(red: 0.6, green: 0.2, blue: 0.5, alpha: 1), NSColor(red: 0.2, green: 0.7, blue: 0.75, alpha: 1), NSColor(red: 0.5, green: 0.15, blue: 0.15, alpha: 1)]
                              + PlayerRig.skins.prefix(4).map { $0 }
        for (i, c) in cols.enumerated() {
            let rgb = c.usingColorSpace(.sRGB) ?? c
            ctx.setFillColor(CGColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: 1)); ctx.fill(CGRect(x: i, y: 0, width: 1, height: 1))
        }
        guard let img = ctx.makeImage() else { return nil }
        return try? await TextureResource(image: img, options: .init(semantic: .color))
    }

    private func labelTexture(_ text: String, bg: NSColor, fg: NSColor, size: CGSize, fontScale: CGFloat = 0.5) async -> TextureResource? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size.height * fontScale, weight: .heavy), .foregroundColor: fg, .paragraphStyle: para]
        (text as NSString).draw(in: CGRect(x: 0, y: size.height * 0.18, width: size.width, height: size.height * 0.7), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return nil }
        return try? await TextureResource(image: img, options: .init(semantic: .color))
    }

    private func buildAdBoards() async {
        let bgs: [NSColor] = [.systemBlue, .systemRed, NSColor(white: 0.1, alpha: 1), .systemOrange, .systemTeal, .systemPurple, .systemGreen, .systemIndigo]
        var mats: [UnlitMaterial] = []
        for (i, n) in Self.sponsors.enumerated() {
            var m = UnlitMaterial(color: bgs[i])
            if let t = await labelTexture(n, bg: bgs[i], fg: .white, size: CGSize(width: 512, height: 96)) { m.color = .init(tint: .white, texture: .init(t)) }
            mats.append(m)
        }
        let hl = PitchSpec.halfLength, hw = PitchSpec.halfWidth
        var k = 0
        for side: Float in [-1, 1] {
            var x: Float = -hl + 2
            while x < hl - 2 { let b = ModelEntity(mesh: .generateBox(size: SIMD3(5, 0.9, 0.12)), materials: [mats[k % mats.count]]); b.position = SIMD3(x + 2.5, 0.45, side * (hw + 3)); root.addChild(b); x += 5.2; k += 1 }
            var z: Float = -hw + 2
            while z < hw - 2 {
                if abs(z + 2.5) > 8 { let b = ModelEntity(mesh: .generateBox(size: SIMD3(0.12, 0.9, 5)), materials: [mats[k % mats.count]]); b.position = SIMD3(side * (hl + 4), 0.45, z + 2.5); root.addChild(b) }
                z += 5.2; k += 1
            }
        }
    }

    private func buildCornerFlags() {
        let pole = SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false), flag = UnlitMaterial(color: .systemYellow)
        for sx: Float in [-1, 1] { for sz: Float in [-1, 1] {
            let p = ModelEntity(mesh: .generateCylinder(height: 1.6, radius: 0.015), materials: [pole]); p.position = SIMD3(sx * PitchSpec.halfLength, 0.8, sz * PitchSpec.halfWidth)
            let f = ModelEntity(mesh: .generateBox(size: SIMD3(0.4, 0.3, 0.01)), materials: [flag]); f.position = SIMD3(sx * PitchSpec.halfLength - sx * 0.2, 1.45, sz * PitchSpec.halfWidth)
            root.addChild(p); root.addChild(f)
        } }
    }

    private func buildDugoutsAndTunnel() {
        let z = -(PitchSpec.halfWidth + 5)
        for x: Float in [-14, 14] {
            let roof = ModelEntity(mesh: .generateBox(size: SIMD3(10, 0.1, 2.2)), materials: [SimpleMaterial(color: NSColor(white: 0.8, alpha: 0.5), roughness: 0.2, isMetallic: false)])
            roof.position = SIMD3(x, 2.4, z); root.addChild(roof)
            let seats = ModelEntity(mesh: .generateBox(size: SIMD3(9, 0.5, 0.6)), materials: [SimpleMaterial(color: NSColor(white: 0.15, alpha: 1), roughness: 0.6, isMetallic: false)])
            seats.position = SIMD3(x, 0.5, z - 0.4); root.addChild(seats)
        }
        let tunnel = ModelEntity(mesh: .generateBox(size: SIMD3(4.5, 3, 0.3)), materials: [UnlitMaterial(color: NSColor(white: 0.02, alpha: 1))])
        tunnel.position = SIMD3(0, 1.5, -(PitchSpec.halfWidth + 5.9)); root.addChild(tunnel)
    }

    /// Scoreboard built from pre-made glyphs: each digit slot holds ten digit meshes and the right one is enabled. (In testing the renderer did not
    /// show a texture or mesh swapped on a live entity, but it does honour `isEnabled` — which the player LOD switching also relies on.)
    private var slots: [[ModelEntity]] = []
    private var lastDigits: [Int] = []
    private var names = ("HOME", "AWAY")

    private func buildScoreboard() async {
        let z = -(PitchSpec.halfWidth + 6 + 0.43 * Float(max(6, 10)) + 4)
        scoreboard.model = ModelComponent(mesh: .generateBox(size: SIMD3(22, 5.5, 0.4)), materials: [UnlitMaterial(color: NSColor(white: 0.02, alpha: 1))])
        scoreboard.position = SIMD3(0, 17, z)
        root.addChild(scoreboard)
        let gold = UnlitMaterial(color: NSColor(red: 1, green: 0.8, blue: 0.2, alpha: 1))
        func glyph(_ t: String) -> ModelEntity? {
            guard let m = try? MeshResource.generateText(t, extrusionDepth: 0.05, font: .systemFont(ofSize: 2.0, weight: .heavy), containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping) else { return nil }
            let e = ModelEntity(mesh: m, materials: [gold]); e.position.x = -m.bounds.center.x; e.position.y = -m.bounds.center.y; return e
        }
        func label(_ t: String, x: Float, maxWidth: Float) {
            guard let e = glyph(t), let m = e.model?.mesh else { return }
            let holder = Entity(); let k = min(0.8, maxWidth / max(m.bounds.extents.x, 0.1)); holder.scale = SIMD3(repeating: k); holder.position = SIMD3(x, 0, 0.22)
            holder.addChild(e); scoreboard.addChild(holder)
        }
        // layout (metres across the 22 m panel): HOME 0 0 – 0 0 AWAY | mm:ss
        label(names.0, x: -8.7, maxWidth: 3.4); label(names.1, x: 1.9, maxWidth: 3.4)
        label("–", x: -3.2, maxWidth: 1); label(":", x: 7.5, maxWidth: 1)
        let xs: [Float] = [-5.6, -4.5, -2.0, -0.9, 5.3, 6.5, 8.5, 9.7]        // home tens, home units, away tens, away units, mm tens/units, ss tens/units
        for x in xs {
            var row: [ModelEntity] = []
            let holder = Entity(); holder.position = SIMD3(x, 0, 0.22); holder.scale = SIMD3(repeating: 0.8); scoreboard.addChild(holder)
            for d in 0...9 { if let g = glyph("\(d)") { g.isEnabled = d == 0; holder.addChild(g); row.append(g) } }
            slots.append(row)
        }
        lastDigits = Array(repeating: 0, count: xs.count)
    }

    func setNames(home: String, away: String) { names = (home, away) }

    func updateScoreboard(hs: Int, aw: Int, seconds: Float) {
        let mins = min(99, Int(seconds) / 60), secs = Int(seconds) % 60
        let d = [min(9, hs / 10), hs % 10, min(9, aw / 10), aw % 10, mins / 10, mins % 10, secs / 10, secs % 10]
        guard d.count == slots.count else { return }
        for i in d.indices where d[i] != lastDigits[i] && slots[i].count == 10 {
            slots[i][lastDigits[i]].isEnabled = false; slots[i][d[i]].isEnabled = true; lastDigits[i] = d[i]
        }
    }

    private func buildTowers() {
        for sx: Float in [-1, 1] { for sz: Float in [-1, 1] {
            let base = SIMD3<Float>(sx * (PitchSpec.halfLength + 13), 0, sz * (PitchSpec.halfWidth + 11))
            let pole = ModelEntity(mesh: .generateCylinder(height: 30, radius: 0.4), materials: [SimpleMaterial(color: NSColor(white: 0.5, alpha: 1), roughness: 0.5, isMetallic: true)])
            pole.position = base + SIMD3(0, 15, 0); root.addChild(pole)
            let head = ModelEntity(mesh: .generateBox(size: SIMD3(5, 2.6, 0.6)), materials: [UnlitMaterial(color: NSColor(white: 0.25, alpha: 1))])
            head.position = base + SIMD3(0, 31, 0)
            head.look(at: SIMD3(0, 0, 0), from: head.position, relativeTo: nil)
            root.addChild(head); towerHeads.append(head)
            // Floodlight: a point light above each tower (spot lights did not contribute in the RealityKit renderer used here).
            let lamp = Entity()
            var pl = PointLightComponent(color: NSColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), intensity: 0, attenuationRadius: 170)
            pl.intensity = 0
            lamp.components.set(pl)
            lamp.position = base * 0.55 + SIMD3(0, 26, 0)       // pulled in over the pitch so the whole surface is covered
            root.addChild(lamp); spots.append(lamp)
        } }
    }

    private func buildSky() {
        sky.model = ModelComponent(mesh: .generateSphere(radius: 480), materials: [UnlitMaterial(color: NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1))])
        if var m = sky.model?.materials.first as? UnlitMaterial { m.faceCulling = .front; sky.model?.materials = [m] }
        root.addChild(sky)
    }

    // MARK: Time of day & weather

    struct Look { var sun: Float; var sunColor: NSColor; var sunFrom: SIMD3<Float>; var fill: Float; var fillColor: NSColor; var sky: NSColor; var flood: Float }

    static func look(_ t: TimeOfDay, _ w: Weather) -> Look {
        var l: Look
        switch t {
        case .day: l = Look(sun: 2400, sunColor: .white, sunFrom: SIMD3(-25, 60, 20), fill: 800, fillColor: NSColor(white: 0.85, alpha: 1), sky: NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1), flood: 0)
        case .sunset: l = Look(sun: 1800, sunColor: NSColor(red: 1, green: 0.62, blue: 0.38, alpha: 1), sunFrom: SIMD3(-70, 16, 25), fill: 600, fillColor: NSColor(red: 0.9, green: 0.55, blue: 0.5, alpha: 1), sky: NSColor(red: 0.93, green: 0.5, blue: 0.32, alpha: 1), flood: 0.35)
        case .night: l = Look(sun: 450, sunColor: NSColor(red: 0.55, green: 0.65, blue: 1, alpha: 1), sunFrom: SIMD3(-30, 50, 20), fill: 220, fillColor: NSColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1), sky: NSColor(red: 0.015, green: 0.025, blue: 0.07, alpha: 1), flood: 1)
        }
        switch w {
        case .clear: break
        case .overcast: l.sun *= 0.55; l.fill *= 0.9; l.sky = l.sky.blended(withFraction: 0.55, of: NSColor(white: 0.5, alpha: 1)) ?? l.sky; l.flood = max(l.flood, 0.25)
        case .rain: l.sun *= 0.55; l.fill *= 0.9; l.sky = l.sky.blended(withFraction: 0.7, of: NSColor(white: 0.32, alpha: 1)) ?? l.sky; l.flood = max(l.flood, 0.45)
        }
        return l
    }

    func applyFloodlights(_ level: Float) {
        for s in spots { var c = s.components[PointLightComponent.self]!; c.intensity = 6_000_000 * level; s.components.set(c); s.isEnabled = level > 0.01 }   // lights off = not evaluated at all
        for h in towerHeads { h.model?.materials = [UnlitMaterial(color: NSColor(white: 0.25 + 0.75 * CGFloat(level), alpha: 1))] }
    }

    func applySky(_ c: NSColor) {
        var m = UnlitMaterial(color: c); m.faceCulling = .front; sky.model?.materials = [m]
    }

    func setRain(_ on: Bool, rate: Float) {
        rain.removeFromParent()
        guard on else { return }
        var e = ParticleEmitterComponent()
        e.emitterShape = .box; e.emitterShapeSize = SIMD3(130, 0.1, 90); e.birthLocation = .volume
        e.mainEmitter.birthRate = rate; e.mainEmitter.lifeSpan = 1.1; e.mainEmitter.size = 0.02
        e.speed = 16; e.emissionDirection = SIMD3(0, -1, 0); e.emitterShapeSize = SIMD3(130, 0.1, 90)
        e.mainEmitter.color = .constant(.single(.init(red: 0.75, green: 0.82, blue: 0.95, alpha: 0.6)))
        e.mainEmitter.spreadingAngle = 0.03; e.mainEmitter.acceleration = SIMD3(0, -6, 0)
        rain.components.set(e); rain.position = SIMD3(0, 22, 0)
        root.addChild(rain)
    }

    /// Crowd reaction: a small vertical bounce whose amplitude and frequency follow the excitement level (0...1).
    func animateCrowd(time: Float, intensity: Float) {
        for (i, c) in crowdStands.enumerated() {
            let amp = 0.01 + 0.09 * intensity * intensity
            c.entity.position.y = c.baseY + amp * abs(sin(time * (3 + 6 * intensity) + c.phase + Float(i)))
        }
    }
}
