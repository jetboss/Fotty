// Synthetic skill-evaluation fixture. Not a Fotty target or production source.
import SwiftUI

struct LabelState: Equatable {
    let id: Int
    let name: String
    let score: String
    let selected: Bool
}

struct LabelLine: View, Equatable {
    let state: LabelState
    var body: some View {
        HStack {
            Text(state.name)
            Text(state.score)
            if state.selected { Image(systemName: "checkmark") }
        }
    }
}

// A measured, cheap parent projection supplies LabelState values.
// Equality is synthesized over all fields rendered here.
// Source/behavior actions live outside this label-only subtree.
// Same-ID score changes create a changed LabelState.
// No runtime trace indicates this subtree is costly.
