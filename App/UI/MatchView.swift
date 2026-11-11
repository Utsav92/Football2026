import SwiftUI
import RealityKit
import FootballGame

struct MatchView: View {
    let model: GameModel
    let router: AppRouter
    @State private var outSlot: Int?
    @State private var showSubs = false

    var body: some View {
        ZStack {
            RealityView { content in await model.start(content: &content) }
            HUDView(model: model)
            if model.summaryVisible { SummaryOverlay(model: model) }
            if model.paused { PauseOverlay(model: model, router: router, outSlot: $outSlot, showSubs: $showSubs) }
        }
        .background(Color.black)
    }
}

struct SummaryOverlay: View {
    let model: GameModel
    var body: some View {
        VStack(spacing: 12) {
            Text(model.summaryTitle).font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("\(model.homeName)  \(model.homeScore) – \(model.awayScore)  \(model.awayName)").font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
            VStack(spacing: 4) {
                ForEach(model.summaryRows) { r in
                    HStack { Text(r.home).frame(width: 110, alignment: .trailing).monospacedDigit(); Text(r.label).frame(width: 170).opacity(0.7); Text(r.away).frame(width: 110, alignment: .leading).monospacedDigit() }.font(.system(size: 14, weight: .semibold))
                }
            }
            if model.summaryTitle == "FULL TIME" { Button("Continue") { model.finishMatch() }.buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction) }
        }
        .padding(28).background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white).transition(.opacity)
    }
}

struct PauseOverlay: View {
    let model: GameModel
    let router: AppRouter
    @Binding var outSlot: Int?
    @Binding var showSubs: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("PAUSED").font(.system(size: 36, weight: .heavy, design: .rounded))
                if showSubs { subPanel } else {
                    MenuButton(title: "Resume") { model.paused = false }
                    MenuButton(title: "Substitutions", subtitle: "\(model.subsLeft) left", enabled: model.training == nil && !model.onPitch.isEmpty) { model.refreshSubLists(); showSubs = true }
                    MenuButton(title: "Camera: \(model.cameraName)") { model.cameraRig.cycle(); model.cameraName = model.cameraRig.mode.name }
                    MenuButton(title: "Quit to menu") { router.quitMatch() }
                    Text(model.controllerText).font(.caption).opacity(0.6)
                }
            }
            .padding(30).foregroundStyle(.white)
        }
    }

    var subPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Substitutions · \(model.subsLeft) left").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("ON THE PITCH").font(.caption.bold()).opacity(0.6)
                    ForEach(model.onPitch) { p in
                        Button { outSlot = p.slot } label: {
                            HStack { Text(p.label); Spacer(); Text("\(Int(p.stamina * 100))%").foregroundStyle(p.stamina < 0.3 ? .orange : .green) }.frame(width: 300)
                                .padding(6).background(outSlot == p.slot ? Theme.accent.opacity(0.35) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading) {
                    Text("BENCH").font(.caption.bold()).opacity(0.6)
                    ForEach(model.bench) { b in
                        Button { if let o = outSlot { model.substitute(slot: o, bench: b.slot); outSlot = nil } } label: {
                            Text(b.label).frame(width: 280, alignment: .leading).padding(6).background(Color.white.opacity(outSlot == nil ? 0.04 : 0.14), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).disabled(outSlot == nil)
                    }
                    Text(outSlot == nil ? "Select a player to take off" : "Now choose a replacement").font(.caption).opacity(0.7)
                }
            }
            Button("Done") { showSubs = false; outSlot = nil }.buttonStyle(.borderedProminent).tint(Theme.accent)
        }.padding(20).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}
