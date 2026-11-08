// Synthetic skill-evaluation fixture. Not a Fotty target or production source.
import SwiftUI

struct Game: Identifiable, Equatable {
    let id: Int
    var name: String
    var score: String
}

struct GameLine: View, Equatable {
    let game: Game
    static func == (a: Self, b: Self) -> Bool { a.game.id == b.game.id }
    var body: some View { Text("\(game.name): \(game.score)") }
}

struct GameShelf: View {
    let games: [Game]
    @State private var ordered: [Game] = []
    var body: some View {
        List(ordered) { game in GameLine(game: game).equatable() }
            .onChange(of: games) { _, updated in
                ordered = updated.sorted { $0.name < $1.name }
            }
    }
}

// Supplied reproduction:
// 1. Shelf first appears with a nonempty, already loaded games array.
// 2. The array remains unchanged until a later server update.
// 3. After a later update populates the shelf, game 7's score changes,
//    while its ID and name are unchanged. No independent row state changes.
