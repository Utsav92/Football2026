import Foundation
import FootballGame

/// A player in the persistent database (separate from the runtime `Footballer` simulation state).
public struct PlayerRecord: Codable, Identifiable, Equatable {
    public var id: Int
    public var name: String
    public var number: Int
    public var role: Role
    public var attributes: PlayerAttributes
    public var appearance: Appearance
    public var age: Int
    public var potential: Int
    public var value: Int
    public var wage: Int
    public var contractYears: Int
    public var morale: Float
    public var fitness: Float
    public var injuredWeeks: Int

    public var profile: PlayerProfile { PlayerProfile(id: id, name: name, number: number, role: role, attributes: attributes, appearance: appearance) }
    public var isAvailable: Bool { injuredWeeks == 0 }

    /// Role-aware overall rating (goalkeepers are rated on their keeping attributes).
    public var rating: Int {
        if role == .gk { return Int(Float(attributes.goalkeeping) * 0.7 + Float(attributes.reactionTime) * 0.15 + Float(attributes.positioning) * 0.15) }
        return attributes.overall
    }
}

public struct ClubRecord: Codable, Identifiable, Equatable {
    public var id: Int
    public var name: String
    public var shortName: String
    public var city: String
    public var stadium: String
    public var primary: ColorRGB
    public var secondary: ColorRGB
    public var preferredFormation: Formation
    public var identity: String
    public var tactics: TeamTactics
    public var strength: Int
    public var budget: Int
    public var squad: [PlayerRecord]

    /// Best available XI for `formation`, then the remaining squad ordered by rating (a reserve goalkeeper first).
    /// Slot compatibility: exact role > same line (-6) > anything else (-20); injured players are skipped.
    public func teamSetup(formation: Formation? = nil) -> TeamSetup {
        let f = formation ?? preferredFormation
        var pool = squad.filter { $0.isAvailable }
        if pool.count < 11 { pool = squad }
        var xi: [PlayerRecord] = []
        for slot in f.slots {
            func score(_ p: PlayerRecord) -> Int {
                if slot.role == .gk { return p.role == .gk ? p.rating : -100 }
                if p.role == .gk { return -100 }
                return p.rating - (p.role == slot.role ? 0 : (p.role.line == slot.role.line ? 6 : 20))
            }
            guard let best = pool.max(by: { score($0) < score($1) }) else { continue }
            xi.append(best); pool.removeAll { $0.id == best.id }
        }
        pool.sort { $0.rating > $1.rating }
        if let g = pool.firstIndex(where: { $0.role == .gk }) { pool.insert(pool.remove(at: g), at: 0) }
        return TeamSetup(name: name, shortName: shortName, formation: f, tactics: tactics, primary: primary, secondary: secondary,
                         players: (xi + pool).map { $0.profile })
    }

    /// Average rating of the XI that would start (used by the statistical result simulator).
    public func xiStrength(formation: Formation? = nil) -> Float {
        let setup = teamSetup(formation: formation)
        let ids = Set(setup.players.prefix(11).map { $0.id })
        let xi = squad.filter { ids.contains($0.id) }
        return Float(xi.map { $0.rating }.reduce(0, +)) / Float(max(1, xi.count))
    }
}

public enum DatabaseError: Error, Equatable {
    case notFound, decode(String), invalid(String)
}

public struct GameDatabase: Codable, Equatable {
    public var schemaVersion: Int
    public var clubs: [ClubRecord]

    public static func load(from url: URL) throws -> GameDatabase {
        guard let data = try? Data(contentsOf: url) else { throw DatabaseError.notFound }
        do {
            let db = try JSONDecoder().decode(GameDatabase.self, from: data)
            try db.validate()
            return db
        } catch let e as DatabaseError { throw e }
        catch { throw DatabaseError.decode("\(error)") }
    }

    public func club(_ id: Int) -> ClubRecord? { clubs.first { $0.id == id } }
    public var allPlayers: [PlayerRecord] { clubs.flatMap { $0.squad } }

    /// Structural validation: unique ids, enough clubs/players, valid squads.
    public func validate(minClubs: Int = 20, minPlayers: Int = 400) throws {
        guard clubs.count >= minClubs else { throw DatabaseError.invalid("need >= \(minClubs) clubs, found \(clubs.count)") }
        let players = allPlayers
        guard players.count >= minPlayers else { throw DatabaseError.invalid("need >= \(minPlayers) players, found \(players.count)") }
        guard Set(players.map { $0.id }).count == players.count else { throw DatabaseError.invalid("duplicate player ids") }
        guard Set(clubs.map { $0.id }).count == clubs.count else { throw DatabaseError.invalid("duplicate club ids") }
        for c in clubs {
            guard c.squad.count >= 16 else { throw DatabaseError.invalid("\(c.name): squad < 16") }
            guard c.squad.filter({ $0.role == .gk }).count >= 2 else { throw DatabaseError.invalid("\(c.name): needs 2 goalkeepers") }
            guard Set(c.squad.map { $0.number }).count == c.squad.count else { throw DatabaseError.invalid("\(c.name): duplicate shirt numbers") }
            let xi = c.teamSetup().players.prefix(11)
            guard xi.count == 11, xi.first?.role == .gk else { throw DatabaseError.invalid("\(c.name): cannot form an XI") }
        }
    }
}
