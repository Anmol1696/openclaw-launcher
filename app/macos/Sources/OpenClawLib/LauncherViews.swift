import SwiftUI

// MARK: - Main View

public struct LauncherView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("🐙")
                    .font(.system(size: 48))
                Text("OpenClawLauncher")
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
                } else if launcher.state == .needsAuth {
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
                } else if launcher.state == .waitingForOAuthCode {
                    VStack(spacing: 12) {
                        if launcher.showApiKeyField {
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
                        } else {
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
                } else if launcher.state == .stopped {
                    Button("Start OpenClawLauncher") {
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
    }
}
