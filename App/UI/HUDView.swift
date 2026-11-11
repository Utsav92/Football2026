import SwiftUI
import FootballGame
import FootballPhysics

struct HUDView: View {
    let model: GameModel

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                scoreboard
                Spacer()
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) { playerCard; controlsCard }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) { if model.debugOn { debugCard }; minimap; statsCard }
                }
            }
            .padding(18)

            if let banner = model.banner {
                VStack(spacing: 6) {
                    Text(banner).font(.system(size: 58, weight: .heavy, design: .rounded))
                    if let sub = model.subBanner { Text(sub).font(.system(size: 22, weight: .semibold, design: .rounded)).opacity(0.9) }
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 8).transition(.scale.combined(with: .opacity))
            }
            if !model.shootoutText.isEmpty && model.summaryTitle != "" && model.banner != nil || !model.shootoutText.isEmpty { VStack { Spacer(); Text("SHOOTOUT  " + model.shootoutText).font(.system(size: 20, weight: .heavy, design: .rounded)).padding(12).background(.black.opacity(0.65), in: Capsule()).padding(.bottom, 130) } }
            if model.charging { VStack { Spacer(); chargeBar.padding(.bottom, 110) } }
            if model.replayActive {
                VStack { HStack { Label("REPLAY", systemImage: "play.rectangle.fill").font(.system(size: 20, weight: .heavy)).padding(10).background(.red, in: Capsule()); Spacer() }.padding(.top, 70).padding(.leading, 24); Spacer()
                    Text("Press T or Return to skip").font(.caption).padding(6).background(.black.opacity(0.5), in: Capsule()).padding(.bottom, 20) }
            }
            if let t = model.toast { VStack { Spacer(); Text(t).padding(10).background(.black.opacity(0.65), in: Capsule()).padding(.bottom, 70) } }
            if model.subPrompt { VStack { HStack { Spacer(); Label("Tired player: pause (Esc) to substitute", systemImage: "arrow.left.arrow.right").font(.caption.bold()).padding(8).background(.orange, in: Capsule()).foregroundStyle(.black); Spacer() }.padding(.top, 70); Spacer() } }
            if !model.trainingText.isEmpty { VStack { HStack { Spacer(); Text(model.trainingText).font(.system(size: 18, weight: .bold, design: .rounded)).padding(10).background(.black.opacity(0.55), in: Capsule()); Spacer() }.padding(.top, 64); Spacer() } }
            if model.paused {
                Text("PAUSED").font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(30).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.banner)
        .allowsHitTesting(false)
    }

    private var scoreboard: some View {
        HStack(spacing: 0) {
            teamCell(model.homeName, model.homeColor)
            Text("\(model.homeScore)  –  \(model.awayScore)")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()).padding(.horizontal, 18)
            teamCell(model.awayName, model.awayColor)
            Text(model.clockText).font(.system(size: 20, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 16).frame(height: 44).background(.black.opacity(0.35))
        }
        .foregroundStyle(.white).frame(height: 44)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func teamCell(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 8) { Circle().fill(color).frame(width: 12, height: 12); Text(name).font(.system(size: 16, weight: .bold, design: .rounded)) }
            .padding(.horizontal, 14)
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(model.playerNumber)").font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .frame(width: 38, height: 30).background(.yellow, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.playerName).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(model.playerRole).font(.caption2).opacity(0.7)
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(model.playerStamina > 0.25 ? Color.green : Color.orange).frame(width: 150 * CGFloat(model.playerStamina))
            }.frame(width: 150, height: 7)
            Text("STAMINA").font(.system(size: 9, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(.white).padding(12).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var chargeBar: some View {
        VStack(spacing: 4) {
            Text(model.chargeKind).font(.caption2.weight(.bold)).foregroundStyle(.white)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(model.chargeKind == "SHOT" ? Color.red : Color.yellow).frame(width: 240 * CGFloat(model.chargeLevel))
            }.frame(width: 240, height: 10)
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CONTROLS").font(.system(size: 9, weight: .bold)).opacity(0.7)
            Group {
                Text("WASD move · Shift sprint · Q switch")
                Text("E pass · G through · F lob · Space shoot")
                Text("X tackle · V slide · Ctrl jockey · Z finesse · IJKL skills")
                Text("C camera · T replay · Esc pause")
            }.font(.system(size: 11, design: .rounded))
        }
        .foregroundStyle(.white).padding(10).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text("POSSESSION").font(.system(size: 9, weight: .bold)).opacity(0.7); Spacer(); Text("\(model.possessionHome)% – \(100 - model.possessionHome)%").font(.system(size: 11, design: .monospaced)) }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(model.homeColor).frame(width: g.size.width * CGFloat(model.possessionHome) / 100)
                    Rectangle().fill(model.awayColor)
                }.clipShape(Capsule())
            }.frame(height: 6)
            HStack { Text("SHOTS").font(.system(size: 9, weight: .bold)).opacity(0.7); Spacer(); Text(model.shotsText).font(.system(size: 11, design: .monospaced)) }
            HStack { Text(model.cameraName).font(.system(size: 10, weight: .semibold)); Spacer(); Text("\(model.fps) fps · \(String(format: "%.1f", model.frameMS)) ms").font(.system(size: 10, design: .monospaced)).opacity(0.7) }
        }
        .foregroundStyle(.white).frame(width: 210).padding(10).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var minimap: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.12, green: 0.4, blue: 0.14)))
            let w = size.width, h = size.height
            let line = GraphicsContext.Shading.color(.white.opacity(0.8))
            ctx.stroke(Path(CGRect(x: 2, y: 2, width: w - 4, height: h - 4)), with: line, lineWidth: 1)
            var mid = Path(); mid.move(to: CGPoint(x: w / 2, y: 2)); mid.addLine(to: CGPoint(x: w / 2, y: h - 2)); ctx.stroke(mid, with: line, lineWidth: 1)
            ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - 12, y: h / 2 - 12, width: 24, height: 24)), with: line, lineWidth: 1)
            func pt(_ x: Float, _ z: Float) -> CGPoint {
                CGPoint(x: CGFloat((x + PitchSpec.halfLength) / PitchSpec.length) * (w - 8) + 4, y: CGFloat((z + PitchSpec.halfWidth) / PitchSpec.width) * (h - 8) + 4)
            }
            for d in model.minimap {
                let p = pt(d.x, d.z)
                if d.isBall { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white)); continue }
                let r: CGFloat = d.controlled ? 4.5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(d.team == .home ? model.homeColor : model.awayColor))
                if d.controlled { ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 1, y: p.y - r - 1, width: 2 * r + 2, height: 2 * r + 2)), with: .color(.yellow), lineWidth: 1.2) }
            }
        }
        .frame(width: 210, height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.4)))
    }

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AI STATES").font(.system(size: 9, weight: .bold)).opacity(0.7)
            ForEach(Array(model.debugCounts.enumerated()), id: \.offset) { _, kv in
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: PitchScene.stateColor(AIState.allCases.first { $0.label == kv.0 } ?? .idle))).frame(width: 8, height: 8)
                    Text(kv.0).font(.system(size: 10, design: .monospaced)); Spacer(); Text("\(kv.1)").font(.system(size: 10, design: .monospaced))
                }
            }
            Text(model.lodText).font(.system(size: 9, design: .monospaced)).opacity(0.6)
        }
        .foregroundStyle(.white).frame(width: 210).padding(10).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}
