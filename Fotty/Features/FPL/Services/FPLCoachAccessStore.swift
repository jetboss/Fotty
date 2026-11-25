import Foundation
import Security

enum FPLCoachAccessError: LocalizedError {
    case invalidCode
    case secureStorageUnavailable
    case insecureDestination

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Use the complete 64-character private invitation code supplied by your inviter."
        case .secureStorageUnavailable: return "The private code could not be accessed securely. Unlock this device and try again."
        case .insecureDestination: return "Private Coach access requires a secure connection."
        }
    }
}

enum FPLCoachAccessStore {
    private static let service = "com.jelani.Fotty.privateCoach"
    private static let account = "private-invitation-v1"
    private static let installMarker = "fotty.coach.keychain-install-v1"
    private static let storageLock = NSLock()

    static func validated(_ value: String) throws -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 64, code.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw FPLCoachAccessError.invalidCode
        }
        return code
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private static func prepareInstall() throws {
        // Keychain entries can survive uninstall. Never reuse a prior install's
        // credential after its local marker has disappeared.
        guard !UserDefaults.standard.bool(forKey: installMarker) else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FPLCoachAccessError.secureStorageUnavailable }
        UserDefaults.standard.set(true, forKey: installMarker)
    }

    static func load() throws -> String? {
        storageLock.lock()
        defer { storageLock.unlock() }
        try prepareInstall()
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let code = String(data: data, encoding: .utf8) else { throw FPLCoachAccessError.secureStorageUnavailable }
        return try validated(code)
    }

    static func save(_ value: String) throws {
        let code = try validated(value)
        storageLock.lock()
        defer { storageLock.unlock() }
        try prepareInstall()
        let attributes: [String: Any] = [
            kSecValueData as String: Data(code.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            attributes.forEach { entry[$0.key] = $0.value }
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw FPLCoachAccessError.secureStorageUnavailable }
        } else if status != errSecSuccess { throw FPLCoachAccessError.secureStorageUnavailable }
    }

    static func remove() throws {
        storageLock.lock()
        defer { storageLock.unlock() }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FPLCoachAccessError.secureStorageUnavailable }
    }

    static func authorize(_ request: inout URLRequest, code: String?) throws {
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        guard let code else { return }
        guard request.url?.scheme?.lowercased() == "https",
              request.url?.user == nil, request.url?.password == nil else { throw FPLCoachAccessError.insecureDestination }
        request.setValue("Bearer \(try validated(code))", forHTTPHeaderField: "Authorization")
    }
}

final class FPLCoachRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = FPLCoachRedirectDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The configured Worker is the only recipient of the private token.
        completionHandler(nil)
    }
}
