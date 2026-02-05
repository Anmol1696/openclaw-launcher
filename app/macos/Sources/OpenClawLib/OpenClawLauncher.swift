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
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/Applications/Docker.app/Contents/Resources/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        try process.run()

        let outData = try await Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        let errData = try await Task.detached {
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
    @Published public var selectedProvider: AuthProvider?

    private var isFirstRun = false
    private var currentPKCE: AnthropicOAuth.PKCE?
    private var healthCheckTimer: Timer?
    private var healthCheckFailCount = 0
    private var uptimeTimer: Timer?

    private let containerName = "openclaw"
    private let imageName = "ghcr.io/openclaw/openclaw:latest"
    private let port: Int = 18789
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

    // MARK: - Public

    public func start() {
        logger.info("start() called, state=\(String(describing: self.state)), hasStarted=\(self.hasStarted)")
        guard !hasStarted || state == .stopped || state == .error else { return }
        hasStarted = true
        steps = []
        needsDockerInstall = false
        state = .working
        menuBarStatus = .starting

        Task {
            do {
                // Quick check: is the container already running from a previous session?
                if await tryRecoverRunningContainer() { return }

                try await checkDocker()
                try await firstRunSetup()

                // Check for expired OAuth tokens and attempt refresh
                await refreshOAuthIfNeeded()

                // Note if no auth configured (non-blocking - user can configure in Control UI)
                if isFirstRun && !authProfileExists() && !oauthCredentialsExist() {
                    addStep(.warning, "No model auth configured — set up in Control UI")
                }

                try await continueAfterSetup()
            } catch {
                if let launcherError = error as? LauncherError,
                   case .dockerNotInstalled = launcherError {
                    needsDockerInstall = true
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
        if FileManager.default.fileExists(atPath: envFile.path) {
            if let content = try? String(contentsOf: envFile, encoding: .utf8) {
                for line in content.split(separator: "\n") {
                    if line.hasPrefix("OPENCLAW_GATEWAY_TOKEN=") {
                        gatewayToken = String(line.dropFirst("OPENCLAW_GATEWAY_TOKEN=".count))
                    }
                }
            }
        }

        addStep(.done, "Recovered running container")
        state = .running
        menuBarStatus = .running
        containerStartTime = Date() // approximate — we don't know exact start
        startHealthCheck()
        return true
    }

    public func stopContainer() {
        Task {
            addStep(.running, "Stopping OpenClaw...")
            _ = try? await shell("docker", "stop", containerName)
            addStep(.done, "Stopped.")
            steps = []
            uptimeTick = 0
            state = .stopped
            menuBarStatus = .stopped
            stopHealthCheck()
        }
    }

    public func restartContainer() async {
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

    // MARK: - Provider Selection

    public func selectProvider(_ provider: AuthProvider) {
        selectedProvider = provider
        apiKeyInput = ""

        if provider.supportsOAuth {
            // Show choice between OAuth and API key for Anthropic
            state = .selectingProvider
        } else {
            // Go directly to API key input for OpenAI/Google
            state = .waitingForApiKey
        }
    }

    public func startOAuthForProvider() {
        guard selectedProvider == .anthropic else { return }
        do {
            let pkce = try AnthropicOAuth.generatePKCE()
            currentPKCE = pkce
            let url = AnthropicOAuth.buildAuthorizeURL(pkce: pkce)
            NSWorkspace.shared.open(url)
            oauthCodeInput = ""
            state = .waitingForOAuthCode
            addStep(.running, "Opened browser for Anthropic sign-in")
        } catch {
            addStep(.error, "Failed to start OAuth: \(error.localizedDescription)")
        }
    }

    public func showApiKeyInputForProvider() {
        apiKeyInput = ""
        state = .waitingForApiKey
    }

    public func submitApiKey() {
        guard let provider = selectedProvider else {
            addStep(.error, "No provider selected")
            state = .needsAuth
            return
        }

        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let authDir = configDir.appendingPathComponent("agents/default/agent")
            let authFile = authDir.appendingPathComponent("auth-profiles.json")

            // Build profile key based on provider
            let profileKey: String
            let providerName: String
            switch provider {
            case .anthropic:
                profileKey = "anthropic:default"
                providerName = "anthropic"
            case .openai:
                profileKey = "openai:default"
                providerName = "openai"
            case .google:
                profileKey = "google:default"
                providerName = "google"
            }

            let payload: [String: Any] = [
                "version": 1,
                "profiles": [
                    profileKey: [
                        "type": "api_key",
                        "provider": providerName,
                        "key": key
                    ]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
               let _ = try? data.write(to: authFile) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
                addStep(.done, "\(provider.displayName) API key saved")
            } else {
                addStep(.error, "Failed to save API key")
            }
        } else {
            addStep(.warning, "Skipped API key — set up later in Control UI")
        }

        selectedProvider = nil
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

    public func backToProviderSelection() {
        state = .needsAuth
        selectedProvider = nil
    }

    public func skipAuth() {
        addStep(.warning, "Skipped auth — set up later in Control UI")
        selectedProvider = nil
        state = .working
        Task {
            do { try await continueAfterSetup() }
            catch { addStep(.error, error.localizedDescription); state = .error }
        }
    }

    // Legacy method for backward compatibility
    public func startOAuth() {
        selectedProvider = .anthropic
        startOAuthForProvider()
    }

    public func showApiKeyInput() {
        selectedProvider = .anthropic
        showApiKeyInputForProvider()
    }

    /// Handle OAuth callback from custom URL scheme (openclaw://oauth/callback)
    public func handleOAuthCallback(code: String, state: String?) {
        guard let pkce = currentPKCE else {
            addStep(.error, "No PKCE session. Try signing in again.")
            state.map { _ in } // Silence unused warning
            self.state = .needsAuth
            return
        }

        // Optionally verify state matches our PKCE verifier
        if let receivedState = state, receivedState != pkce.verifier {
            addStep(.warning, "OAuth state mismatch — proceeding anyway")
        }

        print("[OpenClaw] Received OAuth callback with code: \(code.prefix(8))...")
        addStep(.running, "Processing OAuth callback...")
        self.state = .working

        Task {
            do {
                let creds = try await AnthropicOAuth.exchangeCode(code: code, verifier: pkce.verifier)
                try saveOAuthCredentials(creds)
                addStep(.done, "Signed in with Claude")
                try await continueAfterSetup()
            } catch {
                addStep(.error, "OAuth exchange failed: \(error.localizedDescription)")
                self.state = .needsAuth
            }
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
        var urlString = "http://localhost:\(port)/openclaw"
        if let token = gatewayToken {
            urlString += "?token=\(token)"
        }
        let url = URL(string: urlString)!
        NSWorkspace.shared.open(url)
        addStep(.done, "Opened Control UI in browser")
    }

    public func viewLogs() {
        guard !suppressSideEffects else {
            addStep(.done, "Opened logs in Terminal")
            return
        }
        let script = "tell application \"Terminal\" to do script \"docker logs -f \(containerName)\""
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        addStep(.done, "Opened logs in Terminal")
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
            addStep(.running, "Stopping container...")
            _ = try? await shell("docker", "stop", containerName)
            _ = try? await shell("docker", "rm", "-f", containerName)
            addStep(.done, "Container removed")

            // Remove all local state
            try? FileManager.default.removeItem(at: stateDir)
            addStep(.done, "Local config cleaned up")

            steps = []
            gatewayToken = nil
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

        // Check if docker CLI exists at all
        let which = try? await shell("which", "docker")
        let dockerCliExists = which?.exitCode == 0

        // Check if Docker.app is installed
        let dockerAppExists = FileManager.default.fileExists(atPath: "/Applications/Docker.app")

        // If neither exists, prompt user to install
        if !dockerCliExists && !dockerAppExists {
            throw LauncherError.dockerNotInstalled
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

    private func firstRunSetup() async throws {
        migrateOldStateDir()

        // Load existing token if present
        if FileManager.default.fileExists(atPath: envFile.path) {
            let content = try String(contentsOf: envFile, encoding: .utf8)
            for line in content.split(separator: "\n") {
                if line.hasPrefix("OPENCLAW_GATEWAY_TOKEN=") {
                    gatewayToken = String(line.dropFirst("OPENCLAW_GATEWAY_TOKEN=".count))
                }
            }
            addStep(.done, "Loaded existing configuration")
            return
        }

        isFirstRun = true
        addStep(.running, "First-time setup...")

        // Create directories
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)

        // Generate token
        let token = generateSecureToken()
        gatewayToken = token

        // Write .env
        let envContent = "OPENCLAW_GATEWAY_TOKEN=\(token)\nOPENCLAW_PORT=\(port)\n"
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
        let configFile = configDir.appendingPathComponent("openclaw.json")
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

        let pull = try await shell("docker", "pull", imageName)
        pullProgressText = nil

        if pull.exitCode == 0 {
            addStep(.done, "Docker image up to date")
            return
        }

        // Pull failed — check if we have a local copy to fall back on
        let inspect = try? await shell("docker", "image", "inspect", imageName)
        if inspect?.exitCode == 0 {
            addStep(.warning, "Couldn't check for updates (offline?). Using cached image.")
            return
        }

        throw LauncherError.pullFailed(pull.stderr.isEmpty ? "Image pull failed" : pull.stderr)
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

            // --- Resource limits ---
            "--memory", "2g",                           // max 2GB RAM
            "--memory-swap", "2g",                      // no swap
            "--cpus", "2.0",                            // max 2 CPU cores
            "--pids-limit", "256",                      // prevent fork bombs

            // --- Security ---
            "--cap-drop", "ALL",                        // drop ALL Linux capabilities
            "--cap-add", "NET_BIND_SERVICE",            // only allow binding ports
            "--security-opt", "no-new-privileges:true", // prevent privilege escalation

            // --- Network ---
            "-p", "127.0.0.1:\(port):18789",           // LOCALHOST ONLY — not exposed to network

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

        let url = URL(string: "http://127.0.0.1:\(port)/openclaw/")!
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
        let url = URL(string: "http://127.0.0.1:\(port)/openclaw/")!
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
