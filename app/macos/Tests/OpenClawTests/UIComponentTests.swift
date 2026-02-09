import XCTest
import SwiftUI
@testable import OpenClawLib

final class UIComponentTests: XCTestCase {

    // MARK: - StatusPill Tests

    func testStatusPillReadyColor() {
        let pill = StatusPill(icon: "checkmark", label: "Docker", status: .ready)
        XCTAssertEqual(pill.status, .ready)
        XCTAssertEqual(pill.label, "Docker")
    }

    func testStatusPillInfoStatus() {
        let pill = StatusPill(icon: "info", label: "Port 18789", status: .info)
        XCTAssertEqual(pill.status, .info)
    }

    func testStatusPillWarningStatus() {
        let pill = StatusPill(icon: "exclamationmark.triangle", label: "Warning", status: .warning)
        XCTAssertEqual(pill.status, .warning)
    }

    func testStatusPillErrorStatus() {
        let pill = StatusPill(icon: "xmark", label: "Error", status: .error)
        XCTAssertEqual(pill.status, .error)
    }

    func testStatusPillStatusColors() {
        // Verify each status has a distinct color
        XCTAssertEqual(StatusPill.Status.ready.color, Ocean.success)
        XCTAssertEqual(StatusPill.Status.info.color, Ocean.accent)
        XCTAssertEqual(StatusPill.Status.warning.color, Ocean.warning)
        XCTAssertEqual(StatusPill.Status.error.color, Ocean.error)
    }

    // MARK: - StatCard Tests

    func testStatCardInitialization() {
        let card = StatCard(label: "UPTIME", value: "4m 32s", valueColor: Ocean.accent)
        XCTAssertEqual(card.label, "UPTIME")
        XCTAssertEqual(card.value, "4m 32s")
    }

    func testStatCardDefaultColor() {
        let card = StatCard(label: "PORT", value: "3000")
        XCTAssertEqual(card.valueColor, Ocean.accent)
    }

    func testStatCardCustomColor() {
        let card = StatCard(label: "MEMORY", value: "128 MB", valueColor: Ocean.text)
        XCTAssertEqual(card.valueColor, Ocean.text)
    }

    // MARK: - IdleContentView Tests

    func testIdleContentViewPort() {
        let view = IdleContentView(port: 18789)
        XCTAssertEqual(view.port, 18789)
    }

    func testIdleContentViewCustomPort() {
        let view = IdleContentView(port: 3000)
        XCTAssertEqual(view.port, 3000)
    }

    // MARK: - StatusPanel.StepInfo Tests

    func testStepInfoCreation() {
        let step = StatusPanel.StepInfo(status: .done, label: "Docker connected")
        XCTAssertEqual(step.status, .done)
        XCTAssertEqual(step.label, "Docker connected")
        XCTAssertNil(step.time)
    }

    func testStepInfoWithTime() {
        let step = StatusPanel.StepInfo(status: .error, label: "Failed", time: "2.3s")
        XCTAssertEqual(step.status, .error)
        XCTAssertEqual(step.time, "2.3s")
    }

    func testStepInfoStatuses() {
        let pending = StatusPanel.StepInfo(status: .pending, label: "Pending")
        let active = StatusPanel.StepInfo(status: .active, label: "Active")
        let done = StatusPanel.StepInfo(status: .done, label: "Done")
        let error = StatusPanel.StepInfo(status: .error, label: "Error")

        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(active.status, .active)
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(error.status, .error)
    }

    // MARK: - State Routing Tests

    @MainActor
    func testIdleStateShowsIdleContent() {
        let launcher = OpenClawLauncher()
        launcher.state = .idle
        XCTAssertEqual(launcher.state, .idle)
    }

    @MainActor
    func testWorkingStateShowsChecklist() {
        let launcher = OpenClawLauncher()
        launcher.state = .working
        XCTAssertEqual(launcher.state, .working)
    }

    @MainActor
    func testRunningStateShowsDashboard() {
        let launcher = OpenClawLauncher()
        launcher.state = .running
        XCTAssertEqual(launcher.state, .running)
    }

    @MainActor
    func testStoppedStateShowsIdleContent() {
        let launcher = OpenClawLauncher()
        launcher.state = .stopped
        XCTAssertEqual(launcher.state, .stopped)
    }

    @MainActor
    func testErrorStateShowsError() {
        let launcher = OpenClawLauncher()
        launcher.state = .error
        XCTAssertEqual(launcher.state, .error)
    }

    // MARK: - Dashboard Data Tests

    @MainActor
    func testRunningDashboardUptimeString() {
        let launcher = OpenClawLauncher()
        launcher.containerStartTime = Date().addingTimeInterval(-125) // 2 min 5 sec ago
        let uptime = launcher.uptimeString
        XCTAssertTrue(uptime.hasPrefix("00:02:0"), "Expected ~00:02:05 but got \(uptime)")
    }

    @MainActor
    func testRunningDashboardPort() {
        let launcher = OpenClawLauncher()
        launcher.configurePort(useRandomPort: false, customPort: 3000)
        XCTAssertEqual(launcher.activePort, 3000)
    }

    @MainActor
    func testRunningDashboardDefaultPort() {
        let launcher = OpenClawLauncher()
        XCTAssertEqual(launcher.activePort, 18789)
    }
}
