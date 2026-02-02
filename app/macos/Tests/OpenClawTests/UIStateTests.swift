import XCTest
@testable import OpenClawLib

final class UIStateTests: XCTestCase {

    // MARK: - GatewayStatus

    func testGatewayStatusDecoding() throws {
        let json = #"{"uptime": 12345}"#
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(GatewayStatus.self, from: data)
        XCTAssertEqual(status.uptime, 12345)
    }

    func testGatewayStatusDecodingNullUptime() throws {
        let json = #"{"uptime": null}"#
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(GatewayStatus.self, from: data)
        XCTAssertNil(status.uptime)
    }

    func testGatewayStatusDecodingMissingUptime() throws {
        let json = #"{}"#
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(GatewayStatus.self, from: data)
        XCTAssertNil(status.uptime)
    }

    // MARK: - MenuBarStatus

    func testMenuBarStatusCases() {
        let starting: MenuBarStatus = .starting
        let running: MenuBarStatus = .running
        let stopped: MenuBarStatus = .stopped
        XCTAssertNotNil(starting)
        XCTAssertNotNil(running)
        XCTAssertNotNil(stopped)
    }

    // MARK: - Launcher Computed Properties

    @MainActor
    func testCompletedStepsCount() {
        let launcher = OpenClawLauncher()
        launcher.addStep(.done, "Step 1")
        launcher.addStep(.done, "Step 2")
        launcher.addStep(.running, "Step 3")
        XCTAssertEqual(launcher.completedStepsCount, 2)
    }

    @MainActor
    func testCurrentStep() {
        let launcher = OpenClawLauncher()
        launcher.addStep(.done, "Step 1")
        launcher.addStep(.running, "Step 2")
        launcher.addStep(.done, "Step 3")
        // currentStep returns the last running step
        XCTAssertEqual(launcher.currentStep?.message, "Step 2")
    }

    @MainActor
    func testCurrentStepNilWhenNoRunning() {
        let launcher = OpenClawLauncher()
        launcher.addStep(.done, "Step 1")
        XCTAssertNil(launcher.currentStep)
    }

    @MainActor
    func testErrorSteps() {
        let launcher = OpenClawLauncher()
        launcher.addStep(.done, "OK")
        launcher.addStep(.error, "Failed 1")
        launcher.addStep(.done, "OK 2")
        launcher.addStep(.error, "Failed 2")
        XCTAssertEqual(launcher.errorSteps.count, 2)
        XCTAssertEqual(launcher.errorSteps[0].message, "Failed 1")
        XCTAssertEqual(launcher.errorSteps[1].message, "Failed 2")
    }

    @MainActor
    func testProgressCalculation() {
        let launcher = OpenClawLauncher()
        // No steps = 0 progress
        XCTAssertEqual(launcher.progress, 0.0)

        // Add some completed steps
        launcher.addStep(.done, "Step 1")
        launcher.addStep(.done, "Step 2")
        // 2 out of 8 total steps
        XCTAssertEqual(launcher.progress, 0.25, accuracy: 0.01)
    }

    @MainActor
    func testProgressCapsAtOne() {
        let launcher = OpenClawLauncher()
        for i in 0..<20 {
            launcher.addStep(.done, "Step \(i)")
        }
        XCTAssertEqual(launcher.progress, 1.0)
    }

    @MainActor
    func testUptimeStringWithoutStart() {
        let launcher = OpenClawLauncher()
        XCTAssertEqual(launcher.uptimeString, "00:00:00")
    }

    @MainActor
    func testUptimeStringWithStart() {
        let launcher = OpenClawLauncher()
        launcher.containerStartTime = Date().addingTimeInterval(-65) // 1 min 5 sec ago
        let uptime = launcher.uptimeString
        XCTAssertTrue(uptime.hasPrefix("00:01:0"), "Expected ~00:01:05 but got \(uptime)")
    }

    @MainActor
    func testInitialMenuBarStatus() {
        let launcher = OpenClawLauncher()
        XCTAssertEqual(launcher.menuBarStatus, .stopped)
    }

    @MainActor
    func testInitialGatewayHealthy() {
        let launcher = OpenClawLauncher()
        XCTAssertFalse(launcher.gatewayHealthy)
    }
}
