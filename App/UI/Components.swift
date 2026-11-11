import SwiftUI
import FootballGame
import FootballData

enum Theme {
    static let bg = LinearGradient(colors: [Color(red: 0.04, green: 0.09, blue: 0.14), Color(red: 0.05, green: 0.2, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panel = Color.white.opacity(0.07)
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.25)
}

struct MenuButton: View {
    let title: String
    var subtitle: String? = nil
    var enabled = true
    var width: CGFloat = 300
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                if let s = subtitle { Text(s).font(.system(size: 12)).opacity(0.7) }
            }
            .frame(width: width, height: subtitle == nil ? 46 : 58)
            .background(RoundedRectangle(cornerRadius: 12).fill(enabled ? Theme.accent : Color.gray.opacity(0.4)))
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.5))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct Panel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = title { Text(t.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
            content
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
    }
}

struct ScreenFrame<Content: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("‹ Back", action: back).buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(title).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Spacer(); Color.clear.frame(width: 60)
                }
                content
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

struct ClubBadge: View {
    let club: ClubRecord
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().fill(Color(red: Double(club.primary.r), green: Double(club.primary.g), blue: Double(club.primary.b)))
            Circle().stroke(Color(red: Double(club.secondary.r), green: Double(club.secondary.g), blue: Double(club.secondary.b)), lineWidth: size * 0.12)
            Text(club.shortName.prefix(1)).font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(Color(red: Double(club.secondary.r), green: Double(club.secondary.g), blue: Double(club.secondary.b)))
        }.frame(width: size, height: size)
    }
}

struct ClubPicker: View {
    let title: String
    let clubs: [ClubRecord]
    @Binding var selection: Int
    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(clubs) { c in Text("\(c.name)  (\(c.strength))").tag(c.id) }
            }.labelsHidden().frame(maxWidth: 320)
        }
    }
}

extension Role.Line { var short: String { switch self { case .goalkeeper: return "GK"; case .defender: return "DEF"; case .midfielder: return "MID"; case .forward: return "FWD" } } }
func money(_ v: Int) -> String { abs(v) >= 1_000_000 ? String(format: "%@%.1fM", v < 0 ? "-" : "", Double(abs(v)) / 1e6) : String(format: "%@%dk", v < 0 ? "-" : "", abs(v) / 1000) }
