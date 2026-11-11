import SwiftUI
import FootballInput

struct SettingsView: View {
    let router: AppRouter
    @State private var tab = 0
    @State private var ctx: ControlContext = .attack
    var s: AppSettings { router.settings }

    var body: some View {
        ScreenFrame(title: "Settings", back: { router.screen = .mainMenu }) {
            Picker("", selection: $tab) { Text("Controls").tag(0); Text("Graphics").tag(1); Text("Audio").tag(2); Text("Gameplay").tag(3) }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                switch tab {
                case 0: controls
                case 1: graphics
                case 2: audio
                default: gameplay
                }
            }
            HStack { Button("Reset all settings") { s.reset() }.buttonStyle(.bordered); Text("Settings are saved automatically and persist between launches.").font(.caption).opacity(0.6) }
        }
    }

    var controls: some View {
        VStack(spacing: 10) {
            Panel(title: "Devices") {
                if router.gamepad.count == 0 { Text("No controller connected. Keyboard: WASD move · Shift sprint · E pass · Space shoot · F lob · G through · Q switch · X tackle · V slide · Z finesse · Ctrl jockey · IJKL skill moves · C camera · T replay · B debug · Esc pause").font(.callout) }
                else { ForEach(Array(router.gamepad.names.enumerated()), id: \.offset) { i, n in Text("Player \(i + 1): \(n)") } }
            }
            Panel(title: "Stick response") {
                slider("Dead zone", Binding(get: { s.value.controller.deadZone }, set: { s.value.controller.deadZone = $0 }), 0...0.4)
                slider("Response curve", Binding(get: { s.value.controller.curve }, set: { s.value.controller.curve = $0 }), 1...2.5)
                slider("Trigger threshold", Binding(get: { s.value.controller.triggerThreshold }, set: { s.value.controller.triggerThreshold = $0 }), 0.1...0.8)
            }
            Panel(title: "Button mapping") {
                Picker("Context", selection: $ctx) { Text("Attack (your team has the ball)").tag(ControlContext.attack); Text("Defence").tag(ControlContext.defense) }.pickerStyle(.segmented)
                ForEach(GameAction.allCases, id: \.self) { a in
                    HStack {
                        Text(a.rawValue).frame(width: 130, alignment: .leading)
                        Picker("", selection: Binding(get: { current(a) }, set: { if let b = $0 { s.value.bindings.remap(b, to: a, in: ctx) } })) {
                            Text("—").tag(PadButton?.none)
                            ForEach(PadButton.allCases.filter { ![.dpadUp, .dpadDown, .dpadLeft, .dpadRight].contains($0) }, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }.labelsHidden().frame(width: 180)
                    }
                }
                Button("Restore default layout") { s.value.bindings = .standard }.buttonStyle(.bordered)
            }
        }
    }
    func current(_ a: GameAction) -> PadButton? { s.value.bindings.bindings(ctx).first { $0.value == a }?.key }

    var graphics: some View {
        Panel(title: "Quality preset") {
            Picker("", selection: Binding(get: { s.value.graphics }, set: { s.value.graphics = $0 })) { ForEach(GraphicsPreset.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            Text("Low: 1,200 spectators, 6 stand rows, no shadows, no ad boards, shorter LOD distances.\nMedium: 4,000 spectators, 10 rows, shadows, ad boards.\nHigh: 9,000 spectators, 14 rows, shadows, denser rain, longer LOD distances.\nApplies to the next match.").font(.callout).opacity(0.75)
        }
    }

    var audio: some View {
        Panel(title: "Volume") {
            slider("Master", Binding(get: { s.value.masterVolume }, set: { s.value.masterVolume = $0 }), 0...1)
            slider("Music", Binding(get: { s.value.musicVolume }, set: { s.value.musicVolume = $0 }), 0...1)
            slider("Effects", Binding(get: { s.value.sfxVolume }, set: { s.value.sfxVolume = $0 }), 0...1)
            slider("Crowd", Binding(get: { s.value.crowdVolume }, set: { s.value.crowdVolume = $0 }), 0...1)
            Toggle("Stadium announcements (system text-to-speech)", isOn: Binding(get: { s.value.announcements }, set: { s.value.announcements = $0 }))
        }
    }

    var gameplay: some View {
        Panel(title: "Match defaults") {
            Picker("Match length", selection: Binding(get: { s.value.matchMinutes }, set: { s.value.matchMinutes = $0 })) { ForEach([3, 6, 10, 15], id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.segmented)
            Picker("Default difficulty", selection: Binding(get: { s.value.difficulty }, set: { s.value.difficulty = $0 })) { ForEach(Difficulty.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) } }
            Picker("Default camera", selection: Binding(get: { s.value.defaultCamera }, set: { s.value.defaultCamera = $0 })) { ForEach(CameraMode.selectable, id: \.rawValue) { Text($0.name).tag($0.rawValue) } }
            Toggle("Automatic penalty / free-kick cameras", isOn: Binding(get: { s.value.autoSetPieceCamera }, set: { s.value.autoSetPieceCamera = $0 }))
        }
    }

    func slider(_ t: String, _ v: Binding<Float>, _ r: ClosedRange<Float>) -> some View {
        HStack { Text(t).frame(width: 140, alignment: .leading); Slider(value: v, in: r); Text(String(format: "%.2f", v.wrappedValue)).frame(width: 44).font(.system(.body, design: .monospaced)) }
    }
}
import FootballGame
