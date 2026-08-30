import Foundation
import Combine

enum FPLManagerIDParser {
    /// Extract only an ID. Never fetch a URL supplied by the user.
    static func parse(_ input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = positiveInteger(value) { return id }
        let address = value.hasPrefix("fantasy.premierleague.com/") ? "https://\(value)" : value
        guard let url = URLComponents(string: address),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == "fantasy.premierleague.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        let entryIndex = path.first == "a" || path.first == "api" ? 1 : 0
        guard path.indices.contains(entryIndex + 1), path[entryIndex] == "entry" else { return nil }
        return positiveInteger(path[entryIndex + 1])
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let id = Int(value), id > 0 else { return nil }
        return id
    }
}

struct FPLManagerIdentity: Equatable {
    let id: Int
    let teamName: String
    let managerName: String
    let sourceDescription: String
}

/// A lookup never changes the selected manager. Only the user's confirmation does.
@MainActor
final class FPLManagerConnectionModel: ObservableObject {
    @Published private(set) var identity: FPLManagerIdentity?
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?
    private var requestID = UUID()
    private let fetchIdentity: (Int) async throws -> FPLManagerIdentity

    init(fetchIdentity: @escaping (Int) async throws -> FPLManagerIdentity = { id in
        let resource = try await FPLService.shared.fetchManagerSummaryResource(id: id)
        return FPLManagerIdentity(
            id: resource.value.id,
            teamName: resource.value.name,
            managerName: resource.value.fullName,
            sourceDescription: "\(resource.metadata.source.rawValue) · \(resource.metadata.shortAgeDescription)"
        )
    }) {
        self.fetchIdentity = fetchIdentity
    }

    func reset() {
        requestID = UUID()
        identity = nil
        errorMessage = nil
        isChecking = false
    }

    func lookup(_ input: String) async {
        guard !Task.isCancelled else { return }
        reset()
        guard let id = FPLManagerIDParser.parse(input) else {
            errorMessage = "Paste your official FPL team link or enter a positive manager ID."
            return
        }
        let request = requestID
        isChecking = true
        defer { if requestID == request { isChecking = false } }
        do {
            let result = try await fetchIdentity(id)
            guard !Task.isCancelled, requestID == request else { return }
            guard result.id == id else { throw URLError(.badServerResponse) }
            identity = result
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            if (error as? URLError)?.code == .notConnectedToInternet {
                errorMessage = "You're offline. Reconnect and try again, or edit the team link."
            } else {
                errorMessage = "We couldn't check this team. Check the link or ID and try again. FPL may also be temporarily unavailable."
            }
        }
    }
}
