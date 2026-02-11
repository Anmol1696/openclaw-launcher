import SwiftUI
import Foundation
import os.log

private let logger = Logger(subsystem: "ai.openclaw.launcher", category: "Launcher")

// MARK: - Process Shell Executor (real implementation)

public struct ProcessShellExecutor: ShellExecutor {
    public init() {}

    public func run(_ args: [String]) async throws -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = DockerPaths.augmentedEnvironment()

        try process.run()

        let outData = await Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        let errData = await Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        process.waitUntilExit()

        return ShellResult(
            exitCode: Int(process.terminationStatus),
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

@MainActor
public class OpenClawLauncher: ObservableObject {
    @Published public var steps: [LaunchStep] = []
    @Published public var state: LauncherState = .idle
    @Published public var gatewayToken: String?
    @Published public var apiKeyInput: String = ""
    @Published public var oauthCodeInput: String = ""
    @Published public var showApiKeyField: Bool = false
    @Published public var gatewayHealthy: Bool = false
    @Published public var gatewayStatusData: GatewayStatus?
    @Published public var menuBarStatus: MenuBarStatus = .stopped
    @Published public var containerStartTime: Date?
    @Published public var uptimeTick: UInt = 0
    @Published public var pullProgressText: String?
    @Published public var containerLogs: String = ""
    @Published public var showLogSheet: Bool = false
    @Published public var showResetConfirm: Bool = false
    @Published public var needsDockerInstall: Bool = false
    @Published public var authExpiredBanner: String?
    @Published public var lastError: LauncherError?
    @Published public var activePort: Int = 18789  // The actual port being used (may be random)

    // Resource limits (configurable via settings)
    private var memoryLimit: String = "2g"
    private var cpuLimit: String = "2.0"

    /// Guards against concurrent start/stop operations to prevent race conditions
    private var isOperationInProgress = false
    private var isFirstRun = false
    private var currentPKCE: AnthropicOAuth.PKCE?
    private var healthCheckTimer: Timer?
    private var healthCheckFailCount = 0
    private var uptimeTimer: Timer?

    private let containerName = "openclaw"
    private let imageName = "ghcr.io/openclaw/openclaw:latest"
    private let defaultPort: Int = 18789
    private var hasStarted = false
    private let shellExecutor: ShellExecutor

    // Configurable for testing (avoid 90s waits)
    private let dockerRetryCount: Int
    private let dockerRetryDelayNs: UInt64
    private let gatewayRetryCount: Int
    private let gatewayRetryDelayNs: UInt64
    private let gatewayTimeoutSecs: TimeInterval

    private let stateDir: URL
    private var configDir: URL { stateDir.appendingPathComponent("config") }
    private var workspaceDir: URL { stateDir.appendingPathComponent("workspace") }
    private var envFile: URL { stateDir.appendingPathComponent(".env") }

    /// When true, suppresses real system side effects (opening browser, Docker.app, timers).
    /// Used in integration tests.
    public var suppressSideEffects = false

    public init(
        shell: ShellExecutor = ProcessShellExecutor(),
        stateDir: URL? = nil,
        dockerRetryCount: Int = 45,
        dockerRetryDelayNs: UInt64 = 2_000_000_000,
        gatewayRetryCount: Int = 30,
        gatewayRetryDelayNs: UInt64 = 2_000_000_000,  // 2 seconds between retries
        gatewayTimeoutSecs: TimeInterval = 5
    ) {
        self.shellExecutor = shell
        self.stateDir = stateDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-launcher")
        self.dockerRetryCount = dockerRetryCount
        self.dockerRetryDelayNs = dockerRetryDelayNs
        self.gatewayRetryCount = gatewayRetryCount
        self.gatewayRetryDelayNs = gatewayRetryDelayNs
        self.gatewayTimeoutSecs = gatewayTimeoutSecs
    }

    deinit {
        healthCheckTimer?.invalidate()
        uptimeTimer?.invalidate()
    }

    // MARK: - Computed Properties for UI

    public var currentStep: LaunchStep? {
        steps.last(where: { $0.status == .running })
    }

    public var completedStepsCount: Int {
        steps.filter { $0.status == .done }.count
    }

    public var errorSteps: [LaunchStep] {
        steps.filter { $0.status == .error }
    }

    /// Total logical launch steps: Docker check, first-run setup, auth, image pull, container start, gateway wait.
    private let totalLaunchSteps: Double = 8.0

    public var progress: Double {
        return min(Double(completedStepsCount) / totalLaunchSteps, 1.0)
    }

    public var uptimeString: String {
        _ = uptimeTick
        guard let start = containerStartTime else { return "00:00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Configuration

    /// Configure the port based on settings. Call this before starting the container.
    public func configurePort(useRandomPort: Bool, customPort: Int) {
        if useRandomPort {
            activePort = findAvailablePort()
            logger.info("Using random port: \(self.activePort)")
        } else {
            activePort = customPort
            logger.info("Using custom port: \(self.activePort)")
        }
    }

    /// Configure resource limits based on settings. Call this before starting the container.
    public func configureResources(memoryLimit: String, cpuLimit: String) {
        self.memoryLimit = memoryLimit
        self.cpuLimit = cpuLimit
        logger.info("Configured resources: memory=\(memoryLimit), cpu=\(cpuLimit)")
    }

    /// Find an available port in the ephemeral range (49152-65535)
    public func findAvailablePort() -> Int {
        // Try to find an available port by attempting to bind
        for _ in 0..<100 {
            let port = Int.random(in: 49152...65535)
            if isPortAvailable(port) {
                return port
            }
        }
        // Fallback to default if we can't find one
        logger.warning("Could not find available random port, using default")
        return defaultPort
    }

    /// Check if a port is available by attempting to create a socket
    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return bindResult == 0
    }

    // MARK: - Public

    public func start() {
        logger.info("start() called, state=\(String(describing: self.state)), hasStarted=\(self.hasStarted), inProgress=\(self.isOperationInProgress)")

        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.warning("start() called while operation in progress, ignoring")
            return
        }
        guard !hasStarted || state == .stopped || state == .error else { return }

        isOperationInProgress = true
        hasStarted = true
        steps = []
        needsDockerInstall = false
        lastError = nil
        state = .working
        menuBarStatus = .starting

        Task {
            defer { self.isOperationInProgress = false }

            do {
                // Quick check: is the container already running from a previous session?
                if await tryRecoverRunningContainer() { return }

                try await checkDocker()
                try await firstRunSetup()

                // Check for expired OAuth tokens and attempt refresh
                await refreshOAuthIfNeeded()

                // Pause for auth on first run
                if isFirstRun && !authProfileExists() && !oauthCredentialsExist() {
                    state = .needsAuth
                    return
                }

                try await continueAfterSetup()
            } catch {
                if let launcherError = error as? LauncherError {
                    lastError = launcherError
                    if case .dockerNotInstalled = launcherError {
                        needsDockerInstall = true
                    }
                } else {
                    lastError = nil
                }
                addStep(.error, error.localizedDescription)
                state = .error
                menuBarStatus = .stopped
            }
        }
    }

    /// Detect a running container from a previous app session and resume monitoring it.
    private func tryRecoverRunningContainer() async -> Bool {
        logger.info("tryRecoverRunningContainer: checking...")

        // Check if docker is even available (quick test, don't install)
        guard let info = try? await shell("docker", "info"),
              info.exitCode == 0 else {
            logger.info("tryRecoverRunningContainer: docker not available")
            return false
        }

        // Check if our container is running
        guard let ps = try? await shell("docker", "ps", "--filter", "name=^\(containerName)$", "--format", "{{.Names}}"),
              !ps.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("tryRecoverRunningContainer: container NOT running")
            return false
        }

        // Container is running — load config and resume
        logger.info("tryRecoverRunningContainer: container IS running, recovering")
        migrateOldStateDir()

        if let port = loadStoredPort() {
            activePort = port
            logger.info("tryRecoverRunningContainer: recovered port \(port)")
        }
        if let token = loadStoredToken() {
            gatewayToken = token
            logger.info("tryRecoverRunningContainer: recovered token")
        }

        addStep(.done, "Recovered running container")
        state = .running
        menuBarStatus = .running
        containerStartTime = Date() // approximate — we don't know exact start
        startHealthCheck()
        return true
    }

    public func stopContainer() {
        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.warning("stopContainer() called while operation in progress, ignoring")
            return
        }

        isOperationInProgress = true

        Task {
            defer { self.isOperationInProgress = false }

            addStep(.running, "Stopping OpenClaw...")
            _ = try? await shell("docker", "stop", containerName)
            addStep(.done, "Stopped.")
            steps = []
            uptimeTick = 0
            state = .stopped
            menuBarStatus = .stopped
            hasStarted = false  // Allow restart after stop
            stopHealthCheck()
        }
    }

    public func restartContainer() async {
        // Guard against concurrent operations
        guard !isOperationInProgress else {
            logger.warning("restartContainer() called while operation in progress, ignoring")
            return
        }

        isOperationInProgress = true
        defer { isOperationInProgress = false }

        addStep(.running, "Restarting...")
        menuBarStatus = .starting
        gatewayHealthy = false
        uptimeTick = 0
        do {
            let result = try await shell("docker", "restart", containerName)
            if result.exitCode != 0 {
                addStep(.error, "Failed to restart: \(result.stderr.prefix(200))")
                state = .error
                menuBarStatus = .stopped
                stopHealthCheck()
                return
            }
            addStep(.done, "Restarted")
            containerStartTime = Date()
            menuBarStatus = .running
            startHealthCheck()
        } catch {
            addStep(.error, "Failed to restart: \(error.localizedDescription)")
            state = .error
            menuBarStatus = .stopped
            stopHealthCheck()
        }
    }

    public func submitApiKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let authDir = configDir.appendingPathComponent("agents/default/agent")
            let authFile = authDir.appendingPathComponent("auth-profiles.json")
            let payload: [String: Any] = [
                "version": 1,
                "profiles": [
                    "anthropic:default": [
                        "type": "api_key",
                        "provider": "anthropic",
                        "key": key
                    ]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
               let _ = try? data.write(to: authFile) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
                addStep(.done, "API key saved")
            } else {
                addStep(.error, "Failed to save API key")
            }
        } else {
            addStep(.warning, "Skipped API key — set up later in Control UI")
        }

        state = .working
        Task {
            do {
                try await continueAfterSetup()
            } catch {
                addStep(.error, error.localizedDescription)
                state = .error
            }
        }
    }

    public func startOAuth() {
        do {
            let pkce = try AnthropicOAuth.generatePKCE()
            currentPKCE = pkce
            let url = AnthropicOAuth.buildAuthorizeURL(pkce: pkce)
            NSWorkspace.shared.open(url)
            showApiKeyField = false
            oauthCodeInput = ""
            state = .waitingForOAuthCode
            addStep(.running, "Opened browser for Anthropic sign-in")
        } catch {
            addStep(.error, "Failed to start OAuth: \(error.localizedDescription)")
        }
    }

    public func showApiKeyInput() {
        showApiKeyField = true
        apiKeyInput = ""
        state = .waitingForOAuthCode
    }

    public func skipAuth() {
        addStep(.warning, "Skipped auth — set up later in Control UI")
        state = .working
        Task {
            do { try await continueAfterSetup() }
            catch { addStep(.error, error.localizedDescription); state = .error }
        }
    }

    public func exchangeOAuthCode() {
        guard let pkce = currentPKCE else {
            addStep(.error, "No PKCE session. Try signing in again.")
            state = .needsAuth
            return
        }

        // Extract code from input — user may paste full URL or just the code
        var code = oauthCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlComponents = URLComponents(string: code),
           let codeParam = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
            code = codeParam
        }

        // Anthropic returns code in "code#state" format — split on #
        if code.contains("#") {
            let parts = code.split(separator: "#", maxSplits: 1)
            code = String(parts[0])
        }

        print("[OpenClaw] Exchanging code: \(code.prefix(8))...")
        addStep(.running, "Exchanging authorization code...")
        state = .working

        Task {
            do {
                let creds = try await AnthropicOAuth.exchangeCode(code: code, verifier: pkce.verifier)
                try saveOAuthCredentials(creds)
                addStep(.done, "Signed in with Claude")
                try await continueAfterSetup()
            } catch {
                addStep(.error, "OAuth exchange failed: \(error.localizedDescription)")
                state = .needsAuth
            }
        }
    }

    private func saveOAuthCredentials(_ creds: OAuthCredentials) throws {
        let credDir = configDir.appendingPathComponent("credentials")
        try FileManager.default.createDirectory(at: credDir, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        let oauthFile = credDir.appendingPathComponent("oauth.json")
        let json: [String: Any] = [
            "anthropic": [
                "type": creds.type,
                "refresh": creds.refresh,
                "access": creds.access,
                "expires": creds.expires,
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: oauthFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oauthFile.path)
    }

    private func oauthCredentialsExist() -> Bool {
        let oauthFile = configDir.appendingPathComponent("credentials/oauth.json")
        return FileManager.default.fileExists(atPath: oauthFile.path)
    }

    private func continueAfterSetup() async throws {
        try await ensureImage()
        try await runContainer()
        try await waitForGateway()

        state = .running
        menuBarStatus = .running
        containerStartTime = Date()
        startHealthCheck()
        openBrowser()
    }

    private func authProfileExists() -> Bool {
        let authFile = configDir.appendingPathComponent("agents/default/agent/auth-profiles.json")
        return FileManager.default.fileExists(atPath: authFile.path)
    }

    public func openBrowser() {
        guard !suppressSideEffects else {
            addStep(.done, "Opened Control UI in browser")
            return
        }

        // Always reload token from config to ensure we have the latest
        if let freshToken = loadStoredToken() {
            gatewayToken = freshToken
        }

        var urlString = "http://localhost:\(activePort)/openclaw"
        if let token = gatewayToken {
            urlString += "?token=\(token)"
        } else {
            logger.warning("openBrowser: no token available, browser may fail to authenticate")
        }
        let url = URL(string: urlString)!
        NSWorkspace.shared.open(url)
        addStep(.done, "Opened Control UI in browser")
    }

    public func viewLogs() {
        guard !suppressSideEffects else {
            showLogSheet = true
            return
        }
        // Fetch latest logs and show in-app viewer
        Task {
            if let result = try? await shell("docker", "logs", "--tail", "500", containerName) {
                containerLogs = result.stdout + result.stderr
            }
            showLogSheet = true
        }
    }

    public func openDockerDownload() {
        guard !suppressSideEffects else { return }
        let url = URL(string: "https://www.docker.com/products/docker-desktop/")!
        NSWorkspace.shared.open(url)
    }

    public func openDockerApp() {
        guard !suppressSideEffects else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
    }

    public func addStep(_ status: StepStatus, _ message: String) {
        steps.append(LaunchStep(status: status, message: message))
        if steps.count > 50 {
            steps.removeFirst(steps.count - 50)
        }
    }

    // MARK: - Reset & Cleanup

    public func resetEverything() {
        Task {
            // 1. Save the current token before deleting (preserves browser auth)
            let savedToken = loadStoredToken()

            addStep(.running, "Stopping container...")
            _ = try? await shell("docker", "stop", containerName)
            _ = try? await shell("docker", "rm", "-f", containerName)
            addStep(.done, "Container removed")

            // 2. Remove all local state
            try? FileManager.default.removeItem(at: stateDir)
            addStep(.done, "Local config cleaned up")

            // 3. Recreate .env with preserved token (so browser doesn't get out of sync)
            if let token = savedToken {
                try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
                let envContent = "OPENCLAW_GATEWAY_TOKEN=\(token)\nOPENCLAW_PORT=\(activePort)\n"
                try? envContent.write(to: envFile, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFile.path)
                logger.info("resetEverything: preserved gateway token")
            }

            // 4. Clear state (but keep token in memory)
            steps = []
            gatewayToken = savedToken
            uptimeTick = 0
            containerStartTime = nil
            gatewayHealthy = false
            gatewayStatusData = nil
            isFirstRun = false
            hasStarted = false
            state = .stopped
            menuBarStatus = .stopped
            authExpiredBanner = nil
            stopHealthCheck()
        }
    }

    // MARK: - Re-authenticate

    public func reAuthenticate() {
        Task {
            // Stop container if running
            if state == .running {
                _ = try? await shell("docker", "stop", containerName)
                stopHealthCheck()
            }

            // Delete auth files
            let authFile = configDir.appendingPathComponent("agents/default/agent/auth-profiles.json")
            let oauthFile = configDir.appendingPathComponent("credentials/oauth.json")
            try? FileManager.default.removeItem(at: authFile)
            try? FileManager.default.removeItem(at: oauthFile)

            steps = []
            gatewayHealthy = false
            uptimeTick = 0
            containerStartTime = nil
            hasStarted = false
            menuBarStatus = .stopped
            state = .needsAuth
        }
    }

    // MARK: - Log Viewer

    public func fetchLogs() {
        Task {
            let result = try? await shell("docker", "logs", "--tail", "300", containerName)
            let stdout = result?.stdout ?? ""
            let stderr = result?.stderr ?? ""
            containerLogs = stdout.isEmpty ? stderr : stdout + (stderr.isEmpty ? "" : "\n--- stderr ---\n" + stderr)
            showLogSheet = true
        }
    }

    // MARK: - OAuth Token Refresh

    private func refreshOAuthIfNeeded() async {
        let oauthFile = configDir.appendingPathComponent("credentials/oauth.json")
        guard FileManager.default.fileExists(atPath: oauthFile.path),
              let data = try? Data(contentsOf: oauthFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anthropic = json["anthropic"] as? [String: Any],
              let expires = anthropic["expires"] as? Int64,
              let refreshToken = anthropic["refresh"] as? String else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard nowMs >= expires else { return } // not expired

        // Attempt refresh
        do {
            let creds = try await AnthropicOAuth.refreshAccessToken(refreshToken: refreshToken)
            try saveOAuthCredentials(creds)
            addStep(.done, "OAuth token refreshed")
            authExpiredBanner = nil
        } catch {
            authExpiredBanner = "Auth expired — re-authenticate in Control UI"
            addStep(.warning, "OAuth token expired (refresh failed)")
        }
    }

    // MARK: - Token Generation

    public func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Steps

    private func checkDocker() async throws {
        addStep(.running, "Checking Docker...")

        // In production, use direct filesystem checks (no PATH dependency).
        // In tests (suppressSideEffects), skip filesystem checks and rely on
        // the mock shell executor for docker info.
        if !suppressSideEffects {
            let dockerBinary = DockerPaths.findDockerBinary()
            let dockerApp = DockerPaths.findInstalledApp()

            if dockerBinary == nil && dockerApp == nil {
                throw LauncherError.dockerNotInstalled
            }
        }

        let result = try? await shell("docker", "info")
        if result == nil || result!.exitCode != 0 {
            // Try to start Docker Desktop
            addStep(.warning, "Docker not running. Starting Docker Desktop...")
            if !suppressSideEffects {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
            }

            for _ in 0..<dockerRetryCount {
                try await Task.sleep(nanoseconds: dockerRetryDelayNs)
                let check = try? await shell("docker", "info")
                if check?.exitCode == 0 {
                    addStep(.done, "Docker is ready")
                    return
                }
            }
            throw LauncherError.dockerNotRunning
        }

        addStep(.done, "Docker is ready")
    }

    private func migrateOldStateDir() {
        let oldDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-docker")
        if FileManager.default.fileExists(atPath: oldDir.path)
            && !FileManager.default.fileExists(atPath: stateDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: stateDir)
            print("[OpenClaw] Migrated ~/.openclaw-docker → ~/.openclaw-launcher")
        }
    }

    /// Load the gateway token from stored config.
    /// Prefers openclaw.json (what the gateway uses) over .env.
    private func loadStoredToken() -> String? {
        let configFile = configDir.appendingPathComponent("openclaw.json")

        // Try openclaw.json first (authoritative source)
        if let data = try? Data(contentsOf: configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            return token
        }

        // Fallback to .env
        if let content = try? String(contentsOf: envFile, encoding: .utf8) {
            for line in content.split(separator: "\n") where line.hasPrefix("OPENCLAW_GATEWAY_TOKEN=") {
                return String(line.dropFirst("OPENCLAW_GATEWAY_TOKEN=".count))
            }
        }

        return nil
    }

    /// Load the port from .env file.
    private func loadStoredPort() -> Int? {
        guard let content = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") where line.hasPrefix("OPENCLAW_PORT=") {
            return Int(line.dropFirst("OPENCLAW_PORT=".count))
        }
        return nil
    }

    /// Ensure Docker config directory exists with isolated config (no credential helper).
    /// This prevents TCC permission dialogs when docker-credential-desktop accesses keychain.
    private func ensureDockerConfig() {
        let dockerDir = stateDir.appendingPathComponent(".docker")
        let dockerConfig = dockerDir.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: dockerConfig.path) {
            try? FileManager.default.createDirectory(at: dockerDir, withIntermediateDirectories: true)
            try? "{\n  \"auths\": {}\n}\n".write(to: dockerConfig, atomically: true, encoding: .utf8)
        }
    }

    private func firstRunSetup() async throws {
        migrateOldStateDir()

        // Check if config already exists
        let configFile = configDir.appendingPathComponent("openclaw.json")
        if FileManager.default.fileExists(atPath: configFile.path) {
            if let token = loadStoredToken() {
                gatewayToken = token
                logger.info("firstRunSetup: loaded existing token")
            }
            // Ensure Docker config exists (may have been deleted)
            ensureDockerConfig()
            addStep(.done, "Loaded existing configuration")
            return
        }

        isFirstRun = true
        addStep(.running, "First-time setup...")

        // Create directories
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)

        // Create isolated Docker config to avoid credential helper TCC dialogs
        ensureDockerConfig()

        // Generate token
        let token = generateSecureToken()
        gatewayToken = token

        // Write .env
        let envContent = "OPENCLAW_GATEWAY_TOKEN=\(token)\nOPENCLAW_PORT=\(activePort)\n"
        try envContent.write(to: envFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFile.path)

        // Write config with actual token value
        let config = """
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "\(token)"
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/openclaw",
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": { "primary": "anthropic/claude-opus-4-5" }
    }
  }
}
"""
        try config.write(to: configFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)

        // Create agent directories
        let agentDir = configDir.appendingPathComponent("agents/default/agent")
        let sessionsDir = configDir.appendingPathComponent("agents/default/sessions")
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        addStep(.done, "Configuration created")
    }

    private func ensureImage() async throws {
        addStep(.running, "Pulling latest image... this may take a moment")
        pullProgressText = nil

        let pullExitCode: Int
        if suppressSideEffects {
            // In tests, use the mock shell executor
            let pull = try await shell("docker", "pull", imageName)
            pullExitCode = pull.exitCode
        } else {
            // In production, stream progress from docker pull
            pullExitCode = Int(await pullImageWithProgress(imageName))
        }
        pullProgressText = nil

        if pullExitCode == 0 {
            addStep(.done, "Docker image up to date")
            return
        }

        // Pull failed — check if we have a local copy to fall back on
        let inspect = try? await shell("docker", "image", "inspect", imageName)
        if inspect?.exitCode == 0 {
            addStep(.warning, "Couldn't check for updates (offline?). Using cached image.")
            return
        }

        throw LauncherError.pullFailed("Image pull failed (exit code \(pullExitCode))")
    }

    /// Streams `docker pull` output and updates `pullProgressText` with download progress.
    private func pullImageWithProgress(_ image: String) async -> Int32 {
        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "pull", image]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        process.environment = DockerPaths.augmentedEnvironment()

        do {
            try process.run()
        } catch {
            logger.error("pullImageWithProgress: failed to start process: \(error.localizedDescription)")
            return -1
        }

        // Read stderr incrementally in background and parse progress
        let progressTask = Task.detached { [weak self] () -> Void in
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()

            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }  // EOF
                buffer.append(chunk)

                // Parse complete lines from buffer
                if let text = String(data: buffer, encoding: .utf8) {
                    let summary = Self.parsePullProgress(text)
                    if let summary = summary {
                        await MainActor.run { [weak self] in
                            self?.pullProgressText = summary
                        }
                    }
                }
            }
        }

        process.waitUntilExit()
        progressTask.cancel()

        return process.terminationStatus
    }

    /// Parse docker pull stderr output to produce a human-readable progress summary.
    /// Docker pull output has lines like: "abc123: Downloading  [===>   ]  50.12MB/400MB"
    /// We aggregate all "Downloading" layers into a total.
    nonisolated static func parsePullProgress(_ output: String) -> String? {
        let lines = output.split(separator: "\r").last.map { String($0) } ?? output
        let allLines = lines.split(separator: "\n")

        var totalDownloaded: Double = 0
        var totalSize: Double = 0
        var downloadingCount = 0
        var doneCount = 0
        var extractingCount = 0

        for line in allLines {
            let s = String(line)
            if s.contains("Downloading") {
                downloadingCount += 1
                // Parse "50.12MB/400MB" from the line
                if let (downloaded, size) = parseSizeFromLine(s) {
                    totalDownloaded += downloaded
                    totalSize += size
                }
            } else if s.contains("Download complete") || s.contains("Already exists") || s.contains("Pull complete") {
                doneCount += 1
            } else if s.contains("Extracting") {
                extractingCount += 1
            }
        }

        if extractingCount > 0 {
            return "Extracting layers..."
        }
        if downloadingCount > 0 && totalSize > 0 {
            return "Downloading \(formatBytes(totalDownloaded)) / \(formatBytes(totalSize))"
        }
        if downloadingCount > 0 {
            return "Downloading..."
        }
        if doneCount > 0 {
            return "\(doneCount) layers complete"
        }
        return nil
    }

    /// Parse "50.12MB/400MB" or "50.12kB/400kB" from a docker pull line.
    private nonisolated static func parseSizeFromLine(_ line: String) -> (Double, Double)? {
        // Match patterns like "123.45MB/678.9MB" or "123.45kB/678.9kB"
        let pattern = #"([\d.]+)\s*(kB|MB|GB)/([\d.]+)\s*(kB|MB|GB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 5 else { return nil }

        func extract(_ idx: Int) -> String? {
            guard let range = Range(match.range(at: idx), in: line) else { return nil }
            return String(line[range])
        }

        guard let downloadedStr = extract(1), let downloadedUnit = extract(2),
              let sizeStr = extract(3), let sizeUnit = extract(4),
              let downloaded = Double(downloadedStr), let size = Double(sizeStr) else { return nil }

        return (toBytes(downloaded, unit: downloadedUnit), toBytes(size, unit: sizeUnit))
    }

    private nonisolated static func toBytes(_ value: Double, unit: String) -> Double {
        switch unit {
        case "kB": return value * 1_000
        case "MB": return value * 1_000_000
        case "GB": return value * 1_000_000_000
        default: return value
        }
    }

    private nonisolated static func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", bytes / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.0f MB", bytes / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.0f kB", bytes / 1_000)
        }
        return "\(Int(bytes)) B"
    }

    private func runContainer() async throws {
        logger.info("runContainer: starting...")
        guard gatewayToken != nil else {
            throw LauncherError.noToken
        }

        // Check if already running
        let ps = try? await shell("docker", "ps", "--filter", "name=^\(containerName)$", "--format", "{{.Names}}")
        if let output = ps?.stdout, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.info("runContainer: container already running, skipping")
            addStep(.done, "Container already running")
            return
        }

        // Remove stopped container if exists
        logger.info("runContainer: removing old container...")
        _ = try? await shell("docker", "rm", "-f", containerName)

        addStep(.running, "Starting container (lockdown mode)...")

        // ================================================================
        //  SECURITY: Locked-down docker run
        // ================================================================
        let result = try await shell(
            "docker", "run", "-d",
            "--name", containerName,

            // --- Isolation ---
            "--init",                                   // tini as PID 1
            "--read-only",                              // read-only root filesystem
            "--tmpfs", "/tmp:rw,noexec,nosuid,size=256m",  // writable /tmp, no exec
            "--tmpfs", "/home/node/.npm:rw,size=64m",      // npm might need this

            // --- Resource limits (from settings) ---
            "--memory", memoryLimit,
            "--memory-swap", memoryLimit,               // no swap beyond memory limit
            "--cpus", cpuLimit,
            "--pids-limit", "256",                      // prevent fork bombs

            // --- Security ---
            "--cap-drop", "ALL",                        // drop ALL Linux capabilities
            "--cap-add", "NET_BIND_SERVICE",            // only allow binding ports
            "--security-opt", "no-new-privileges:true", // prevent privilege escalation

            // --- Network ---
            "-p", "127.0.0.1:\(activePort):18789",    // LOCALHOST ONLY — not exposed to network

            // --- Persistent state (mounted writable) ---
            "-v", "\(configDir.path):/home/node/.openclaw",
            "-v", "\(workspaceDir.path):/home/node/.openclaw/workspace",

            // --- Environment ---
            "-e", "HOME=/home/node",
            "-e", "TERM=xterm-256color",
            "--env-file", envFile.path,
            "-e", "NODE_ENV=production",

            // --- Restart policy ---
            "--restart", "unless-stopped",

            // --- Image ---
            imageName,

            // --- CMD override (upstream default is just `node dist/index.js`) ---
            "node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"
        )

        logger.info("runContainer: docker run exitCode=\(result.exitCode)")
        if result.exitCode != 0 {
            logger.error("runContainer: FAILED - \(result.stderr.prefix(200))")
            throw LauncherError.runFailed(result.stderr)
        }

        addStep(.done, "Container started (locked down)")
    }

    private func waitForGateway() async throws {
        addStep(.running, "Waiting for Gateway to be ready...")
        logger.info("waitForGateway: starting (max \(self.gatewayRetryCount) attempts)")

        let url = URL(string: "http://127.0.0.1:\(activePort)/openclaw/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // 5 second timeout per attempt

        for attempt in 1...gatewayRetryCount {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    logger.info("waitForGateway: attempt \(attempt), HTTP \(http.statusCode)")
                    if http.statusCode == 200 {
                        addStep(.done, "Gateway is ready!")
                        return
                    }
                }
            } catch {
                logger.info("waitForGateway: attempt \(attempt), error: \(error.localizedDescription)")
            }

            try await Task.sleep(nanoseconds: gatewayRetryDelayNs)
        }

        // Not fatal — might just be slow
        logger.warning("waitForGateway: TIMEOUT after \(self.gatewayRetryCount) attempts")
        addStep(.warning, "Gateway is still starting. Try opening the browser anyway.")
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        guard !suppressSideEffects else { return }
        stopHealthCheck()

        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.uptimeTick += 1
            }
        }

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.checkGatewayHealth()
            }
        }

        Task {
            await checkGatewayHealth()
        }
    }

    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    private func checkGatewayHealth() async {
        let url = URL(string: "http://127.0.0.1:\(activePort)/openclaw/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run {
                    gatewayHealthy = true
                    healthCheckFailCount = 0
                }
                return
            }
        } catch {
            logger.info("checkGatewayHealth: error: \(error.localizedDescription)")
        }

        await handleHealthCheckFailure()
    }

    @MainActor private func handleHealthCheckFailure() async {
        gatewayHealthy = false
        gatewayStatusData = nil
        healthCheckFailCount += 1

        // After 3 consecutive failures, check if container is still running
        if healthCheckFailCount >= 3 {
            let ps = try? await shell("docker", "ps", "--filter", "name=^\(containerName)$", "--format", "{{.Names}}")
            let running = !(ps?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !running {
                addStep(.error, "Container stopped unexpectedly")
                state = .error
                menuBarStatus = .stopped
                stopHealthCheck()
            }
        }
    }

    // MARK: - Shell Helper

    private func shell(_ args: String...) async throws -> ShellResult {
        try await shellExecutor.run(args)
    }

}
