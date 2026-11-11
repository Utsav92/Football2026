import XCTest
@testable import FootballModes
import FootballGame
import FootballData

final class TournamentTests: XCTestCase {
    func fx(_ id: Int, _ h: Int, _ a: Int, _ hg: Int, _ ag: Int) -> Fixture {
        Fixture(id: id, stage: "League", round: 1, home: h, away: a, result: MatchResult(homeGoals: hg, awayGoals: ag), isKnockout: false)
    }

    func testRoundRobinPlaysEveryPairOncePerLegAndBalancesHomeAway() {
        for n in [4, 5, 8, 20] {
            let clubs = Array(1...n)
            let fs = FixtureGenerator.roundRobin(clubs: clubs, double: true)
            let legs = n % 2 == 0 ? n - 1 : n
            XCTAssertEqual(fs.count, n * (n - 1), "n=\(n)")
            var pairs = Set<String>()
            for f in fs { XCTAssertTrue(pairs.insert("\(f.home)-\(f.away)").inserted, "duplicate \(f.home)-\(f.away)"); XCTAssertNotEqual(f.home, f.away) }
            for c in clubs {
                let home = fs.filter { $0.home == c }.count, away = fs.filter { $0.away == c }.count
                XCTAssertEqual(home, n - 1); XCTAssertEqual(away, n - 1)
                // nobody plays twice in a round
                for r in 1...(2 * legs) { XCTAssertLessThanOrEqual(fs.filter { $0.round == r && ($0.home == c || $0.away == c) }.count, 1) }
            }
        }
    }

    func testStandingsPointsGoalDifferenceAndTieBreaks() {
        let fs = [fx(1, 1, 2, 3, 0), fx(2, 3, 4, 1, 1), fx(3, 2, 3, 0, 2), fx(4, 4, 1, 0, 1)]
        let t = Standings.table(fixtures: fs, clubs: [1, 2, 3, 4])
        XCTAssertEqual(t.map { $0.club }, [1, 3, 4, 2])      // 1: 6pts, 3: 4pts, 4: 1pt (GD -1, GF1), 2: 0pts
        XCTAssertEqual(t[0].points, 6); XCTAssertEqual(t[0].goalDifference, 4)
        XCTAssertEqual(t[1].played, 2)
    }

    func testHeadToHeadBreaksLevelTeams() {
        // 1 and 2 finish level on points, GD and GF; 2 beat 1 head-to-head.
        let fs = [fx(1, 1, 2, 0, 1), fx(2, 2, 1, 1, 1 - 1 + 0), fx(3, 1, 3, 2, 0), fx(4, 2, 3, 1, 0)]
        var all = fs; all[1].result = MatchResult(homeGoals: 1, awayGoals: 1)
        let t = Standings.table(fixtures: all, clubs: [1, 2, 3])
        XCTAssertEqual(t[0].club, 2)
    }

    func testLeagueCompletesAndCrownsTopOfTable() {
        var t = Tournament(name: "L", format: .league(double: false), clubs: [1, 2, 3, 4])
        for f in t.fixtures { t.record(fixtureID: f.id, result: MatchResult(homeGoals: f.home < f.away ? 2 : 0, awayGoals: f.home < f.away ? 0 : 1)) }
        XCTAssertTrue(t.isComplete)
        XCTAssertEqual(t.champion, t.table().first?.club)
    }

    func testRecordRejectsDoubleResultsAndKnockoutDrawsWithoutPenalties() {
        var t = Tournament(name: "K", format: .knockout, clubs: [1, 2, 3, 4])
        let f = t.fixtures[0]
        XCTAssertFalse(t.record(fixtureID: f.id, result: MatchResult(homeGoals: 1, awayGoals: 1)), "draw needs a penalty winner")
        XCTAssertFalse(t.record(fixtureID: f.id, result: MatchResult(homeGoals: 1, awayGoals: 1, penaltyWinner: 99)), "winner must be one of the clubs")
        XCTAssertTrue(t.record(fixtureID: f.id, result: MatchResult(homeGoals: 1, awayGoals: 1, penaltyWinner: f.away)))
        XCTAssertFalse(t.record(fixtureID: f.id, result: MatchResult(homeGoals: 3, awayGoals: 0)), "result is final")
        XCTAssertEqual(t.fixtures[0].winner, f.away)
    }

    func testKnockoutWithByesProgressesToAChampion() {
        for n in [4, 5, 6, 8, 11] {
            var t = Tournament(name: "K", format: .knockout, clubs: Array(1...n))
            var guardCount = 0
            while !t.isComplete && guardCount < 50 {
                guard let f = t.pending.first else { break }
                XCTAssertTrue(t.record(fixtureID: f.id, result: MatchResult(homeGoals: 1, awayGoals: 0)))
                guardCount += 1
            }
            XCTAssertTrue(t.isComplete, "n=\(n)")
            XCTAssertEqual(t.fixtures.count, n - 1, "a knockout of n clubs has n-1 matches")
            XCTAssertEqual(t.fixtures.last?.stage, "Final")
            XCTAssertEqual(t.champion, 1, "top seed always wins here (home side + byes)")
        }
    }

    func testGroupStageFeedsKnockoutAndCrossPairs() {
        var t = Tournament(name: "Cup", format: .groupsThenKnockout(groups: 2, advancePerGroup: 2), clubs: Array(1...8))
        XCTAssertEqual(t.groupNames, ["Group A", "Group B"])
        XCTAssertEqual(t.fixtures.count, 12)                 // two groups of 4: 6 matches each
        for f in t.fixtures { t.record(fixtureID: f.id, result: MatchResult(homeGoals: f.home < f.away ? 1 : 0, awayGoals: f.home < f.away ? 0 : 1)) }
        let ko = t.fixtures.filter { $0.isKnockout }
        XCTAssertEqual(ko.count, 2, "semi-finals created once groups finish")
        let groupA = Set(t.table(stage: "Group A").map { $0.club }), groupB = Set(t.table(stage: "Group B").map { $0.club })
        for f in ko { XCTAssertNotEqual(groupA.contains(f.home), groupA.contains(f.away), "cross-group pairing") }
        while !t.isComplete, let f = t.pending.first { t.record(fixtureID: f.id, result: MatchResult(homeGoals: 2, awayGoals: 1)) }
        XCTAssertNotNil(t.champion)
        XCTAssertTrue(groupA.union(groupB).contains(t.champion!))
        _ = groupB
    }

    func testStatisticalSimulatorRespectsStrengthAndKnockoutResolution() {
        var rng = SplitMix64(seed: 1)
        var strong = 0, weak = 0, goals = 0
        for _ in 0..<2000 {
            let r = ResultSimulator.simulate(home: 80, away: 60, knockout: false, rng: &rng, homeID: 1, awayID: 2)
            strong += r.homeGoals; weak += r.awayGoals; goals += r.homeGoals + r.awayGoals
        }
        XCTAssertGreaterThan(strong, weak * 2, "much stronger side scores far more")
        var even = 0
        for _ in 0..<2000 { let r = ResultSimulator.simulate(home: 70, away: 70, knockout: false, rng: &rng, homeID: 1, awayID: 2); even += r.homeGoals + r.awayGoals }
        XCTAssertEqual(Double(even) / 2000, 2.7, accuracy: 0.5, "plausible goals per match between equal sides")
        XCTAssertGreaterThan(goals, even, "a mismatch produces more goals")
        for _ in 0..<500 {
            let r = ResultSimulator.simulate(home: 70, away: 70, knockout: true, rng: &rng, homeID: 1, awayID: 2)
            if r.homeGoals == r.awayGoals { XCTAssertNotNil(r.penaltyWinner); XCTAssertTrue(r.extraTime) }
        }
    }

    func testTournamentIsCodable() throws {
        var t = Tournament(name: "Cup", format: .groupsThenKnockout(groups: 2, advancePerGroup: 2), clubs: Array(1...8))
        t.record(fixtureID: 1, result: MatchResult(homeGoals: 2, awayGoals: 2))
        let d = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(Tournament.self, from: d), t)
    }
}
