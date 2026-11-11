import SwiftUI
import FootballGame
import FootballData
import FootballModes
import FootballInput

enum Screen: Equatable {
    case splash, mainMenu, quickMatch(versus: Bool), training, tournament, career, settings
    case match
}

/// Navigation + shared services (database, input, audio, career save). One instance for the app.
@MainActor @Observable
final class AppRouter {
    var screen: Screen = .splash
    var database: GameDatabase?
    var loadError: String?
    var match: GameModel?
    var tournament: Tournament?
    var tournamentUserClub = 0
    var career: CareerState?
    var careerMessage: String?
    var toast: String?

    let settings = AppSettings.shared
    let keyboard = KeyboardInput()
    let gamepad = GamepadInput()
    let audio = AudioSystem()
    private var returnTo: Screen = .mainMenu
    private var pendingOutcomeHandler: ((MatchOutcome) -> Void)?

    static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Football2026", isDirectory: true)
        return dir.appendingPathComponent("career.json")
    }

    func bootstrap() {
        if let i = CommandLine.arguments.firstIndex(of: "--graphics"), i + 1 < CommandLine.arguments.count, let g = GraphicsPreset.allCases.first(where: { $0.rawValue.lowercased() == CommandLine.arguments[i + 1] }) { settings.value.graphics = g }
        guard database == nil else { return }
        guard let url = Bundle.main.url(forResource: "clubs", withExtension: "json") else { loadError = "clubs.json missing from app bundle"; return }
        do { database = try GameDatabase.load(from: url) } catch { loadError = "\(error)" }
        if let l = try? SaveManager(url: Self.saveURL).load() { career = l.state; careerMessage = l.restoredFromBackup ? "Loaded from backup save" : (l.migratedFrom.map { "Save migrated from v\($0)" }) }
    }

    func club(_ id: Int) -> ClubRecord? { database?.club(id) }

    // MARK: Launching matches

    func makeConfig(home: ClubRecord, away: ClubRecord, humans: Set<TeamSide>, formation: Formation? = nil, minutes: Int? = nil,
                    difficulty: Difficulty? = nil, seed: UInt64 = UInt64.random(in: 1...9999)) -> MatchConfig {
        let s = settings.value
        return MatchConfig(home: home.teamSetup(formation: formation), away: away.teamSetup(),
                           matchLengthSeconds: Float(minutes ?? s.matchMinutes) * 60, difficulty: difficulty ?? Difficulty(rawValue: s.difficulty) ?? .professional,
                           humanTeams: humans, seed: seed)
    }

    func start(_ session: MatchSession, returnTo: Screen, onFinish: @escaping (MatchOutcome) -> Void) {
        self.returnTo = returnTo
        let m = GameModel(session: session, settings: settings, keyboard: keyboard, gamepad: gamepad, audio: audio)
        m.onFinish = { [weak self] outcome in
            guard let self else { return }
            self.match = nil
            self.screen = self.returnTo
            onFinish(outcome)
        }
        match = m; screen = .match
    }

    func quitMatch() {
        match?.teardown(); match = nil; screen = returnTo
    }

    // MARK: Tournament flow

    func newTournament(format: TournamentFormat, clubCount: Int, userClub: Int) {
        guard let db = database else { return }
        var clubs = db.clubs.sorted { $0.strength > $1.strength }.prefix(clubCount).map { $0.id }
        if !clubs.contains(userClub) { clubs[clubs.count - 1] = userClub }
        tournament = Tournament(name: "Football 2026 Cup", format: format, clubs: clubs.sorted { (club($0)?.strength ?? 0) > (club($1)?.strength ?? 0) })
        tournamentUserClub = userClub
    }

    func userFixture(in t: Tournament) -> Fixture? { t.pending.first { $0.home == tournamentUserClub || $0.away == tournamentUserClub } }

    func playTournamentFixture(_ f: Fixture) {
        guard let h = club(f.home), let a = club(f.away) else { return }
        let userHome = f.home == tournamentUserClub
        var s = MatchSession(config: makeConfig(home: h, away: a, humans: [userHome ? .home : .away]), mode: .tournament(fixtureID: f.id))
        s.homeClubID = f.home; s.awayClubID = f.away; s.knockout = f.isKnockout; s.stadiumName = h.stadium
        start(s, returnTo: .tournament) { [weak self] outcome in
            guard let self, var t = self.tournament else { return }
            var r = MatchResult(homeGoals: outcome.homeGoals, awayGoals: outcome.awayGoals)
            r.extraTime = outcome.extraTime
            if f.isKnockout && outcome.knockoutTie, let w = outcome.shootoutWinner { r.penaltyWinner = w == .home ? f.home : f.away }   // decided by the engine's real shootout
            t.record(fixtureID: f.id, result: r); self.tournament = t
        }
    }

    func simulateTournamentRound() {
        guard var t = tournament, let db = database else { return }
        var rng = SplitMix64(seed: UInt64(t.fixtures.filter { $0.result != nil }.count) &+ 31)
        let todo = t.pending.filter { $0.home != tournamentUserClub && $0.away != tournamentUserClub }
        let round = (t.pending.map { $0.round }.min()) ?? 0
        for f in todo where f.round == round {
            let r = ResultSimulator.simulate(home: db.club(f.home)?.xiStrength() ?? 60, away: db.club(f.away)?.xiStrength() ?? 60,
                                             knockout: f.isKnockout, rng: &rng, homeID: f.home, awayID: f.away)
            t.record(fixtureID: f.id, result: r)
        }
        tournament = t
    }

    func simulateUserFixture() {
        guard var t = tournament, let db = database, let f = userFixture(in: t) else { return }
        var rng = SplitMix64(seed: UInt64(f.id) &* 131 &+ 7)
        let r = ResultSimulator.simulate(home: db.club(f.home)?.xiStrength() ?? 60, away: db.club(f.away)?.xiStrength() ?? 60, knockout: f.isKnockout, rng: &rng, homeID: f.home, awayID: f.away)
        t.record(fixtureID: f.id, result: r); tournament = t
    }

    // MARK: Career flow

    func newCareer(clubID: Int) {
        guard let db = database else { return }
        career = try? CareerState(database: db, clubID: clubID, seed: UInt64.random(in: 1...99999)); saveCareer()
    }

    func saveCareer() {
        guard let c = career else { return }
        do { try SaveManager(url: Self.saveURL).save(c) } catch { careerMessage = "Save failed: \(error)" }
    }

    func playCareerFixture() {
        guard let c = career, let f = c.userFixture(), let h = c.clubs.first(where: { $0.id == f.home }), let a = c.clubs.first(where: { $0.id == f.away }) else { return }
        let userHome = f.home == c.clubID
        var s = MatchSession(config: makeConfig(home: h, away: a, humans: [userHome ? .home : .away], formation: userHome ? c.formation : nil), mode: .career)
        s.homeClubID = f.home; s.awayClubID = f.away; s.stadiumName = h.stadium
        start(s, returnTo: .career) { [weak self] outcome in
            guard let self, var c = self.career else { return }
            c.advanceWeek(userResult: MatchResult(homeGoals: outcome.homeGoals, awayGoals: outcome.awayGoals)); self.career = c; self.saveCareer()
        }
    }

    func simulateCareerWeek() { guard var c = career else { return }; c.advanceWeek(); career = c; saveCareer() }
}
