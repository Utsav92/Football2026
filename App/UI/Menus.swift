import SwiftUI
import FootballGame
import FootballData
import FootballModes
import FootballInput

// MARK: Splash & main menu

struct SplashView: View {
    let router: AppRouter
    @State private var shown = false
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("FOOTBALL").font(.system(size: 72, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("2026").font(.system(size: 120, weight: .black, design: .rounded)).foregroundStyle(Theme.accent).offset(y: -22)
                if let e = router.loadError { Text(e).foregroundStyle(.red) } else { ProgressView().tint(.white) }
            }
            .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.94)
        }
        .task {
            withAnimation(.easeOut(duration: 0.8)) { shown = true }
            router.bootstrap()
            await CharacterAssets.shared.load()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if router.loadError == nil { router.screen = .mainMenu }
        }
    }
}

struct MainMenuView: View {
    let router: AppRouter
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            HStack(spacing: 60) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("FOOTBALL").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text("2026").font(.system(size: 78, weight: .black, design: .rounded)).foregroundStyle(Theme.accent).offset(y: -12)
                    Text("11v11 · fictional clubs · \(router.database?.clubs.count ?? 0) teams · \(router.database?.allPlayers.count ?? 0) players")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    Text(router.gamepad.count == 0 ? "No controller detected — keyboard active" : "Controllers: " + router.gamepad.names.joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 6)
                }
                VStack(spacing: 12) {
                    MenuButton(title: "Quick Match", subtitle: "Human vs AI") { router.screen = .quickMatch(versus: false) }
                    MenuButton(title: "Local Versus", subtitle: "Two controllers, one Mac", enabled: true) { router.screen = .quickMatch(versus: true) }
                    MenuButton(title: "Tournament", subtitle: "League, groups, knockout") { router.screen = .tournament }
                    MenuButton(title: "Career", subtitle: router.career.map { "Continue · Season \($0.season)" } ?? "Manage a club") { router.screen = .career }
                    MenuButton(title: "Training", subtitle: "Shooting · passing · penalties") { router.screen = .training }
                    MenuButton(title: "Settings") { router.screen = .settings }
                    MenuButton(title: "Quit") { NSApp.terminate(nil) }
                }
            }
            if let m = router.careerMessage { VStack { Spacer(); Text(m).padding(8).background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white).padding() } }
        }
    }
}

// MARK: Quick match setup

struct QuickMatchView: View {
    let router: AppRouter
    let versus: Bool
    @State private var homeID = 1
    @State private var awayID = 2
    @State private var formation: Formation = .f433
    @State private var side = 0               // 0 home, 1 away
    @State private var minutes = 6
    @State private var difficulty = 3
    @State private var tod: TimeOfDay = .day
    @State private var weather: Weather = .clear
    @State private var stadiumFrom = 0
    @State private var loaded = false

    var body: some View {
        ScreenFrame(title: versus ? "Local Versus" : "Quick Match", back: { router.screen = .mainMenu }) {
            if let db = router.database, let h = db.club(homeID), let a = db.club(awayID) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 12) {
                        Panel(title: "Teams") {
                            ClubPicker(title: "Home", clubs: db.clubs, selection: $homeID)
                            ClubPicker(title: "Away", clubs: db.clubs, selection: $awayID)
                            HStack(spacing: 24) {
                                teamCard(h); Text("VS").font(.system(size: 22, weight: .black)); teamCard(a)
                            }.frame(maxWidth: .infinity)
                        }
                        Panel(title: "Formation (your team)") {
                            Picker("", selection: $formation) { ForEach(Formation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                            FormationPreview(formation: formation, color: Color(red: Double(h.primary.r), green: Double(h.primary.g), blue: Double(h.primary.b))).frame(height: 150)
                        }
                    }
                    VStack(spacing: 12) {
                        Panel(title: "Match") {
                            if !versus { Picker("You control", selection: $side) { Text("Home").tag(0); Text("Away").tag(1) }.pickerStyle(.segmented) }
                            Picker("Length", selection: $minutes) { ForEach([3, 6, 10, 15], id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.segmented)
                            Picker("Difficulty", selection: $difficulty) { ForEach(Difficulty.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) } }
                            Picker("Time of day", selection: $tod) { ForEach(TimeOfDay.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            Picker("Weather", selection: $weather) { ForEach(Weather.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            Picker("Stadium", selection: $stadiumFrom) { Text(h.stadium).tag(0); Text(a.stadium).tag(1) }.pickerStyle(.segmented)
                        }
                        if versus { Panel(title: "Controllers") { Text(router.gamepad.count >= 2 ? "Two controllers connected: Home = pad 1, Away = pad 2" : "Connect two gamepads (\(router.gamepad.count)/2). With one pad, the keyboard plays Home.").font(.callout) } }
                        MenuButton(title: "Kick Off") {
                            var cfg = router.makeConfig(home: h, away: a, humans: versus ? [.home, .away] : [side == 0 ? .home : .away], formation: side == 0 || versus ? formation : nil,
                                                        minutes: minutes, difficulty: Difficulty(rawValue: difficulty))
                            if !versus && side == 1 { cfg.away = a.teamSetup(formation: formation) }
                            var s = MatchSession(config: cfg, mode: .quick)
                            s.homeClubID = homeID; s.awayClubID = awayID; s.timeOfDay = tod; s.weather = weather; s.stadiumName = stadiumFrom == 0 ? h.stadium : a.stadium
                            router.start(s, returnTo: .mainMenu) { _ in }
                        }
                    }.frame(width: 380)
                }
            }
        }
        .onAppear {
            guard !loaded, let db = router.database else { return }
            loaded = true
            homeID = db.clubs[0].id; awayID = db.clubs[min(5, db.clubs.count - 1)].id
            formation = db.clubs[0].preferredFormation
            minutes = router.settings.value.matchMinutes; difficulty = router.settings.value.difficulty
        }
        .onChange(of: homeID) { _, id in if let c = router.database?.club(id) { formation = c.preferredFormation } }
    }

    func teamCard(_ c: ClubRecord) -> some View {
        VStack(spacing: 4) {
            ClubBadge(club: c, size: 54)
            Text(c.name).font(.system(size: 14, weight: .bold)); Text(c.identity).font(.system(size: 11)).opacity(0.7)
            Text("Rating \(c.strength) · \(c.preferredFormation.rawValue)").font(.system(size: 11)).opacity(0.7)
        }.frame(width: 190)
    }
}

struct FormationPreview: View {
    let formation: Formation
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.12, green: 0.4, blue: 0.14))
                Path { p in p.move(to: CGPoint(x: g.size.width / 2, y: 0)); p.addLine(to: CGPoint(x: g.size.width / 2, y: g.size.height)) }.stroke(.white.opacity(0.4), lineWidth: 1)
                ForEach(Array(formation.slots.enumerated()), id: \.offset) { _, s in
                    Circle().fill(color).overlay(Circle().stroke(.white, lineWidth: 1.5)).frame(width: 14, height: 14)
                        .position(x: CGFloat(s.depth) * g.size.width, y: (CGFloat(s.lateral) * 0.5 + 0.5) * (g.size.height - 20) + 10)
                }
            }
        }
    }
}

// MARK: Training

struct TrainingMenuView: View {
    let router: AppRouter
    @State private var clubID = 1
    var body: some View {
        ScreenFrame(title: "Training", back: { router.screen = .mainMenu }) {
            if let db = router.database {
                Panel(title: "Your club") { ClubPicker(title: "Club", clubs: db.clubs, selection: $clubID) }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TrainingKind.allCases, id: \.self) { k in
                        VStack(spacing: 8) {
                            Image(systemName: icon(k)).font(.system(size: 30)).foregroundStyle(Theme.accent).frame(height: 36)
                            Text(k.rawValue).font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(blurb(k)).font(.system(size: 11)).multilineTextAlignment(.center).opacity(0.7).frame(height: 48, alignment: .top)
                            Spacer(minLength: 0)
                            Button("Start") {
                                guard let h = db.club(clubID), let a = db.clubs.first(where: { $0.id != clubID }) else { return }
                                var s = MatchSession(config: router.makeConfig(home: h, away: a, humans: [.home], minutes: 90), mode: .training(k))
                                s.homeClubID = h.id; s.awayClubID = a.id; s.stadiumName = h.stadium
                                router.start(s, returnTo: .training) { _ in }
                            }.buttonStyle(.borderedProminent).tint(Theme.accent)
                        }
                        .padding(14).frame(width: 190, height: 210).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                }
                Text("Drills run on the real match engine. Esc pauses; the HUD shows attempts, goals and streaks.").font(.callout).foregroundStyle(.white.opacity(0.6))
            }
        }.onAppear { if let id = router.database?.clubs.first?.id { clubID = id } }
    }
    func icon(_ k: TrainingKind) -> String { switch k { case .freePractice: return "figure.run"; case .shooting: return "scope"; case .passing: return "arrow.triangle.swap"; case .penalties: return "target"; case .freeKicks: return "flag" } }
    func blurb(_ k: TrainingKind) -> String {
        switch k { case .freePractice: return "Roam the pitch with no opposition."; case .shooting: return "Random spots against a keeper; resets after every attempt."
        case .passing: return "Keep the ball moving between four teammates."; case .penalties: return "Beat the keeper from the spot, again and again."; case .freeKicks: return "Direct free kicks over a defensive wall." }
    }
}

// MARK: Tournament

struct TournamentView: View {
    let router: AppRouter
    @State private var formatIndex = 0
    @State private var clubCount = 8
    @State private var userClub = 1
    var body: some View {
        ScreenFrame(title: "Tournament", back: { router.screen = .mainMenu }) {
            if let db = router.database {
                if let t = router.tournament { dashboard(t, db) }
                else {
                    Panel(title: "New tournament") {
                        Picker("Format", selection: $formatIndex) { Text("League (home & away)").tag(0); Text("Groups + Knockout").tag(1); Text("Knockout").tag(2) }.pickerStyle(.segmented)
                        Picker("Clubs", selection: $clubCount) { ForEach([4, 8, 16], id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                        ClubPicker(title: "Your club", clubs: db.clubs, selection: $userClub)
                        MenuButton(title: "Create") {
                            let f: TournamentFormat = formatIndex == 0 ? .league(double: true) : (formatIndex == 1 ? .groupsThenKnockout(groups: clubCount >= 8 ? 4 : 2, advancePerGroup: 2) : .knockout)
                            router.newTournament(format: f, clubCount: clubCount, userClub: userClub)
                        }
                    }.frame(maxWidth: 520)
                }
            }
        }.onAppear { if let id = router.database?.clubs.first?.id { userClub = id } }
    }

    @ViewBuilder func dashboard(_ t: Tournament, _ db: GameDatabase) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                if let champ = t.champion, let c = db.club(champ) {
                    Panel(title: "Champions") { HStack { Image(systemName: "trophy.fill").font(.system(size: 34)).foregroundStyle(Theme.accent); ClubBadge(club: c, size: 40); Text(c.name).font(.system(size: 22, weight: .heavy, design: .rounded)) } }
                } else if let f = router.userFixture(in: t), let h = db.club(f.home), let a = db.club(f.away) {
                    Panel(title: "Your next match · \(f.stage)") {
                        HStack { Text(h.name).bold(); Text("vs"); Text(a.name).bold() }
                        HStack { MenuButton(title: "Play", width: 140) { router.playTournamentFixture(f) }; MenuButton(title: "Simulate", width: 140) { router.simulateUserFixture() } }
                    }
                } else if !t.isComplete {
                    Panel(title: "Round") { MenuButton(title: "Simulate round") { router.simulateTournamentRound() } }
                }
                if !t.pending.isEmpty { MenuButton(title: "Simulate other fixtures") { router.simulateTournamentRound() } }
                MenuButton(title: "Abandon tournament") { router.tournament = nil }
            }.frame(width: 320)
            ScrollView { VStack(spacing: 10) { tables(t, db); fixtures(t, db) } }
        }
    }

    @ViewBuilder func tables(_ t: Tournament, _ db: GameDatabase) -> some View {
        let groups = t.groupNames
        if groups.isEmpty { standing("Table", t.table(), db) } else { ForEach(groups, id: \.self) { standing($0, t.table(stage: $0), db) } }
    }

    func standing(_ title: String, _ rows: [StandingRow], _ db: GameDatabase) -> some View {
        Panel(title: title) {
            HStack { Text("#").frame(width: 22); Text("Club").frame(maxWidth: .infinity, alignment: .leading); Text("P").frame(width: 28); Text("W").frame(width: 28); Text("D").frame(width: 28); Text("L").frame(width: 28); Text("GD").frame(width: 34); Text("Pts").frame(width: 34) }.font(.system(size: 11, weight: .bold)).opacity(0.6)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                HStack { Text("\(i + 1)").frame(width: 22)
                    Text(db.club(r.club)?.name ?? "?").frame(maxWidth: .infinity, alignment: .leading).fontWeight(r.club == router.tournamentUserClub ? .bold : .regular)
                    Text("\(r.played)").frame(width: 28); Text("\(r.won)").frame(width: 28); Text("\(r.drawn)").frame(width: 28); Text("\(r.lost)").frame(width: 28)
                    Text("\(r.goalDifference)").frame(width: 34); Text("\(r.points)").frame(width: 34).bold() }.font(.system(size: 12, design: .monospaced))
            }
        }
    }

    func fixtures(_ t: Tournament, _ db: GameDatabase) -> some View {
        Panel(title: "Fixtures & results") {
            ForEach(t.fixtures.filter { $0.isKnockout || $0.result != nil || $0.round == (t.pending.first?.round ?? 0) }.suffix(40)) { f in
                HStack {
                    Text(f.stage).frame(width: 110, alignment: .leading).opacity(0.6)
                    Text(db.club(f.home)?.shortName ?? "?").frame(width: 44, alignment: .trailing)
                    Text(f.result.map { "\($0.homeGoals) – \($0.awayGoals)" } ?? "v").frame(width: 60).bold()
                    Text(db.club(f.away)?.shortName ?? "?").frame(width: 44, alignment: .leading)
                    if let r = f.result, r.homeGoals == r.awayGoals, let w = r.penaltyWinner { Text("(\(db.club(w)?.shortName ?? "") on pens)").opacity(0.6) }
                }.font(.system(size: 12, design: .monospaced))
            }
        }
    }
}
