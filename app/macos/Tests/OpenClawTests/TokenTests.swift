import XCTest
@testable import OpenClawLib

final class TokenTests: XCTestCase {

    @MainActor
    func testSecureTokenLength() {
        let launcher = OpenClawLauncher()
        let token = launcher.generateSecureToken()
        XCTAssertEqual(token.count, 64, "Token should be 64 hex characters (32 bytes)")
    }

    @MainActor
    func testSecureTokenHexOnly() {
        let launcher = OpenClawLauncher()
        let token = launcher.generateSecureToken()
        let hexPattern = #"^[0-9a-f]+$"#
        XCTAssertNotNil(token.range(of: hexPattern, options: .regularExpression),
                        "Token should contain only lowercase hex characters")
    }

    @MainActor
    func testSecureTokenUniqueness() {
        let launcher = OpenClawLauncher()
        let token1 = launcher.generateSecureToken()
        let token2 = launcher.generateSecureToken()
        XCTAssertNotEqual(token1, token2)
    }
}
