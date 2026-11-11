import XCTest
@testable import FootballData
import FootballGame

final class DatabaseTests: XCTestCase {
    func db() throws -> GameDatabase {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "clubs_fixture", withExtension: "json"))
        return try GameDatabase.load(from: url)
    }

    func testDatabaseMeetsSizeRequirements() throws {
        let d = try db()
        XCTAssertGreaterThanOrEqual(d.clubs.count, 20)
        XCTAssertGreaterThanOrEqual(d.allPlayers.count, 400)
        XCTAssertEqual(Set(d.allPlayers.map { $0.id }).count, d.allPlayers.count, "player ids unique")
        XCTAssertEqual(Set(d.allPlayers.map { $0.name }).count, d.allPlayers.count, "fictional names unique")
    }

    func testEveryClubFormsValidLineupInEveryFormation() throws {
        for club in try db().clubs {
            for f in Formation.allCases {
                let s = club.teamSetup(formation: f)
                XCTAssertGreaterThanOrEqual(s.players.count, 16)
                XCTAssertEqual(s.players[0].role, .gk, "\(club.name) \(f.rawValue)")
                XCTAssertEqual(Set(s.players.prefix(11).map { $0.id }).count, 11)
                XCTAssertEqual(s.players.prefix(11).filter { $0.role == .gk }.count, 1)
            }
        }
    }

    func testLineupPrefersRoleMatchAndSkipsInjured() throws {
        var club = try db().clubs[0]
        let best = club.squad.filter { $0.role == .st }.max { $0.rating < $1.rating }!
        XCTAssertTrue(club.teamSetup(formation: .f433).players.prefix(11).contains { $0.id == best.id })
        let i = club.squad.firstIndex { $0.id == best.id }!
        club.squad[i].injuredWeeks = 3
        XCTAssertFalse(club.teamSetup(formation: .f433).players.prefix(11).contains { $0.id == best.id })
    }

    func testAttributesAreInRangeAndRolesBiased() throws {
        let d = try db()
        for p in d.allPlayers {
            for v in [p.attributes.sprintSpeed, p.attributes.tackling, p.attributes.goalkeeping, p.attributes.reactionTime] { XCTAssertTrue((15...97).contains(v)) }
        }
        let gk = d.allPlayers.filter { $0.role == .gk }.map { $0.attributes.goalkeeping }.reduce(0, +) / d.allPlayers.filter { $0.role == .gk }.count
        let st = d.allPlayers.filter { $0.role == .st }.map { $0.attributes.goalkeeping }.reduce(0, +) / d.allPlayers.filter { $0.role == .st }.count
        XCTAssertGreaterThan(gk, st + 25, "keepers keep, strikers don't")
    }

    func testClubStrengthGradientAndMatchEngineAcceptsSetups() throws {
        let d = try db()
        XCTAssertGreaterThan(d.clubs.first!.xiStrength(), d.clubs.last!.xiStrength())
        let m = MatchSimulation(config: MatchConfig(home: d.clubs[0].teamSetup(), away: d.clubs[1].teamSetup(), humanTeams: [], seed: 1))
        XCTAssertEqual(m.players.count, 22)
        for _ in 0..<600 { m.step() }
    }

    func testValidationRejectsBadData() throws {
        var d = try db()
        d.clubs[0].squad[1].id = d.clubs[0].squad[0].id
        XCTAssertThrowsError(try d.validate())
        var e = try db(); e.clubs.removeLast()
        XCTAssertThrowsError(try e.validate())
    }
}
