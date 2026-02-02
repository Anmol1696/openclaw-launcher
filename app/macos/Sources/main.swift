// ============================================================================
//  OpenClaw Launcher — Native macOS App (SwiftUI)
//  UI Improvements: Dashboard, Progress Bar, Dark Mode, Menu Bar
//
//  Build: swift build
// ============================================================================

import SwiftUI
import Foundation
import CryptoKit

// MARK: - Anthropic OAuth (PKCE)

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AnthropicOAuth {
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"

    struct PKCE {
        let verifier: String
        let challenge: String
    }

    static func generatePKCE() throws -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let verifier = Data(bytes).base64URLEncodedString()
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }

    static func buildAuthorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier),
        ]
        return components.url!
    }

    static func exchangeCode(code: String, verifier: String) async throws -> OAuthCredentials {
        let payload: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "state": verifier,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<error>"
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[OpenClaw] Token exchange failed (HTTP \(status)): \(text)")
            throw NSError(domain: "AnthropicOAuth", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(text)"])
        }

        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = decoded?["access_token"] as? String,
              let refresh = decoded?["refresh_token"] as? String,
              let expiresIn = decoded?["expires_in"] as? Double else {
            throw NSError(domain: "AnthropicOAuth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected token response"])
        }

        let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn * 1000) - Int64(5 * 60 * 1000)
        return OAuthCredentials(type: "oauth", refresh: refresh, access: access, expires: expiresAtMs)
    }
}

struct OAuthCredentials {
    let type: String
    let refresh: String
    let access: String
    let expires: Int64
}

// MARK: - Gateway Status

struct GatewayStatus: Codable {
    let uptime: Int?
}

// MARK: - App Entry Point

@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()

    var body: some Scene {
        WindowGroup {
            LauncherView(launcher: launcher)
                .frame(width: 520, height: launcher.state == .running ? 580 : 520)
                .animation(.easeInOut(duration: 0.25), value: launcher.state)
                .onAppear { launcher.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        // Menu Bar Extra (macOS 13+)
        MenuBarExtra {
            MenuBarContent(launcher: launcher)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(launcher.menuBarStatus == .running ? .green : 
                               launcher.menuBarStatus == .starting ? .yellow : .red)
        }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContent: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        Button("Open Control UI") {
            launcher.openBrowser()
        }
        .disabled(launcher.state != .running)
        
        Divider()
        
        Button("Restart") {
            Task {
                await launcher.restartContainer()
            }
        }
        .disabled(launcher.state != .running)
        
        Button("Stop") {
            launcher.stopContainer()
        }
        .disabled(launcher.state != .running)
        
        Divider()
        
        Button("View Logs") {
            launcher.viewLogs()
        }
        
        Button("Show Window") {
            NSApp.activate(ignoringOtherApps: true)
            // Find the launcher window (skip menu bar extra windows)
            let window = NSApp.windows.first { $0.contentView != nil && $0.title != "" }
                ?? NSApp.windows.first
            window?.makeKeyAndOrderFront(nil)
        }
        
        Divider()
        
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Main View

struct LauncherView: View {
    @ObservedObject var launcher: OpenClawLauncher

    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                        Text("🐙")
                            .font(.system(size: 42))
                    }
                    Text("OpenClaw Launcher")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Isolated AI Agent • Docker Powered")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            // Content area
            if launcher.state == .running {
                DashboardView(launcher: launcher)
            } else {
                SetupView(launcher: launcher)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Dashboard View (After Launch)

struct DashboardView: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Container Status Card
                StatusCard(
                    title: "Container Status",
                    icon: "server.rack",
                    iconColor: launcher.gatewayHealthy ? .green : .orange
                ) {
                    HStack {
                        Circle()
                            .fill(launcher.gatewayHealthy ? Color.green : Color.orange)
                            .frame(width: 12, height: 12)
                        Text(launcher.gatewayHealthy ? "Running" : "Starting")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(launcher.uptimeString)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Tip card
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Configure channels, agents, and settings in the Control UI.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Quick Actions
                VStack(spacing: 12) {
                    Button(action: { launcher.openBrowser() }) {
                        HStack {
                            Image(systemName: "arrow.up.forward.app")
                            Text("Open Control UI")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    HStack(spacing: 12) {
                        Button(action: { launcher.viewLogs() }) {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("View Logs")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { 
                            Task { await launcher.restartContainer() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { launcher.stopContainer() }) {
                            HStack {
                                Image(systemName: "stop.circle")
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                
                // Token (collapsed)
                if let token = launcher.gatewayToken {
                    DisclosureGroup("Gateway Token") {
                        HStack {
                            Text(token.prefix(24) + "...")
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

struct StatusCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Setup View (During Launch)

struct SetupView: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if launcher.state == .working {
                        // Progress bar + current step
                        VStack(alignment: .leading, spacing: 12) {
                            if let current = launcher.currentStep {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text(current.message)
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                            
                            ProgressView(value: launcher.progress)
                                .progressViewStyle(.linear)
                        }
                        .padding(16)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                        
                        // Completed summary
                        if launcher.completedStepsCount > 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(launcher.completedStepsCount) steps completed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        // Show all steps for non-working states
                        ForEach(launcher.steps) { step in
                            StepRow(step: step)
                        }
                    }
                    
                    // Show errors prominently
                    ForEach(launcher.errorSteps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom actions
            VStack(spacing: 12) {
                if launcher.state == .needsAuth {
                    AuthChoiceView(launcher: launcher)
                } else if launcher.state == .waitingForOAuthCode {
                    if launcher.showApiKeyField {
                        ApiKeyInputView(launcher: launcher)
                    } else {
                        OAuthCodeInputView(launcher: launcher)
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
                    .controlSize(.large)
                } else if launcher.state == .working {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Setting up...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

struct AuthChoiceView: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Authentication")
                .font(.system(size: 14, weight: .semibold))
            Text("Choose how to connect to Anthropic.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button("Sign in with Claude") {
                    launcher.startOAuth()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Use API Key") {
                    launcher.showApiKeyInput()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Skip") {
                    launcher.skipAuth()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            }
        }
    }
}

struct ApiKeyInputView: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        VStack(spacing: 12) {
            Text("API Key Setup")
                .font(.system(size: 14, weight: .semibold))
            Text("Enter your Anthropic API key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            SecureField("sk-ant-...", text: $launcher.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button("Continue") { launcher.submitApiKey() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Back") { launcher.state = .needsAuth }
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }
}

struct OAuthCodeInputView: View {
    @ObservedObject var launcher: OpenClawLauncher
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Paste Authorization Code")
                .font(.system(size: 14, weight: .semibold))
            Text("Sign in on the browser page that opened,\nthen copy the code and paste it below.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Paste code or URL here...", text: $launcher.oauthCodeInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button("Exchange") { launcher.exchangeOAuthCode() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(launcher.oauthCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Back") { launcher.state = .needsAuth }
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
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
        .padding(.vertical, 4)
    }
}

// MARK: - Data Models

enum StepStatus { case pending, running, done, error, warning }

enum LauncherState { case idle, working, needsAuth, waitingForOAuthCode, running, stopped, error }

enum MenuBarStatus { case starting, running, stopped }

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
    @Published var apiKeyInput: String = ""
    @Published var oauthCodeInput: String = ""
    @Published var showApiKeyField: Bool = false
    @Published var gatewayHealthy: Bool = false
    @Published var gatewayStatusData: GatewayStatus?
    @Published var menuBarStatus: MenuBarStatus = .stopped
    @Published var containerStartTime: Date?
    @Published var uptimeTick: UInt = 0  // Incremented every second to drive uptime display
    
    private var isFirstRun = false
    private var currentPKCE: AnthropicOAuth.PKCE?
    private var healthCheckTimer: Timer?
    private var uptimeTimer: Timer?

    private let containerName = "openclaw"
    private let imageName = "ghcr.io/openclaw/openclaw:latest"
    private let port: Int = 18789
    private var hasStarted = false

    private var stateDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-docker")
    }
    private var configDir: URL { stateDir.appendingPathComponent("config") }
    private var workspaceDir: URL { stateDir.appendingPathComponent("workspace") }
    private var envFile: URL { stateDir.appendingPathComponent(".env") }

    deinit {
        healthCheckTimer?.invalidate()
        uptimeTimer?.invalidate()
    }
    
    // MARK: - Computed Properties for UI
    
    var currentStep: LaunchStep? {
        steps.last(where: { $0.status == .running })
    }
    
    var completedStepsCount: Int {
        steps.filter { $0.status == .done }.count
    }
    
    var errorSteps: [LaunchStep] {
        steps.filter { $0.status == .error }
    }
    
    /// Total logical launch steps: Docker check, first-run setup, auth, image pull, container start, gateway wait.
    /// Update if the launch pipeline adds or removes steps.
    private let totalLaunchSteps: Double = 8.0
    
    var progress: Double {
        return min(Double(completedStepsCount) / totalLaunchSteps, 1.0)
    }
    
    var uptimeString: String {
        _ = uptimeTick  // Subscribe to tick updates
        guard let start = containerStartTime else { return "00:00:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Public

    func start() {
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

    func stopContainer() {
        Task {
            addStep(.running, "Stopping OpenClaw...")
            _ = try? await shell("docker", "stop", containerName)
            addStep(.done, "Stopped.")
            state = .stopped
            menuBarStatus = .stopped
            stopHealthCheck()
        }
    }
    
    func restartContainer() async {
        addStep(.running, "Restarting...")
        menuBarStatus = .starting
        gatewayHealthy = false
        _ = try? await shell("docker", "restart", containerName)
        addStep(.done, "Restarted")
        containerStartTime = Date()
        menuBarStatus = .running
        startHealthCheck()
    }

    func submitApiKey() {
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

    func startOAuth() {
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

    func showApiKeyInput() {
        showApiKeyField = true
        apiKeyInput = ""
        state = .waitingForOAuthCode
    }

    func skipAuth() {
        addStep(.warning, "Skipped auth — set up later in Control UI")
        state = .working
        Task {
            do { try await continueAfterSetup() }
            catch { addStep(.error, error.localizedDescription); state = .error }
        }
    }

    func exchangeOAuthCode() {
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

    func openBrowser() {
        var urlString = "http://localhost:\(port)/openclaw"
        if let token = gatewayToken {
            urlString += "?token=\(token)"
        }
        let url = URL(string: urlString)!
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
    
    // MARK: - Health Check
    
    private func startHealthCheck() {
        stopHealthCheck()
        
        // Start uptime timer on main run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.uptimeTick += 1
                }
            }
        }
        
        // Start health check timer on main run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task {
                    await self?.checkGatewayHealth()
                }
            }
        }
        
        // Initial check
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
            // Fallback to simple health check
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

        isFirstRun = true
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
      "allowInsecureAuth": true,
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

struct ShellResult {
    let exitCode: Int
    let stdout: String
    let stderr: String
}

enum LauncherError: LocalizedError {
    case dockerNotRunning
    case dockerInstallFailed(String)
    case pullFailed(String)
    case runFailed(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .dockerNotRunning:
            return "Docker Desktop is not running. Please start it and try again."
        case .dockerInstallFailed(let msg):
            return "Failed to install Docker Desktop: \(msg)"
        case .pullFailed(let msg):
            return "Failed to pull Docker image: \(msg.prefix(200))"
        case .runFailed(let msg):
            return "Failed to start container: \(msg.prefix(200))"
        case .noToken:
            return "Gateway token not generated. Try resetting: rm -rf ~/.openclaw-docker"
        }
    }
}
