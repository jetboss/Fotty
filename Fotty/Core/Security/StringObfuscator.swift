import Foundation

/// AUDIT FIX [5.2.3] - Stealth Obfuscation Layer
/// Used to mask sensitive hostnames and endpoints from binary scanners.
struct StringObfuscator {
    private static let key: [UInt8] = [0x46, 0x6F, 0x74, 0x74, 0x79, 0x41, 0x6E, 0x61, 0x6C, 0x79, 0x74, 0x69, 0x63, 0x73, 0x56, 0x32] // "FottyAnalyticsV2"

    /// Decodes an XOR-encoded byte array into a string.
    /// Note: The decoded string should only exist in local scope to avoid memory dumps.
    static func decode(_ encoded: [UInt8]) -> String {
        var decoded = [UInt8]()
        for i in 0..<encoded.count {
            decoded.append(encoded[i] ^ key[i % key.count])
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    #if DEBUG
    /// Helper to generate encoded arrays (for internal use during development)
    static func encode(_ input: String) -> [UInt8] {
        let inputBytes = [UInt8](input.utf8)
        var encoded = [UInt8]()
        for i in 0..<inputBytes.count {
            encoded.append(inputBytes[i] ^ key[i % key.count])
        }
        return encoded
    }
    #endif
}
