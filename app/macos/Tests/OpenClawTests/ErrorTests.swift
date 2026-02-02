import XCTest
@testable import OpenClawLib

final class ErrorTests: XCTestCase {

    func testAllErrorCasesHaveDescriptions() {
        let cases: [LauncherError] = [
            .dockerNotRunning,
            .dockerInstallFailed("test"),
            .pullFailed("test"),
            .runFailed("test"),
            .noToken,
        ]

        for error in cases {
            let description = error.errorDescription
            XCTAssertNotNil(description, "\(error) should have a description")
            XCTAssertFalse(description!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testErrorMessageContent() {
        XCTAssertTrue(
            LauncherError.dockerNotRunning.errorDescription!.contains("Docker Desktop"),
            "Should mention Docker Desktop")

        XCTAssertTrue(
            LauncherError.noToken.errorDescription!.contains(".openclaw-launcher"),
            "Should reference the state directory")

        XCTAssertTrue(
            LauncherError.pullFailed("some error").errorDescription!.contains("Docker image"),
            "Should mention Docker image")

        XCTAssertTrue(
            LauncherError.runFailed("some error").errorDescription!.contains("container"),
            "Should mention container")

        XCTAssertTrue(
            LauncherError.dockerInstallFailed("reason").errorDescription!.contains("reason"),
            "Should include the failure reason")
    }
}
