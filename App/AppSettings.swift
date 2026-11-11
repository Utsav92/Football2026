import SwiftUI
import FootballInput

enum GraphicsPreset: String, Codable, CaseIterable, Identifiable {
    case low = "Low", medium = "Medium", high = "High"
    var id: String { rawValue }
    var crowdDensity: Int { switch self { case .low: return 1200; case .medium: return 4000; case .high: return 9000 } }
    var standRows: Int { switch self { case .low: return 6; case .medium: return 10; case .high: return 14 } }
    var shadows: Bool { self != .low }
    var lodScale: Float { switch self { case .low: return 0.6; case .medium: return 1; case .high: return 1.5 } }
    var rainBirthRate: Float { switch self { case .low: return 1500; case .medium: return 3500; case .high: return 7000 } }
    var adBoards: Bool { self != .low }
}

enum TimeOfDay: String, Codable, CaseIterable, Identifiable { case day = "Day", sunset = "Sunset", night = "Night"; var id: String { rawValue } }
enum Weather: String, Codable, CaseIterable, Identifiable { case clear = "Clear", overcast = "Overcast", rain = "Rain"; var id: String { rawValue } }

struct Settings: Codable, Equatable {
    var bindings = ControlBindings.standard
    var controller = ControllerSettings()
    var graphics: GraphicsPreset = .high
    var masterVolume: Float = 0.8
    var musicVolume: Float = 0.35
    var sfxVolume: Float = 0.9
    var crowdVolume: Float = 0.6
    var announcements = false            // optional system text-to-speech stadium announcer (off by default)
    var autoSetPieceCamera = true
    var defaultCamera = 0
    var matchMinutes = 6
    var difficulty = 3
}

/// Persistent settings (UserDefaults, JSON). Survives relaunch; a corrupt blob falls back to defaults.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    private static let key = "football2026.settings.v1"
    var value: Settings { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(Settings.self, from: d) { value = s } else { value = Settings() }
    }
    private func save() { if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: Self.key) } }
    func reset() { value = Settings() }
}
