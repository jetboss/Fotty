import XCTest
@testable import Fotty

final class FPLCoachAccessTests: XCTestCase {
    func testPrivateCodeNormalizationRejectsMalformedInput() throws {
        let code = String(repeating: "AB", count: 32)
        XCTAssertEqual(try FPLCoachAccessStore.validated(" \(code)\n"), code.lowercased())
        for invalid in ["", "short", String(repeating: "z", count: 64), String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try FPLCoachAccessStore.validated(invalid))
        }
    }

    func testAuthorizationIsHeaderOnlyAndRequiresHTTPS() throws {
        let code = String(repeating: "ab", count: 32)
        let endpoint = URL(string: "https://coach.example/api/fpl/coach")!
        var request = URLRequest(url: endpoint)
        try FPLCoachAccessStore.authorize(&request, code: code)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(code)")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertNil(request.httpBody)
        try FPLCoachAccessStore.authorize(&request, code: nil)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        request.url = URL(string: "http://coach.example/api/fpl/coach")!
        XCTAssertThrowsError(try FPLCoachAccessStore.authorize(&request, code: code))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
