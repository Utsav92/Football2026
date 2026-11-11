import Foundation
import FootballGame
import FootballData

public struct MatchResult: Codable, Equatable {
    public var homeGoals: Int
    public var awayGoals: Int
    public var extraTime = false
    /// Club id that won on penalties when a knockout tie finished level.
    public var penaltyWinner: Int?
    public init(homeGoals: Int, awayGoals: Int, extraTime: Bool = false, penaltyWinner: Int? = nil) {
        self.homeGoals = homeGoals; self.awayGoals = awayGoals; self.extraTime = extraTime; self.penaltyWinner = penaltyWinner
    }
}

public struct Fixture: Codable, Identifiable, Equatable {
    public var id: Int
    public var stage: String          // "League", "Group A", "Round of 16", "Final" ...
    public var round: Int
    public var home: Int              // club ids
    public var away: Int
    public var result: MatchResult?
    public var isKnockout: Bool
    public var winner: Int? {
        guard let r = result else { return nil }
        if r.homeGoals != r.awayGoals { return r.homeGoals > r.awayGoals ? home : away }
        return r.penaltyWinner
    }
}

public struct StandingRow: Codable, Equatable, Identifiable {
    public var id: Int { club }
    public var club: Int
    public var played = 0, won = 0, drawn = 0, lost = 0, goalsFor = 0, goalsAgainst = 0
    public var points: Int { won * 3 + drawn }
    public var goalDifference: Int { goalsFor - goalsAgainst }
}

public enum Standings {
    /// Points, goal difference, goals scored, head-to-head points among the tied clubs, then club id (stable).
    public static func table(fixtures: [Fixture], clubs: [Int]) -> [StandingRow] {
        var rows: [Int: StandingRow] = Dictionary(uniqueKeysWithValues: clubs.map { ($0, StandingRow(club: $0)) })
        for f in fixtures {
            guard let r = f.result, rows[f.home] != nil, rows[f.away] != nil else { continue }
            rows[f.home]!.played += 1; rows[f.away]!.played += 1
            rows[f.home]!.goalsFor += r.homeGoals; rows[f.home]!.goalsAgainst += r.awayGoals
            rows[f.away]!.goalsFor += r.awayGoals; rows[f.away]!.goalsAgainst += r.homeGoals
            if r.homeGoals > r.awayGoals { rows[f.home]!.won += 1; rows[f.away]!.lost += 1 }
            else if r.homeGoals < r.awayGoals { rows[f.away]!.won += 1; rows[f.home]!.lost += 1 }
            else { rows[f.home]!.drawn += 1; rows[f.away]!.drawn += 1 }
        }
        func h2h(_ a: Int, among group: Set<Int>) -> Int {
            fixtures.reduce(0) { acc, f in
                guard let r = f.result, group.contains(f.home), group.contains(f.away), (f.home == a || f.away == a) else { return acc }
                let gf = f.home == a ? r.homeGoals : r.awayGoals, ga = f.home == a ? r.awayGoals : r.homeGoals
                return acc + (gf > ga ? 3 : (gf == ga ? 1 : 0))
            }
        }
        var sorted = Array(rows.values).sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) != ($1.points, $1.goalDifference, $1.goalsFor)
                ? ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor) : $0.club < $1.club
        }
        // Head-to-head resolves clubs that are still level on the three primary criteria.
        var i = 0
        while i < sorted.count {
            var j = i + 1
            let key = (sorted[i].points, sorted[i].goalDifference, sorted[i].goalsFor)
            while j < sorted.count, (sorted[j].points, sorted[j].goalDifference, sorted[j].goalsFor) == key { j += 1 }
            if j - i > 1 {
                let g = Set(sorted[i..<j].map { $0.club })
                sorted[i..<j].sort { (h2h($0.club, among: g), -$0.club) > (h2h($1.club, among: g), -$1.club) }
            }
            i = j
        }
        return sorted
    }
}

public enum FixtureGenerator {
    /// Circle-method round robin: every club plays every other once (twice when `double`), home/away balanced.
    public static func roundRobin(clubs: [Int], double: Bool, stage: String = "League", startID: Int = 1) -> [Fixture] {
        var teams = clubs
        if teams.count % 2 == 1 { teams.append(-1) }          // bye
        let n = teams.count
        var out: [Fixture] = []
        var id = startID
        var rotation = teams
        var rounds: [[(Int, Int)]] = []
        for r in 0..<(n - 1) {
            var pairs: [(Int, Int)] = []
            for i in 0..<(n / 2) {
                var a = rotation[i], b = rotation[n - 1 - i]
                if (r + i) % 2 == 1 { swap(&a, &b) }       // alternate home/away
                if a != -1 && b != -1 { pairs.append((a, b)) }
            }
            rounds.append(pairs)
            rotation.insert(rotation.removeLast(), at: 1)
        }
        for (r, pairs) in rounds.enumerated() { for p in pairs { out.append(Fixture(id: id, stage: stage, round: r + 1, home: p.0, away: p.1, result: nil, isKnockout: false)); id += 1 } }
        if double {
            for (r, pairs) in rounds.enumerated() { for p in pairs { out.append(Fixture(id: id, stage: stage, round: n - 1 + r + 1, home: p.1, away: p.0, result: nil, isKnockout: false)); id += 1 } }
        }
        return out
    }
}

public enum TournamentFormat: Codable, Equatable {
    case league(double: Bool)
    case knockout
    case groupsThenKnockout(groups: Int, advancePerGroup: Int)
}

public struct Tournament: Codable, Equatable {
    public var name: String
    public var format: TournamentFormat
    public var clubs: [Int]                       // seeded best-first
    public var fixtures: [Fixture]
    public var champion: Int?
    public private(set) var knockoutRound = 0
    var nextID: Int

    public init(name: String, format: TournamentFormat, clubs: [Int]) {
        self.name = name; self.format = format; self.clubs = clubs; fixtures = []; nextID = 1
        switch format {
        case .league(let double):
            fixtures = FixtureGenerator.roundRobin(clubs: clubs, double: double)
        case .knockout:
            addKnockoutRound(from: clubs)
        case .groupsThenKnockout(let groups, _):
            for g in 0..<groups {
                let members = clubs.enumerated().filter { ($0.offset % (2 * groups) == g) || ($0.offset % (2 * groups) == 2 * groups - 1 - g) }.map { $0.element }   // snake seeding
                let fs = FixtureGenerator.roundRobin(clubs: members, double: false, stage: "Group \(Character(UnicodeScalar(65 + g)!))", startID: nextID)
                fixtures += fs; nextID += fs.count
            }
        }
        nextID = (fixtures.map { $0.id }.max() ?? 0) + 1
    }

    public var groupNames: [String] { Array(Set(fixtures.filter { !$0.isKnockout && $0.stage.hasPrefix("Group") }.map { $0.stage })).sorted() }
    public func table(stage: String? = nil) -> [StandingRow] {
        let fs = stage == nil ? fixtures.filter { !$0.isKnockout } : fixtures.filter { $0.stage == stage }
        let ids = Array(Set(fs.flatMap { [$0.home, $0.away] }))
        return Standings.table(fixtures: fs, clubs: stage == nil && ids.isEmpty ? clubs : ids)
    }
    public var pending: [Fixture] { fixtures.filter { $0.result == nil } }
    public var isComplete: Bool { champion != nil }

    public func roundName(_ teams: Int) -> String {
        switch teams { case 2: return "Final"; case 4: return "Semi-final"; case 8: return "Quarter-final"; default: return "Round of \(teams)" }
    }

    private mutating func addKnockoutRound(from entrants: [Int]) {
        var seeds = entrants
        var size = 1; while size < seeds.count { size *= 2 }
        let byes = size - seeds.count                      // top seeds receive byes
        knockoutRound += 1
        var ties: [(Int, Int)] = []
        let playing = Array(seeds.dropFirst(byes))
        for i in 0..<(playing.count / 2) { ties.append((playing[i], playing[playing.count - 1 - i])) }
        for t in ties { fixtures.append(Fixture(id: nextID, stage: roundName(size), round: knockoutRound, home: t.0, away: t.1, result: nil, isKnockout: true)); nextID += 1 }
        pendingByes = Array(seeds.prefix(byes)); seeds = []
    }
    private var pendingByes: [Int] = []

    /// Record a result. Knockout draws must carry a penalty winner. Advances rounds / sets the champion automatically.
    @discardableResult
    public mutating func record(fixtureID: Int, result: MatchResult) -> Bool {
        guard let i = fixtures.firstIndex(where: { $0.id == fixtureID }), fixtures[i].result == nil else { return false }
        if fixtures[i].isKnockout && result.homeGoals == result.awayGoals {
            guard let w = result.penaltyWinner, w == fixtures[i].home || w == fixtures[i].away else { return false }
        }
        fixtures[i].result = result
        advanceIfNeeded()
        return true
    }

    private mutating func advanceIfNeeded() {
        switch format {
        case .league:
            if pending.isEmpty { champion = table().first?.club }
        case .knockout:
            advanceKnockout()
        case .groupsThenKnockout(_, let advance):
            let groupFixtures = fixtures.filter { !$0.isKnockout }
            guard knockoutRound == 0, groupFixtures.allSatisfy({ $0.result != nil }) else { if knockoutRound > 0 { advanceKnockout() }; return }
            // cross-group pairing: winners meet runners-up of the next group (A1-B2, B1-A2, ...)
            let qualifiers: [[Int]] = groupNames.map { table(stage: $0).prefix(advance).map { $0.club } }
            var order: [Int] = []
            for rank in 0..<advance { for g in 0..<qualifiers.count { order.append(qualifiers[g][rank]) } }   // [A1,B1,A2,B2]: seed pairing gives A1-B2, B1-A2
            addKnockoutRound(from: order)
            pendingByes = []
        }
    }

    private mutating func advanceKnockout() {
        let current = fixtures.filter { $0.isKnockout && $0.round == knockoutRound }
        guard !current.isEmpty, current.allSatisfy({ $0.result != nil }) else { return }
        let winners = pendingByes + current.compactMap { $0.winner }
        if winners.count == 1 { champion = winners[0]; return }
        pendingByes = []
        // later rounds: pair winners in bracket order
        knockoutRound += 1
        let name = roundName(winners.count)
        for k in 0..<(winners.count / 2) {
            fixtures.append(Fixture(id: nextID, stage: name, round: knockoutRound, home: winners[2 * k], away: winners[2 * k + 1], result: nil, isKnockout: true)); nextID += 1
        }
    }
}

/// Fast statistical match result for fixtures the user does not play (Poisson goals from XI strength, home advantage).
public enum ResultSimulator {
    public static func simulate(home: Float, away: Float, knockout: Bool, rng: inout SplitMix64, homeID: Int, awayID: Int) -> MatchResult {
        func goals(_ attack: Float, _ defence: Float, bonus: Float) -> Int {
            let lambda = max(0.15, 1.35 * exp((attack - defence) / 22) * bonus)
            var l = exp(-lambda), k = 0, p: Float = 1
            repeat { k += 1; p *= rng.float() } while p > l && k < 12
            return k - 1
        }
        var h = goals(home, away, bonus: 1.12), a = goals(away, home, bonus: 0.92)
        if knockout && h == a {
            // extra time: a short Poisson each, then penalties weighted by strength
            h += goals(home, away, bonus: 0.4); a += goals(away, home, bonus: 0.4)
            if h == a {
                let pHome = 0.5 + max(-0.15, min(0.15, (home - away) / 200))
                return MatchResult(homeGoals: h, awayGoals: a, extraTime: true, penaltyWinner: rng.float() < pHome ? homeID : awayID)
            }
            return MatchResult(homeGoals: h, awayGoals: a, extraTime: true)
        }
        return MatchResult(homeGoals: h, awayGoals: a)
    }
}
