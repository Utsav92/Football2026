import XCTest
@testable import FootballModes
import FootballData
import FootballGame

final class CareerTests: XCTestCase {
    func db() throws -> GameDatabase {
        try GameDatabase.load(from: try XCTUnwrap(Bundle.module.url(forResource: "clubs_fixture", withExtension: "json")))
    }
    func newCareer(club: Int = 5, seed: UInt64 = 3) throws -> CareerState { try CareerState(database: try db(), clubID: club, seed: seed) }
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("f26-\(UUID().uuidString)/career.json") }

    func testNewCareerHasLeagueCalendarAndFinances() throws {
        let c = try newCareer()
        XCTAssertEqual(c.league.fixtures.count, 20 * 19)
        XCTAssertEqual(c.totalRounds, 38)
        XCTAssertNotNil(c.userFixture())
        XCTAssertGreaterThan(c.finances.balance, 0)
    }

    func testWeekAdvancesFixturesFinancesAndRecordsUserResult() throws {
        var c = try newCareer()
        let before = c.finances.balance
        let f = try XCTUnwrap(c.userFixture())
        c.advanceWeek(userResult: f.home == c.clubID ? MatchResult(homeGoals: 3, awayGoals: 0) : MatchResult(homeGoals: 0, awayGoals: 3))
        XCTAssertEqual(c.week, 1)
        XCTAssertEqual(c.league.fixtures.filter { $0.round == 1 && $0.result != nil }.count, 10, "every fixture of the round is decided")
        XCTAssertEqual(c.league.table().first { $0.club == c.clubID }?.won, 1)
        XCTAssertNotEqual(c.finances.balance, before)
    }

    func testFullSeasonRollsOverAgesPlayersAndPaysPrizeMoney() throws {
        var c = try newCareer()
        let ages = c.club.squad.map { $0.age }
        for _ in 0..<38 { c.advanceWeek() }
        XCTAssertEqual(c.season, 2); XCTAssertEqual(c.week, 0)
        XCTAssertEqual(c.history.count, 1)
        XCTAssertEqual(c.history[0].season, 1)
        XCTAssertTrue((1...20).contains(c.history[0].position))
        XCTAssertEqual(c.league.fixtures.filter { $0.result != nil }.count, 0, "new season fixtures")
        let survivors = c.club.squad
        for p in survivors.prefix(5) { if let old = ages.first, old > 0 { XCTAssertGreaterThanOrEqual(p.age, 18) } }
        XCTAssertTrue(survivors.allSatisfy { $0.contractYears >= 1 }, "contracts of departed players are gone, others have years left")
    }

    func testTransferBuyChecksBudgetSquadSizeAndMovesPlayer() throws {
        var c = try newCareer(club: 15)
        let l = try XCTUnwrap(c.marketListings(minRating: 60).first)
        let seller = l.clubID
        c.finances.balance = l.askingPrice - 1
        XCTAssertEqual(c.buy(playerID: l.player.id), .failure(.insufficientFunds))
        c.finances.balance = l.askingPrice + 5_000_000; c.finances.wageBudget = 10_000_000
        let squadBefore = c.club.squad.count, sellerBefore = c.clubs.first { $0.id == seller }!.squad.count
        XCTAssertEqual(c.buy(playerID: l.player.id), .success(Done()))
        XCTAssertEqual(c.club.squad.count, squadBefore + 1)
        XCTAssertEqual(c.clubs.first { $0.id == seller }!.squad.count, sellerBefore - 1)
        XCTAssertTrue(c.club.squad.contains { $0.id == l.player.id })
        XCTAssertEqual(Set(c.club.squad.map { $0.number }).count, c.club.squad.count, "no duplicate shirt numbers after a signing")
        XCTAssertEqual(c.buy(playerID: l.player.id), .failure(.ownPlayer))
        XCTAssertEqual(c.buy(playerID: -5), .failure(.playerNotFound))
    }

    func testSquadLimitsAndLastGoalkeeperProtected() throws {
        var c = try newCareer(club: 8)
        c.finances.balance = 900_000_000; c.finances.wageBudget = 100_000_000
        var guardN = 0
        while c.club.squad.count < CareerState.maxSquad, guardN < 60, let l = c.marketListings().first { guardN += 1; _ = c.buy(playerID: l.player.id) }
        XCTAssertEqual(c.club.squad.count, CareerState.maxSquad)
        let l = try XCTUnwrap(c.marketListings().first)
        XCTAssertEqual(c.buy(playerID: l.player.id), .failure(.squadFull))
        // sell goalkeepers until two remain
        var c2 = try newCareer(club: 8)
        for gk in c2.club.squad.filter({ $0.role == .gk }).dropFirst(2) { XCTAssertNotNil(try? c2.sell(playerID: gk.id).get()) }
        let gks = c2.club.squad.filter { $0.role == .gk }
        XCTAssertEqual(c2.sell(playerID: gks[0].id), .failure(.lastGoalkeeper))
    }

    func testSellPaysClubAndRespectsMinimumSquad() throws {
        var c = try newCareer(club: 3)
        let p = try XCTUnwrap(c.club.squad.last { $0.role == .cm })
        let bal = c.finances.balance
        let r = c.sell(playerID: p.id)
        guard case .success(let price) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(c.finances.balance, bal + price)
        XCTAssertFalse(c.club.squad.contains { $0.id == p.id })
        while c.club.squad.count > CareerState.minSquad, let q = c.club.squad.first(where: { $0.role != .gk }) { _ = c.sell(playerID: q.id) }
        let any = c.club.squad.first { $0.role != .gk }!
        XCTAssertEqual(c.sell(playerID: any.id), .failure(.squadTooSmall))
    }

    func testContractRenewalCostsMoneyAndRaisesWage() throws {
        var c = try newCareer()
        let p = c.club.squad[3]
        c.finances.balance = 100_000_000; c.finances.wageBudget = 100_000_000
        let bal = c.finances.balance
        XCTAssertEqual(c.renewContract(playerID: p.id, years: 4), .success(Done()))
        let q = c.club.squad.first { $0.id == p.id }!
        XCTAssertEqual(q.contractYears, 4); XCTAssertGreaterThan(q.wage, p.wage); XCTAssertLessThan(c.finances.balance, bal)
        c.finances.balance = 0
        XCTAssertEqual(c.renewContract(playerID: p.id, years: 4), .failure(.insufficientFunds))
    }

    func testExpiredContractsRemovePlayersUnlessRenewed() throws {
        var c = try newCareer()
        let keep = c.club.squad[2].id, leave = c.club.squad[4].id
        for i in c.clubs.indices where c.clubs[i].id == c.clubID { for j in c.clubs[i].squad.indices { c.clubs[i].squad[j].contractYears = 1 } }
        c.finances.balance = 100_000_000; c.finances.wageBudget = 100_000_000
        XCTAssertEqual(c.renewContract(playerID: keep, years: 3), .success(Done()))
        for _ in 0..<38 { c.advanceWeek() }
        XCTAssertTrue(c.club.squad.contains { $0.id == keep })
        XCTAssertFalse(c.club.squad.contains { $0.id == leave })
    }

    func testTrainingImprovesFocusedAttributesWithinCapsAndYoungPlayersGrowFaster() throws {
        var c = try newCareer()
        c.setTraining(.attacking)
        let before = c.club.squad
        for _ in 0..<38 { c.advanceWeek() }
        // compare the same players (those still at the club) before the season rollover aged them
        let young = before.filter { $0.age <= 22 }, old = before.filter { $0.age >= 31 }
        func gain(_ ps: [PlayerRecord]) -> Int {
            ps.reduce(0) { acc, p in
                guard let q = c.club.squad.first(where: { $0.id == p.id }) else { return acc }
                return acc + (q.attributes.shootingAccuracy - p.attributes.shootingAccuracy) + (q.attributes.dribbling - p.attributes.dribbling)
            }
        }
        XCTAssertGreaterThan(gain(young), 0)
        XCTAssertGreaterThanOrEqual(gain(young) * max(1, old.count), gain(old) * max(1, young.count), "per-player, young players develop at least as much")
        XCTAssertTrue(c.club.squad.allSatisfy { $0.attributes.shootingAccuracy <= 99 && $0.attributes.dribbling <= 99 })
    }

    func testInjuriesHappenHealAndAreExcludedFromLineup() throws {
        var c = try newCareer()
        for _ in 0..<12 { c.advanceWeek() }
        XCTAssertTrue(c.news.contains { $0.contains("injured") }, "12 matches should produce at least one injury")
        let i = c.clubs.firstIndex { $0.id == c.clubID }!
        c.clubs[i].squad[1].injuredWeeks = 2
        let id = c.clubs[i].squad[1].id
        XCTAssertFalse(c.club.teamSetup().players.prefix(11).contains { $0.id == id })
        c.advanceWeek(); c.advanceWeek()
        XCTAssertEqual(c.clubs[i].squad.first { $0.id == id }?.injuredWeeks, 0)
    }

    func testDeterministicBySeed() throws {
        var a = try newCareer(seed: 9), b = try newCareer(seed: 9), d = try newCareer(seed: 10)
        for _ in 0..<10 { a.advanceWeek(); b.advanceWeek(); d.advanceWeek() }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.league, d.league)
    }

    // MARK: persistence
    func testSaveLoadRoundTripAndBackupRotation() throws {
        var c = try newCareer()
        let m = SaveManager(url: tmp())
        try m.save(c)
        c.advanceWeek(); try m.save(c)
        XCTAssertTrue(FileManager.default.fileExists(atPath: m.backupURL.path), "previous save kept as .bak")
        let l = try m.load()
        XCTAssertEqual(l.state, c); XCTAssertFalse(l.restoredFromBackup); XCTAssertNil(l.migratedFrom)
    }

    func testCorruptSaveFallsBackToBackup() throws {
        var c = try newCareer()
        let m = SaveManager(url: tmp())
        try m.save(c); c.advanceWeek(); try m.save(c)
        try Data("{ not json".utf8).write(to: m.url)
        let l = try m.load()
        XCTAssertTrue(l.restoredFromBackup)
        XCTAssertEqual(l.state.week, 0, "backup is the previous (week 0) save")
        try Data("garbage".utf8).write(to: m.backupURL)
        XCTAssertThrowsError(try m.load())
    }

    func testMissingSaveReportsNotFound() {
        XCTAssertThrowsError(try SaveManager(url: tmp()).load()) { XCTAssertEqual($0 as? SaveError, .notFound) }
    }

    func testMigrationFromV1AddsNewFields() throws {
        let c = try newCareer()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        for k in ["history", "news", "formation"] { obj[k] = nil }
        obj["schemaVersion"] = 1
        var fin = obj["finances"] as! [String: Any]; fin["wageBudget"] = nil; fin["weeklyIncome"] = nil; obj["finances"] = fin
        let m = SaveManager(url: tmp())
        try FileManager.default.createDirectory(at: m.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: obj).write(to: m.url)
        let l = try m.load()
        XCTAssertEqual(l.migratedFrom, 1)
        XCTAssertEqual(l.state.schemaVersion, CareerState.currentSchema)
        XCTAssertEqual(l.state.formation, l.state.club.preferredFormation)
        XCTAssertTrue(l.state.history.isEmpty)
        XCTAssertGreaterThan(l.state.finances.wageBudget, 0)
    }

    func testSaveFromNewerAppVersionIsRefused() throws {
        let c = try newCareer()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any]); obj["schemaVersion"] = 99
        let m = SaveManager(url: tmp()); try FileManager.default.createDirectory(at: m.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: obj).write(to: m.url)
        XCTAssertThrowsError(try m.load()) { XCTAssertEqual($0 as? SaveError, .newerThanApp(99)) }
    }
}
