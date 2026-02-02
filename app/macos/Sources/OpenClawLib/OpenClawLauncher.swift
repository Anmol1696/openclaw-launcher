import SwiftUI
import Foundation

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

    private var isFirstRun = false
    private var currentPKCE: AnthropicOAuth.PKCE?
    private var healthCheckTimer: Timer?
    private var uptimeTimer: Timer?

    private let containerName = "openclaw"
    private let imageName = "ghcr.io/anmol1696/openclaw-launcher:base"
    private let port: Int = 18789
    private var hasStarted = false

    private var stateDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-launcher")
    }
    private var configDir: URL { stateDir.appendingPathComponent("config") }
    private var workspaceDir: URL { stateDir.appendingPathComponent("workspace") }
    private var envFile: URL { stateDir.appendingPathComponent(".env") }

    public init() {}

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
        guard !hasStarted || state == .stopped || state == .error else { return }
        hasStarted = true
        steps = []
        state = .working
        menuBarStatus = .starting

        Task {
            do {
                try await checkDocker()
                try await firstRunSetup()

                // Pause for auth on first run
                if isFirstRun && !authProfileExists() && !oauthCredentialsExist() {
                    state = .needsAuth
                    return
                }

                try await continueAfterSetup()
            } catch {
                addStep(.error, error.localizedDescription)
                state = .error
                menuBarStatus = .stopped
            }
        }
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

    public func submitApiKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let authDir = configDir.appendingPathComponent("agents/default/agent")
            let authFile = authDir.appendingPathComponent("auth-profiles.json")
            let json = """
            {
              "version": 1,
              "profiles": {
                "anthropic:default": {
                  "type": "api_key",
                  "provider": "anthropic",
                  "key": "\(key)"
                }
              }
            }
            """
            try? json.write(to: authFile, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
            addStep(.done, "API key saved")
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
        var urlString = "http://localhost:\(port)/openclaw"
        if let token = gatewayToken {
            urlString += "?token=\(token)"
        }
        let url = URL(string: urlString)!
        NSWorkspace.shared.open(url)
        addStep(.done, "Opened Control UI in browser")
    }

    public func viewLogs() {
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

        // If neither exists, download and install Docker Desktop
        if !dockerCliExists && !dockerAppExists {
            try await installDocker()
        }

        let result = try? await shell("docker", "info")
        if result == nil || result!.exitCode != 0 {
            // Try to start Docker Desktop
            addStep(.warning, "Docker not running. Starting Docker Desktop...")
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))

            // Wait up to 90 seconds
            for _ in 0..<45 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
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

    private func installDocker() async throws {
        addStep(.running, "Docker Desktop not found. Downloading...")

        // Detect architecture
        let arch = try await shell("uname", "-m")
        let archString = arch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let dmgURL: URL
        if archString == "arm64" {
            dmgURL = URL(string: "https://desktop.docker.com/mac/main/arm64/Docker.dmg")!
        } else {
            dmgURL = URL(string: "https://desktop.docker.com/mac/main/amd64/Docker.dmg")!
        }

        // Download DMG to temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let dmgPath = tempDir.appendingPathComponent("Docker.dmg")

        // Clean up any previous download
        try? FileManager.default.removeItem(at: dmgPath)

        addStep(.running, "Downloading Docker Desktop (\(archString))... This may take a few minutes.")

        let (downloadedURL, _) = try await URLSession.shared.download(from: dmgURL)
        try FileManager.default.moveItem(at: downloadedURL, to: dmgPath)

        addStep(.done, "Download complete")
        addStep(.running, "Installing Docker Desktop...")

        // Mount DMG
        let mount = try await shell("hdiutil", "attach", "-nobrowse", "-quiet", dmgPath.path)
        if mount.exitCode != 0 {
            throw LauncherError.dockerInstallFailed("Failed to mount DMG: \(mount.stderr.prefix(200))")
        }

        // Find the mounted volume
        let volumePath = "/Volumes/Docker"
        let sourceApp = "\(volumePath)/Docker.app"

        guard FileManager.default.fileExists(atPath: sourceApp) else {
            _ = try? await shell("hdiutil", "detach", volumePath, "-quiet")
            throw LauncherError.dockerInstallFailed("Docker.app not found in mounted DMG")
        }

        // Copy to /Applications — try direct copy first
        let copy = try await shell("/bin/cp", "-R", sourceApp, "/Applications/Docker.app")
        if copy.exitCode != 0 {
            // Need admin privileges — use osascript to prompt
            addStep(.warning, "Requesting administrator permission to install...")
            let adminCopy = try await shell(
                "osascript", "-e",
                "do shell script \"cp -R '\(sourceApp)' '/Applications/Docker.app'\" with administrator privileges"
            )
            if adminCopy.exitCode != 0 {
                _ = try? await shell("hdiutil", "detach", volumePath, "-quiet")
                throw LauncherError.dockerInstallFailed("Installation cancelled or failed: \(adminCopy.stderr.prefix(200))")
            }
        }

        // Detach DMG and clean up
        _ = try? await shell("hdiutil", "detach", volumePath, "-quiet")
        try? FileManager.default.removeItem(at: dmgPath)

        addStep(.done, "Docker Desktop installed")
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
        addStep(.running, "Checking for image updates...")

        let pull = try await shell("docker", "pull", imageName)
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

        throw LauncherError.pullFailed(pull.stderr)
    }

    private func runContainer() async throws {
        guard gatewayToken != nil else {
            throw LauncherError.noToken
        }

        // Check if already running
        let ps = try? await shell("docker", "ps", "--filter", "name=^\(containerName)$", "--format", "{{.Names}}")
        if let output = ps?.stdout, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addStep(.done, "Container already running")
            return
        }

        // Remove stopped container if exists
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

        if result.exitCode != 0 {
            throw LauncherError.runFailed(result.stderr)
        }

        addStep(.done, "Container started (locked down)")
    }

    private func waitForGateway() async throws {
        addStep(.running, "Waiting for Gateway to be ready...")

        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let check = try? await shell("curl", "-sf", "http://localhost:\(port)/openclaw/")
            if check?.exitCode == 0 {
                addStep(.done, "Gateway is ready!")
                return
            }
        }

        // Not fatal — might just be slow
        addStep(.warning, "Gateway is still starting. Try opening the browser anyway.")
    }

    // MARK: - Health Check

    private func startHealthCheck() {
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
        do {
            let url = URL(string: "http://localhost:\(port)/openclaw/api/status")!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run {
                    gatewayHealthy = false
                }
                return
            }

            let status = try JSONDecoder().decode(GatewayStatus.self, from: data)
            await MainActor.run {
                gatewayHealthy = true
                gatewayStatusData = status
            }
        } catch {
            let check = try? await shell("curl", "-sf", "http://localhost:\(port)/openclaw/")
            let healthy = check?.exitCode == 0
            await MainActor.run {
                gatewayHealthy = healthy
                if !healthy {
                    gatewayStatusData = nil
                }
            }
        }
    }

    // MARK: - Shell Helper

    private func shell(_ args: String...) async throws -> ShellResult {
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

        // Read pipes concurrently to avoid deadlock when output exceeds buffer
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
