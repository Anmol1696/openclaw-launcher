// ============================================================================
//  OpenClaw Launcher — Native macOS App (SwiftUI)
//
//  Zero terminal. User double-clicks → sees a small native window →
//  Docker runs in background → browser opens with Control UI.
//
//  Build: swiftc -o OpenClawLauncher main.swift (or use Xcode)
//  Or use the Package.swift to build via `swift build`
// ============================================================================

import SwiftUI
import Foundation

// MARK: - App Entry Point

@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()

    var body: some Scene {
        WindowGroup {
            LauncherView(launcher: launcher)
                .frame(width: 480, height: 520)
                .onAppear { launcher.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - Main View

struct LauncherView: View {
    @ObservedObject var launcher: OpenClawLauncher

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("🐙")
                    .font(.system(size: 48))
                Text("OpenClaw")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Isolated AI Agent • Docker Powered")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Status steps
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(launcher.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom actions
            VStack(spacing: 12) {
                if launcher.state == .running {
                    // Token display
                    if let token = launcher.gatewayToken {
                        HStack {
                            Text("Token:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(token.prefix(16) + "...")
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                                launcher.addStep(.done, "Token copied to clipboard")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Open Control UI") {
                            launcher.openBrowser()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Stop") {
                            launcher.stopContainer()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                } else if launcher.state == .stopped {
                    Button("Start OpenClaw") {
                        launcher.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if launcher.state == .error {
                    HStack(spacing: 12) {
                        Button("Retry") {
                            launcher.start()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("View Logs") {
                            launcher.viewLogs()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Setting up...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct StepRow: View {
    let step: LaunchStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch step.status {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                case .running:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .error:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 18)

            Text(step.message)
                .font(.system(size: 13))
                .foregroundStyle(step.status == .error ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Data Models

enum StepStatus { case pending, running, done, error, warning }

enum LauncherState { case idle, working, running, stopped, error }

struct LaunchStep: Identifiable {
    let id = UUID()
    let status: StepStatus
    let message: String
}

// MARK: - Launcher Logic

@MainActor
class OpenClawLauncher: ObservableObject {
    @Published var steps: [LaunchStep] = []
    @Published var state: LauncherState = .idle
    @Published var gatewayToken: String?

    private let containerName = "openclaw"
    private let imageName = "ghcr.io/anmol1696/openclaw:latest"
    private let port: Int = 18789
    private var hasStarted = false

    private var stateDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-docker")
    }
    private var configDir: URL { stateDir.appendingPathComponent("config") }
    private var workspaceDir: URL { stateDir.appendingPathComponent("workspace") }
    private var envFile: URL { stateDir.appendingPathComponent(".env") }

    // MARK: - Public

    func start() {
        guard !hasStarted || state == .stopped || state == .error else { return }
        hasStarted = true
        steps = []
        state = .working

        Task {
            do {
                try await checkDocker()
                try await firstRunSetup()
                try await ensureImage()
                try await runContainer()
                try await waitForGateway()

                state = .running
                openBrowser()
            } catch {
                addStep(.error, error.localizedDescription)
                state = .error
            }
        }
    }

    func stopContainer() {
        Task {
            addStep(.running, "Stopping OpenClaw...")
            _ = try? await shell("docker", "stop", containerName)
            addStep(.done, "Stopped.")
            state = .stopped
        }
    }

    func openBrowser() {
        let url = URL(string: "http://localhost:\(port)")!
        NSWorkspace.shared.open(url)
        addStep(.done, "Opened Control UI in browser")
    }

    func viewLogs() {
        let script = "tell application \"Terminal\" to do script \"docker logs -f \(containerName)\""
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        addStep(.done, "Opened logs in Terminal")
    }

    func addStep(_ status: StepStatus, _ message: String) {
        steps.append(LaunchStep(status: status, message: message))
        if steps.count > 50 {
            steps.removeFirst(steps.count - 50)
        }
    }

    // MARK: - Steps

    private func checkDocker() async throws {
        addStep(.running, "Checking Docker...")

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

    private func firstRunSetup() async throws {
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

        addStep(.running, "First-time setup...")

        // Create directories
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)

        // Generate token
        let token = generateSecureToken()
        gatewayToken = token

        // Write .env
        let env = "OPENCLAW_GATEWAY_TOKEN=\(token)\nOPENCLAW_PORT=\(port)\n"
        try env.write(to: envFile, atomically: true, encoding: .utf8)

        // Write minimal config
        let config = """
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": { "mode": "token" },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true }
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace"
    }
  }
}
"""
        let configFile = configDir.appendingPathComponent("openclaw.json")
        try config.write(to: configFile, atomically: true, encoding: .utf8)

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
        guard let token = gatewayToken else {
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
            "-e", "OPENCLAW_GATEWAY_TOKEN=\(token)",
            "-e", "NODE_ENV=production",

            // --- Restart policy ---
            "--restart", "unless-stopped",

            // --- Image ---
            imageName
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
            let check = try? await shell("curl", "-sf", "http://localhost:\(port)/")
            if check?.exitCode == 0 {
                addStep(.done, "Gateway is ready!")
                return
            }
        }

        // Not fatal — might just be slow
        addStep(.warning, "Gateway is still starting. Try opening the browser anyway.")
    }

    // MARK: - Helpers

    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func shell(_ args: String...) async throws -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment

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

struct ShellResult {
    let exitCode: Int
    let stdout: String
    let stderr: String
}

enum LauncherError: LocalizedError {
    case dockerNotRunning
    case pullFailed(String)
    case runFailed(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .dockerNotRunning:
            return "Docker Desktop is not running. Please start it and try again."
        case .pullFailed(let msg):
            return "Failed to pull Docker image: \(msg.prefix(200))"
        case .runFailed(let msg):
            return "Failed to start container: \(msg.prefix(200))"
        case .noToken:
            return "Gateway token not generated. Try resetting: rm -rf ~/.openclaw-docker"
        }
    }
}
