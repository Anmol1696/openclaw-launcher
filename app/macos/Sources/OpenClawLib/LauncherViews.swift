import SwiftUI

// MARK: - Menu Bar Content

public struct MenuBarContent: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
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

public struct LauncherView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
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

public struct DashboardView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
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
                    Text("Chat with your agent and manage settings in the Control UI.")
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

public struct StatusCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    public init(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    public var body: some View {
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
                        ForEach(launcher.steps) { step in
                            StepRow(step: step)
                        }
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

public struct StepRow: View {
    let step: LaunchStep

    public init(step: LaunchStep) {
        self.step = step
    }

    public var body: some View {
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
