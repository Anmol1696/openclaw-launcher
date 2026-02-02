import XCTest
@testable import OpenClawLib

/// Integration tests exercising OpenClawLauncher with MockShellExecutor.
/// All tests use a temporary directory for state (never touches ~/.openclaw-launcher),
/// suppressSideEffects=true so no browser/Docker.app opens, no timers fire,
/// and no real network calls happen.
@MainActor
final class LauncherIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private var tempStateDir: URL!

    override func setUp() {
        super.setUp()
        tempStateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let dir = tempStateDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempStateDir = nil
        super.tearDown()
    }

    /// Create a test launcher with mock shell, temp state dir, fast retries, and no side effects.
    private func makeLauncher(mock: MockShellExecutor) -> OpenClawLauncher {
        let launcher = OpenClawLauncher(
            shell: mock,
            stateDir: tempStateDir,
            dockerRetryCount: 2,         // 2 retries instead of 45
            dockerRetryDelayNs: 1_000,   // ~instant instead of 2s
            gatewayRetryCount: 2,
            gatewayRetryDelayNs: 1_000
        )
        launcher.suppressSideEffects = true
        return launcher
    }

    /// Pre-seed the temp state dir so firstRunSetup loads existing config.
    @discardableResult
    private func seedStateDir() throws -> URL {
        let configDir = tempStateDir.appendingPathComponent("config")
        let agentDir = configDir.appendingPathComponent("agents/default/agent")
        let sessionsDir = configDir.appendingPathComponent("agents/default/sessions")

        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let envFile = tempStateDir.appendingPathComponent(".env")
        try "OPENCLAW_GATEWAY_TOKEN=testtoken123\nOPENCLAW_PORT=18789\n"
            .write(to: envFile, atomically: true, encoding: .utf8)

        let configFile = configDir.appendingPathComponent("openclaw.json")
        try "{}".write(to: configFile, atomically: true, encoding: .utf8)

        // Auth profile so launcher doesn't pause for auth
        let authFile = agentDir.appendingPathComponent("auth-profiles.json")
        try "{\"version\":1}".write(to: authFile, atomically: true, encoding: .utf8)

        return tempStateDir
    }

    /// Wait for launcher state to settle (not .working).
    private func waitForCompletion(
        _ launcher: OpenClawLauncher,
        timeout: TimeInterval = 5.0
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while (launcher.state == .working || launcher.state == .idle) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    // MARK: - Docker Error Tests

    func testDockerNotRunning_ThrowsError() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.fail(stderr: "Cannot connect"))
        mock.defaultResult = MockShellExecutor.fail

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .error)
        XCTAssertEqual(launcher.menuBarStatus, .stopped)

        let errorMessages = launcher.steps.filter { $0.status == .error }.map(\.message)
        XCTAssertTrue(
            errorMessages.contains(where: { $0.contains("Docker") }),
            "Error should mention Docker: \(errorMessages)"
        )
    }

    // MARK: - Image Pull Error Tests

    func testPullFails_NoCachedImage() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("pull") }, return: MockShellExecutor.fail(stderr: "network timeout"))
        mock.on({ $0.contains("inspect") }, return: MockShellExecutor.fail)
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .error)
        let errorMessages = launcher.steps.filter { $0.status == .error }.map(\.message)
        XCTAssertTrue(
            errorMessages.contains(where: { $0.contains("Docker image") || $0.contains("pull") }),
            "Error should mention image pull: \(errorMessages)"
        )
    }

    func testPullFails_FallsBackToCachedImage() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("pull") }, return: MockShellExecutor.fail(stderr: "network timeout"))
        mock.on({ $0.contains("inspect") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("ps") }, return: MockShellExecutor.ok(stdout: ""))
        mock.on({ $0.contains("rm") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("run") && $0.contains("-d") }, return: MockShellExecutor.ok)
        mock.on("curl", return: MockShellExecutor.ok)
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .running)
        let warningMessages = launcher.steps.filter { $0.status == .warning }.map(\.message)
        XCTAssertTrue(
            warningMessages.contains(where: { $0.contains("cached") || $0.contains("offline") }),
            "Should warn about cached image: \(warningMessages)"
        )
    }

    // MARK: - Container Error Tests

    func testRunContainerFails() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("pull") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("ps") }, return: MockShellExecutor.ok(stdout: ""))
        mock.on({ $0.contains("rm") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("run") && $0.contains("-d") }, return: MockShellExecutor.fail(stderr: "port already in use"))
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .error)
        let errorMessages = launcher.steps.filter { $0.status == .error }.map(\.message)
        XCTAssertTrue(
            errorMessages.contains(where: { $0.contains("container") || $0.contains("port") }),
            "Error should mention container failure: \(errorMessages)"
        )
    }

    func testContainerAlreadyRunning_SkipsPullAndRun() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("pull") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("ps") }, return: MockShellExecutor.ok(stdout: "openclaw\n"))
        mock.on("curl", return: MockShellExecutor.ok)
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .running)
        let runCommands = mock.commandLog.filter { $0.contains("run") && $0.contains("-d") }
        XCTAssertTrue(runCommands.isEmpty, "Should not call docker run when container already running")
    }

    // MARK: - Recovery Tests

    func testRecoverRunningContainer() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("ps") }, return: MockShellExecutor.ok(stdout: "openclaw\n"))
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .running)
        XCTAssertEqual(launcher.menuBarStatus, .running)
        let messages = launcher.steps.map(\.message)
        XCTAssertTrue(
            messages.contains(where: { $0.contains("Recovered") }),
            "Should have recovery step: \(messages)"
        )
    }

    // MARK: - Gateway Tests

    func testGatewayTimeout_NonFatal() async throws {
        try seedStateDir()

        let mock = MockShellExecutor()
        mock.on("which", return: MockShellExecutor.ok(stdout: "/usr/local/bin/docker\n"))
        mock.on({ $0.contains("info") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("pull") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("ps") }, return: MockShellExecutor.ok(stdout: ""))
        mock.on({ $0.contains("rm") }, return: MockShellExecutor.ok)
        mock.on({ $0.contains("run") && $0.contains("-d") }, return: MockShellExecutor.ok)
        mock.on("curl", return: MockShellExecutor.fail)
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.start()
        await waitForCompletion(launcher)

        XCTAssertEqual(launcher.state, .running)
        let warningMessages = launcher.steps.filter { $0.status == .warning }.map(\.message)
        XCTAssertTrue(
            warningMessages.contains(where: { $0.contains("still starting") || $0.contains("browser") }),
            "Should have gateway timeout warning: \(warningMessages)"
        )
    }

    // MARK: - Restart / Stop Tests

    func testRestartFails() async throws {
        let mock = MockShellExecutor()
        mock.on({ $0.contains("restart") }, return: MockShellExecutor.fail(stderr: "no such container"))
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.state = .running
        launcher.menuBarStatus = .running

        await launcher.restartContainer()

        XCTAssertEqual(launcher.state, .error)
        XCTAssertEqual(launcher.menuBarStatus, .stopped)
        let errorMessages = launcher.steps.filter { $0.status == .error }.map(\.message)
        XCTAssertFalse(errorMessages.isEmpty, "Should have error step for failed restart")
    }

    func testStopAlwaysSucceeds() async throws {
        let mock = MockShellExecutor()
        mock.on({ $0.contains("stop") }, return: MockShellExecutor.fail(stderr: "no such container"))
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.state = .running

        launcher.stopContainer()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms for Task to complete

        XCTAssertEqual(launcher.state, .stopped)
        XCTAssertEqual(launcher.menuBarStatus, .stopped)
    }

    // MARK: - Error Message Quality Tests

    func testErrorStepsContainActionableMessages() async throws {
        let errors: [LauncherError] = [
            .dockerNotRunning,
            .dockerInstallFailed("DMG mount failed"),
            .pullFailed("network unreachable"),
            .runFailed("port 18789 already in use"),
            .noToken,
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "\(error) should have a description")
            let hasKeyword = description.contains("Docker") || description.contains("container")
                || description.contains("image") || description.contains("token")
                || description.contains("resetting")
            XCTAssertTrue(hasKeyword, "Error '\(description)' should contain actionable keyword")
        }
    }

    func testCommandsAreLogged() async throws {
        let mock = MockShellExecutor()
        mock.defaultResult = MockShellExecutor.ok

        let launcher = makeLauncher(mock: mock)
        launcher.state = .running

        launcher.stopContainer()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(mock.commandLog.isEmpty, "Mock should record commands")
        let stopCommands = mock.commandLog.filter { $0.contains("stop") }
        XCTAssertFalse(stopCommands.isEmpty, "Should have logged docker stop command")
    }
}
