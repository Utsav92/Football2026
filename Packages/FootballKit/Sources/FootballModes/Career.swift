import Foundation
import FootballGame
import FootballData

public struct Finances: Codable, Equatable {
    public var balance: Int
    public var wageBudget: Int            // weekly wage cap
    public var weeklyIncome: Int          // sponsorship + merchandise
    public init(balance: Int, wageBudget: Int = 1_000_000, weeklyIncome: Int = 300_000) { self.balance = balance; self.wageBudget = wageBudget; self.weeklyIncome = weeklyIncome }
}

public enum TrainingFocus: String, Codable, CaseIterable {
    case attacking, defending, passing, physical, goalkeeping, balanced
    var attributes: [WritableKeyPath<PlayerAttributes, Int>] {
        switch self {
        case .attacking: return [\.shootingAccuracy, \.shotPower, \.dribbling, \.ballControl]
        case .defending: return [\.tackling, \.defensiveAwareness, \.strength, \.positioning]
        case .passing: return [\.shortPassing, \.longPassing, \.ballControl, \.positioning]
        case .physical: return [\.sprintSpeed, \.acceleration, \.stamina, \.agility, \.balance]
        case .goalkeeping: return [\.goalkeeping, \.reactionTime, \.positioning]
        case .balanced: return [\.dribbling, \.shortPassing, \.tackling, \.stamina, \.positioning]
        }
    }
}

public struct SeasonSummary: Codable, Equatable { public var season: Int; public var position: Int; public var points: Int; public var champion: Int }

/// Success marker for operations that return nothing (keeps `Result` Equatable).
public struct Done: Equatable { public init() {} }

public enum TransferError: Error, Equatable {
    case playerNotFound, insufficientFunds, squadFull, squadTooSmall, wageBudgetExceeded, lastGoalkeeper, ownPlayer, noBuyer
}

public struct CareerState: Codable, Equatable {
    public static let currentSchema = 2
    public var schemaVersion = CareerState.currentSchema
    public var clubID: Int
    public var season = 1
    public var week = 0                         // number of completed league rounds this season
    public var clubs: [ClubRecord]
    public var league: Tournament
    public var finances: Finances
    public var training: TrainingFocus = .balanced
    public var formation: Formation
    public var history: [SeasonSummary] = []
    public var news: [String] = []
    public var rngState: UInt64

    public static let maxSquad = 30, minSquad = 18

    public init(database: GameDatabase, clubID: Int, seed: UInt64 = 1) throws {
        guard let c = database.club(clubID) else { throw DatabaseError.invalid("unknown club \(clubID)") }
        self.clubID = clubID; clubs = database.clubs
        let seeded = database.clubs.sorted { $0.strength > $1.strength }.map { $0.id }
        league = Tournament(name: "Premier Division", format: .league(double: true), clubs: seeded)
        finances = Finances(balance: c.budget, wageBudget: 250_000 + c.strength * 12_000, weeklyIncome: 120_000 + c.strength * 6_000)
        formation = c.preferredFormation; rngState = seed &+ 12345
    }

    // MARK: Accessors
    public var club: ClubRecord { clubs.first { $0.id == clubID }! }
    private func index(of id: Int) -> Int { clubs.firstIndex { $0.id == id }! }
    public var totalRounds: Int { league.fixtures.map { $0.round }.max() ?? 0 }
    public var isSeasonOver: Bool { week >= totalRounds }
    public var weeklyWageBill: Int { club.squad.reduce(0) { $0 + $1.wage } }
    public var tablePosition: Int { (league.table().firstIndex { $0.club == clubID } ?? 0) + 1 }
    public func userFixture() -> Fixture? { league.fixtures.first { $0.round == week + 1 && $0.result == nil && ($0.home == clubID || $0.away == clubID) } }

    private mutating func rng() -> SplitMix64 { SplitMix64(seed: rngState) }
    private mutating func nextRandom() -> Float { var r = SplitMix64(seed: rngState); let v = r.float(); rngState = r.next() &+ 1; return v }

    // MARK: Weekly loop
    /// Plays one league round. `userResult` is the user's (played) result; pass nil to simulate their fixture too.
    public mutating func advanceWeek(userResult: MatchResult? = nil) {
        guard !isSeasonOver else { return }
        let round = week + 1
        var r = rng()
        for f in league.fixtures where f.round == round && f.result == nil {
            let isUser = f.home == clubID || f.away == clubID
            let result: MatchResult
            if isUser, let u = userResult { result = u }
            else {
                result = ResultSimulator.simulate(home: clubs[index(of: f.home)].xiStrength(), away: clubs[index(of: f.away)].xiStrength(),
                                                  knockout: false, rng: &r, homeID: f.home, awayID: f.away)
            }
            league.record(fixtureID: f.id, result: result)
            if isUser { applyMatchEffects(f, result) }
        }
        rngState = r.next() &+ 1
        payWeek()
        developSquad()
        recover()
        week += 1
        if isSeasonOver { endSeason() }
    }

    private mutating func applyMatchEffects(_ f: Fixture, _ r: MatchResult) {
        let userGoals = f.home == clubID ? r.homeGoals : r.awayGoals, oppGoals = f.home == clubID ? r.awayGoals : r.homeGoals
        let delta: Float = userGoals > oppGoals ? 0.06 : (userGoals == oppGoals ? 0 : -0.08)
        let ci = index(of: clubID)
        let xi = Set(club.teamSetup(formation: formation).players.prefix(11).map { $0.id })
        for i in clubs[ci].squad.indices {
            clubs[ci].squad[i].morale = max(0.1, min(1, clubs[ci].squad[i].morale + delta))
            if xi.contains(clubs[ci].squad[i].id) {
                clubs[ci].squad[i].fitness = max(0.4, clubs[ci].squad[i].fitness - 0.18)
                if nextRandom() < 0.035 { clubs[ci].squad[i].injuredWeeks = 1 + Int(nextRandom() * 7); news.append("\(clubs[ci].squad[i].name) injured (\(clubs[ci].squad[i].injuredWeeks) weeks)") }
            }
        }
        if f.home == clubID { finances.balance += 180_000 + Int(Float(club.strength) * 3_000) }     // gate receipts
        if userGoals > oppGoals { finances.balance += 50_000 }                                         // win bonus
    }

    private mutating func payWeek() {
        finances.balance += finances.weeklyIncome - weeklyWageBill
    }

    private mutating func recover() {
        let ci = index(of: clubID)
        for i in clubs[ci].squad.indices {
            clubs[ci].squad[i].fitness = min(1, clubs[ci].squad[i].fitness + 0.12)
            if clubs[ci].squad[i].injuredWeeks > 0 { clubs[ci].squad[i].injuredWeeks -= 1 }
        }
    }

    // MARK: Training & development
    private func ageFactor(_ age: Int) -> Float { age < 21 ? 1.6 : (age < 25 ? 1.2 : (age < 29 ? 0.8 : (age < 32 ? 0.3 : 0))) }

    private mutating func developSquad() {
        let ci = index(of: clubID)
        let focus = training
        for i in clubs[ci].squad.indices {
            var p = clubs[ci].squad[i]
            guard p.injuredWeeks == 0 else { continue }
            let relevant = focus == .goalkeeping && p.role != .gk ? [] : focus.attributes
            for kp in relevant {
                let headroom = Float(p.potential - p.attributes[keyPath: kp]) / 20
                let chance = max(0, min(0.2, 0.08 * ageFactor(p.age) * (0.5 + p.morale) * headroom))
                if nextRandom() < chance, p.attributes[keyPath: kp] < min(99, p.potential + 5) { p.attributes[keyPath: kp] += 1 }
            }
            clubs[ci].squad[i] = p
        }
    }

    public mutating func setTraining(_ f: TrainingFocus) { training = f }

    // MARK: Season rollover
    private mutating func endSeason() {
        let table = league.table()
        let pos = (table.firstIndex { $0.club == clubID } ?? 0) + 1
        history.append(SeasonSummary(season: season, position: pos, points: table.first { $0.club == clubID }?.points ?? 0, champion: table.first?.club ?? 0))
        finances.balance += max(0, (21 - pos)) * 150_000                                              // prize money
        for ci in clubs.indices {
            var expired: [Int] = []
            for pi in clubs[ci].squad.indices {
                clubs[ci].squad[pi].age += 1
                clubs[ci].squad[pi].contractYears -= 1
                var a = clubs[ci].squad[pi].attributes
                if clubs[ci].squad[pi].age > 31 {          // age regression of physical attributes
                    a.sprintSpeed = max(25, a.sprintSpeed - 2); a.acceleration = max(25, a.acceleration - 2); a.stamina = max(25, a.stamina - 1)
                }
                clubs[ci].squad[pi].attributes = a
                clubs[ci].squad[pi].fitness = 1; clubs[ci].squad[pi].injuredWeeks = 0
                if clubs[ci].squad[pi].contractYears <= 0 {
                    if clubs[ci].id == clubID { expired.append(clubs[ci].squad[pi].id) }
                    else { clubs[ci].squad[pi].contractYears = 3 }                                   // AI clubs renew automatically
                }
            }
            if !expired.isEmpty {
                clubs[ci].squad.removeAll { expired.contains($0.id) && !$0.isRenewalProtected }
                news.append("\(expired.count) player(s) left on expired contracts")
            }
        }
        season += 1; week = 0
        let seeded = clubs.sorted { $0.strength > $1.strength }.map { $0.id }
        league = Tournament(name: "Premier Division", format: .league(double: true), clubs: seeded)
    }

    // MARK: Contracts
    /// Renew a contract: wage rises 10 %; cost is a signing fee of 8 weeks' new wages per year.
    @discardableResult
    public mutating func renewContract(playerID: Int, years: Int) -> Result<Done, TransferError> {
        let ci = index(of: clubID)
        guard let pi = clubs[ci].squad.firstIndex(where: { $0.id == playerID }) else { return .failure(.playerNotFound) }
        let newWage = Int(Float(clubs[ci].squad[pi].wage) * 1.10)
        let fee = newWage * 8 * years
        guard finances.balance >= fee else { return .failure(.insufficientFunds) }
        guard weeklyWageBill - clubs[ci].squad[pi].wage + newWage <= finances.wageBudget else { return .failure(.wageBudgetExceeded) }
        finances.balance -= fee
        clubs[ci].squad[pi].wage = newWage; clubs[ci].squad[pi].contractYears = years
        clubs[ci].squad[pi].morale = min(1, clubs[ci].squad[pi].morale + 0.1)
        return .success(Done())
    }

    // MARK: Transfers
    public struct Listing: Equatable { public var player: PlayerRecord; public var clubID: Int; public var askingPrice: Int }

    public func marketListings(minRating: Int = 0, maxPrice: Int = .max, role: Role? = nil) -> [Listing] {
        clubs.filter { $0.id != clubID }.flatMap { c in
            c.squad.filter { $0.rating >= minRating && (role == nil || $0.role == role) }
                .map { Listing(player: $0, clubID: c.id, askingPrice: Int(Float($0.value) * 1.15)) }
        }.filter { $0.askingPrice <= maxPrice }.sorted { $0.player.rating > $1.player.rating }
    }

    @discardableResult
    public mutating func buy(playerID: Int) -> Result<Done, TransferError> {
        guard let l = marketListings().first(where: { $0.player.id == playerID }) else {
            return clubs[index(of: clubID)].squad.contains { $0.id == playerID } ? .failure(.ownPlayer) : .failure(.playerNotFound)
        }
        let ci = index(of: clubID), si = index(of: l.clubID)
        guard clubs[ci].squad.count < Self.maxSquad else { return .failure(.squadFull) }
        guard finances.balance >= l.askingPrice else { return .failure(.insufficientFunds) }
        guard weeklyWageBill + l.player.wage <= finances.wageBudget else { return .failure(.wageBudgetExceeded) }
        guard clubs[si].squad.count > Self.minSquad - 1 else { return .failure(.squadTooSmall) }
        finances.balance -= l.askingPrice; clubs[si].budget += l.askingPrice
        clubs[si].squad.removeAll { $0.id == playerID }
        var p = l.player
        p.contractYears = 3; p.morale = 0.75; p.number = freeNumber(in: ci)
        clubs[ci].squad.append(p)
        news.append("Signed \(p.name) for \(l.askingPrice)")
        return .success(Done())
    }

    @discardableResult
    public mutating func sell(playerID: Int) -> Result<Int, TransferError> {
        let ci = index(of: clubID)
        guard let pi = clubs[ci].squad.firstIndex(where: { $0.id == playerID }) else { return .failure(.playerNotFound) }
        guard clubs[ci].squad.count > Self.minSquad else { return .failure(.squadTooSmall) }
        let p = clubs[ci].squad[pi]
        if p.role == .gk, clubs[ci].squad.filter({ $0.role == .gk }).count <= 2 { return .failure(.lastGoalkeeper) }
        let price = Int(Float(p.value) * 0.9)
        guard let bi = clubs.indices.filter({ clubs[$0].id != clubID && clubs[$0].budget >= price && clubs[$0].squad.count < Self.maxSquad })
                .max(by: { clubs[$0].budget < clubs[$1].budget }) else { return .failure(.noBuyer) }
        clubs[bi].budget -= price
        var moved = p; moved.number = freeNumber(in: bi); clubs[bi].squad.append(moved)
        clubs[ci].squad.remove(at: pi)
        finances.balance += price
        news.append("Sold \(p.name) for \(price)")
        return .success(price)
    }

    private func freeNumber(in ci: Int) -> Int {
        let used = Set(clubs[ci].squad.map { $0.number })
        return (2...99).first { !used.contains($0) && $0 != 12 } ?? 99
    }
}

extension PlayerRecord { var isRenewalProtected: Bool { false } }

// MARK: - Persistence

public enum SaveError: Error, Equatable { case notFound, corrupt, newerThanApp(Int) }

public struct SaveManager {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var backupURL: URL { url.appendingPathExtension("bak") }

    /// Atomic save that keeps the previous good save as `.bak`.
    public func save(_ state: CareerState) throws {
        let data = try JSONEncoder().encode(state)
        let tmp = url.appendingPathExtension("tmp")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: url, to: backupURL)
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    public struct Loaded { public var state: CareerState; public var restoredFromBackup: Bool; public var migratedFrom: Int? }

    public func load() throws -> Loaded {
        func attempt(_ u: URL) throws -> (CareerState, Int?) {
            guard let raw = try? Data(contentsOf: u) else { throw SaveError.notFound }
            let (data, from) = try Self.migrate(raw)
            guard let s = try? JSONDecoder().decode(CareerState.self, from: data) else { throw SaveError.corrupt }
            return (s, from)
        }
        do { let (s, from) = try attempt(url); return Loaded(state: s, restoredFromBackup: false, migratedFrom: from) }
        catch SaveError.newerThanApp(let v) { throw SaveError.newerThanApp(v) }
        catch {
            let (s, from) = try attempt(backupURL)      // fall back to the previous save
            return Loaded(state: s, restoredFromBackup: true, migratedFrom: from)
        }
    }

    /// Upgrades older save formats. v1 → v2 added `history`, `news`, `formation` and the wage/income fields of `finances`.
    public static func migrate(_ data: Data) throws -> (Data, Int?) {
        guard var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SaveError.corrupt }
        let v = obj["schemaVersion"] as? Int ?? 1
        if v > CareerState.currentSchema { throw SaveError.newerThanApp(v) }
        guard v < CareerState.currentSchema else { return (data, nil) }
        if v == 1 {
            obj["history"] = obj["history"] ?? []
            obj["news"] = obj["news"] ?? []
            if obj["formation"] == nil {
                let clubID = obj["clubID"] as? Int ?? 0
                let club = (obj["clubs"] as? [[String: Any]])?.first { $0["id"] as? Int == clubID }
                obj["formation"] = club?["preferredFormation"] as? String ?? "4-3-3"
            }
            var fin = obj["finances"] as? [String: Any] ?? [:]
            fin["wageBudget"] = fin["wageBudget"] ?? 1_000_000
            fin["weeklyIncome"] = fin["weeklyIncome"] ?? 300_000
            obj["finances"] = fin
            obj["schemaVersion"] = 2
        }
        return (try JSONSerialization.data(withJSONObject: obj), v)
    }
}
