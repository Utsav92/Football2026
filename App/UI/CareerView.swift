import SwiftUI
import FootballGame
import FootballData
import FootballModes

struct CareerView: View {
    let router: AppRouter
    @State private var tab = 0
    @State private var newClub = 1
    @State private var minRating = 60
    @State private var message = ""

    var body: some View {
        ScreenFrame(title: "Career", back: { router.screen = .mainMenu }) {
            if let db = router.database {
                if let c = router.career { dashboard(c) }
                else {
                    Panel(title: "Start a career") {
                        Text("Pick a fictional club, manage the squad and finances, and play or simulate a 38-round league season. Progress saves automatically.").font(.callout)
                        ClubPicker(title: "Club", clubs: db.clubs, selection: $newClub)
                        MenuButton(title: "Begin career") { router.newCareer(clubID: newClub) }
                    }.frame(maxWidth: 560)
                }
            }
        }.onAppear { if let id = router.database?.clubs.last?.id, router.career == nil { newClub = id } }
    }

    @ViewBuilder func dashboard(_ c: CareerState) -> some View {
        Picker("", selection: $tab) { Text("Overview").tag(0); Text("Squad").tag(1); Text("Transfers").tag(2); Text("Training").tag(3); Text("Table").tag(4) }.pickerStyle(.segmented).labelsHidden()
        if !message.isEmpty { Text(message).font(.callout).foregroundStyle(Theme.accent) }
        ScrollView {
            switch tab {
            case 0: overview(c)
            case 1: squad(c)
            case 2: transfers(c)
            case 3: training(c)
            default: table(c)
            }
        }
    }

    func overview(_ c: CareerState) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Panel(title: c.club.name) { Text("Season \(c.season) · Round \(c.week)/\(c.totalRounds)").font(.title3.bold()); Text("League position: \(c.tablePosition)").font(.callout); Text(c.club.identity).opacity(0.7) }
                Panel(title: "Finances") { Text("Balance \(money(c.finances.balance))").font(.title3.bold()); Text("Weekly wage bill \(money(c.weeklyWageBill)) / cap \(money(c.finances.wageBudget))").font(.callout); Text("Weekly income \(money(c.finances.weeklyIncome))").font(.callout) }
            }
            if let f = c.userFixture(), let h = c.clubs.first(where: { $0.id == f.home }), let a = c.clubs.first(where: { $0.id == f.away }) {
                Panel(title: "Next fixture · round \(f.round)") {
                    HStack { Text(h.name).bold(); Text("vs"); Text(a.name).bold() }
                    HStack { MenuButton(title: "Play match", width: 220) { router.playCareerFixture() }; MenuButton(title: "Simulate week", width: 220) { router.simulateCareerWeek() } }
                }
            } else { Panel(title: "Season complete") { Text("Season \(c.season - 1) finished.").bold() } }
            Panel(title: "News") { ForEach(Array(c.news.suffix(6).reversed().enumerated()), id: \.offset) { _, n in Text("• " + n).font(.system(size: 12)) } }
            if !c.history.isEmpty { Panel(title: "History") { ForEach(c.history, id: \.season) { h in Text("Season \(h.season): finished \(h.position)th · \(h.points) pts · champions: \(router.club(h.champion)?.name ?? "?")").font(.system(size: 12)) } } }
            Button("Save now") { router.saveCareer(); message = "Saved" }.buttonStyle(.bordered)
        }
    }

    func squad(_ c: CareerState) -> some View {
        Panel(title: "Squad (\(c.club.squad.count)/\(CareerState.maxSquad))") {
            ForEach(c.club.squad.sorted { $0.rating > $1.rating }) { p in
                HStack(spacing: 8) {
                    Text("#\(p.number)").frame(width: 34, alignment: .leading).opacity(0.6)
                    Text(p.name).frame(width: 130, alignment: .leading)
                    Text(p.role.rawValue.uppercased()).frame(width: 34)
                    Text("\(p.rating)").frame(width: 30).bold()
                    Text("\(p.age)y").frame(width: 30)
                    Text("\(p.contractYears)y").frame(width: 30)
                    Text(p.injuredWeeks > 0 ? "inj \(p.injuredWeeks)w" : "fit \(Int(p.fitness * 100))%").frame(width: 70).foregroundStyle(p.injuredWeeks > 0 ? .red : .white)
                    Text(money(p.value)).frame(width: 60)
                    Button("Renew") { var s = c; if case .failure(let e) = s.renewContract(playerID: p.id, years: 3) { message = "Renew failed: \(e)" } else { router.career = s; message = "Renewed \(p.name)" } }.buttonStyle(.bordered).controlSize(.small)
                    Button("Sell") { var s = c; switch s.sell(playerID: p.id) { case .success(let price): router.career = s; router.saveCareer(); message = "Sold \(p.name) for \(money(price))"; case .failure(let e): message = "Cannot sell: \(e)" } }.buttonStyle(.bordered).controlSize(.small)
                }.font(.system(size: 12, design: .monospaced))
            }
        }
    }

    func transfers(_ c: CareerState) -> some View {
        Panel(title: "Transfer market · budget \(money(c.finances.balance))") {
            Picker("Min rating", selection: $minRating) { ForEach([50, 60, 65, 70, 75], id: \.self) { Text("\($0)+").tag($0) } }.pickerStyle(.segmented)
            ForEach(Array(c.marketListings(minRating: minRating, maxPrice: max(c.finances.balance, 1_000_000)).prefix(30)), id: \.player.id) { l in
                HStack(spacing: 8) {
                    Text(l.player.name).frame(width: 130, alignment: .leading); Text(l.player.role.rawValue.uppercased()).frame(width: 34)
                    Text("\(l.player.rating)").frame(width: 30).bold(); Text("\(l.player.age)y").frame(width: 30)
                    Text(router.club(l.clubID)?.shortName ?? "").frame(width: 40); Text(money(l.askingPrice)).frame(width: 70)
                    Button("Buy") { var s = c; switch s.buy(playerID: l.player.id) { case .success: router.career = s; router.saveCareer(); message = "Signed \(l.player.name)"; case .failure(let e): message = "Cannot buy: \(e)" } }.buttonStyle(.bordered).controlSize(.small)
                }.font(.system(size: 12, design: .monospaced))
            }
        }
    }

    func training(_ c: CareerState) -> some View {
        Panel(title: "Weekly training focus") {
            Picker("", selection: Binding(get: { c.training }, set: { var s = c; s.setTraining($0); router.career = s; router.saveCareer() })) {
                ForEach(TrainingFocus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text("Young, high-potential, high-morale players improve fastest; players over 31 stop improving and slowly lose pace.").font(.callout).opacity(0.7)
            Picker("Formation", selection: Binding(get: { c.formation }, set: { var s = c; s.formation = $0; router.career = s })) { ForEach(Formation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        }
    }

    func table(_ c: CareerState) -> some View {
        Panel(title: "League table") {
            ForEach(Array(c.league.table().enumerated()), id: \.element.id) { i, r in
                HStack { Text("\(i + 1)").frame(width: 24); Text(router.club(r.club)?.name ?? "?").frame(width: 200, alignment: .leading).fontWeight(r.club == c.clubID ? .bold : .regular)
                    Text("\(r.played)").frame(width: 30); Text("\(r.goalDifference)").frame(width: 36); Text("\(r.points)").frame(width: 36).bold() }.font(.system(size: 12, design: .monospaced))
            }
        }
    }
}
