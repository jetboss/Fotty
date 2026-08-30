import Foundation

// MARK: - API-Football Response Wrapper
struct APIFootballResponseWrapper<T: Decodable>: Decodable {
    let response: [T]
}

// MARK: - Match Statistics Models
struct APIFootballStatistics: Decodable {
    let team: APIFootballTeam
    let statistics: [APIFootballStatItem]
}

struct APIFootballStatItem: Decodable {
    let type: String
    let value: APIFootballStatValue?
}

enum APIFootballStatValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(Double.self) {
            self = .double(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(APIFootballStatValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for APIFootballStatValue"))
    }
}

// MARK: - Lineup Models
struct APIFootballLineup: Decodable {
    let team: APIFootballTeam
    let formation: String?
    let startXI: [APIFootballLineupPlayer]
    let substitutes: [APIFootballLineupPlayer]
    let coach: APIFootballCoach
}

struct APIFootballLineupPlayer: Decodable {
    let player: APIFootballPlayerInfo
}

struct APIFootballPlayerInfo: Decodable {
    let id: Int
    let name: String
    let number: Int?
    let pos: String?
    let grid: String?
}

struct APIFootballCoach: Decodable {
    let id: Int?
    let name: String?
    let photo: String?
}
