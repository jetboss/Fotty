import Foundation

extension URL {
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        
        var dict: [String: String] = [:]
        for item in queryItems {
            dict[item.name] = item.value
        }
        return dict
    }
}
