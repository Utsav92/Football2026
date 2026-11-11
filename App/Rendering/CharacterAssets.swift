import RealityKit
import Foundation
import AppKit

struct ClipInfo: Decodable { let fps: Int; let frames: Int; let loop: Bool; let contact_frame: Int? }
struct CharacterManifest: Decodable { let clips: [String: ClipInfo]; let material_slots: [String] }

/// Loads the Blender-generated athlete (Tools/blender/make_football_player.py): three LOD meshes and 16 animation clips.
/// Everything is original work; see Documentation/ASSET_PIPELINE.md. If any file is missing the game falls back to the procedural rig.
@MainActor
final class CharacterAssets {
    static let shared = CharacterAssets()
    private(set) var lodTemplates: [Int: Entity] = [:]
    private(set) var clips: [String: AnimationResource] = [:]
    private(set) var manifest: CharacterManifest?
    private(set) var loadError: String?
    private(set) var loadSeconds: Double = 0
    var isAvailable: Bool { lodTemplates.count == 3 && !clips.isEmpty }

    private func url(_ name: String, _ ext: String) -> URL? { Bundle.main.url(forResource: name, withExtension: ext) }

    func load() async {
        guard !isAvailable, loadError == nil else { return }
        let t0 = Date()
        do {
            guard let mURL = url("player", "json") else { throw NSError(domain: "assets", code: 1, userInfo: [NSLocalizedDescriptionKey: "player.json not in bundle"]) }
            manifest = try JSONDecoder().decode(CharacterManifest.self, from: Data(contentsOf: mURL))
            for lod in 0...2 {
                guard let u = url("player_lod\(lod)", "usdz") else { throw NSError(domain: "assets", code: 2, userInfo: [NSLocalizedDescriptionKey: "player_lod\(lod).usdz missing"]) }
                lodTemplates[lod] = try await Entity(contentsOf: u)
            }
            for (name, info) in manifest!.clips {
                guard let u = url("anim_\(name)", "usdz") else { continue }
                let e = try await Entity(contentsOf: u)
                var anims: [AnimationResource] = []
                func collect(_ x: Entity) { anims += x.availableAnimations; x.children.forEach(collect) }
                collect(e)
                guard !anims.isEmpty else { continue }
                var res = anims.count == 1 ? anims[0] : try AnimationResource.group(with: anims)
                if info.loop { res = res.repeat() }
                clips[name] = res
            }
        } catch {
            loadError = "\(error)"
        }
        loadSeconds = Date().timeIntervalSince(t0)
    }

    /// Kit material override. Slot order is fixed by the Blender script: skin, shirt, shorts, socks, boots, hair.
    static func applyKit(_ e: Entity, skin: NSColor, shirt: NSColor, shorts: NSColor, socks: NSColor, hair: NSColor) {
        func m(_ c: NSColor, _ r: Float) -> PhysicallyBasedMaterial {
            var p = PhysicallyBasedMaterial(); p.baseColor = .init(tint: c); p.roughness = .init(floatLiteral: r); p.metallic = .init(floatLiteral: 0); return p
        }
        let mats: [PhysicallyBasedMaterial] = [m(skin, 0.6), m(shirt, 0.7), m(shorts, 0.7), m(socks, 0.75), m(NSColor(white: 0.04, alpha: 1), 0.4), m(hair, 0.9)]
        func walk(_ x: Entity) {
            if var model = x.components[ModelComponent.self] {
                if model.materials.count == mats.count { model.materials = mats; x.components.set(model) }
            }
            x.children.forEach(walk)
        }
        walk(e)
    }
}
