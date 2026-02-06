import SwiftUI

// MARK: - Auth Choice View

/// Ocean-themed authentication choice view
public struct OceanAuthChoiceView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Ocean.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .blur(radius: 10)

                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Ocean.accent)
            }

            VStack(spacing: 8) {
                Text("Authentication Required")
                    .font(Ocean.ui(18, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Text("Connect to Anthropic to power your AI agents.")
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                OceanButton("Sign in with Claude", icon: "→", variant: .primary) {
                    launcher.startOAuth()
                }

                OceanButton("Use API Key", variant: .secondary) {
                    launcher.showApiKeyInput()
                }

                Button("Skip for now") {
                    launcher.skipAuth()
                }
                .buttonStyle(.plain)
                .font(Ocean.ui(12))
                .foregroundColor(Ocean.textDim)
                .padding(.top, 4)
            }
        }
        .padding(32)
    }
}

// MARK: - OAuth Code Input View

/// Ocean-themed OAuth code input view
public struct OceanOAuthCodeInputView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Ocean.info.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .blur(radius: 10)

                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Ocean.info)
            }

            VStack(spacing: 8) {
                Text("Paste Authorization Code")
                    .font(Ocean.ui(18, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Text("Sign in on the browser page that opened,\nthen copy the code and paste it below.")
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                TextField("Paste code or URL here...", text: $launcher.oauthCodeInput)
                    .textFieldStyle(.plain)
                    .font(Ocean.mono(12))
                    .padding(12)
                    .background(Ocean.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Ocean.border, lineWidth: 1)
                    )
                    .frame(maxWidth: 320)

                HStack(spacing: 12) {
                    OceanButton("Back", variant: .secondary) {
                        launcher.state = .needsAuth
                    }

                    OceanButton("Continue", icon: "→", variant: .primary) {
                        launcher.exchangeOAuthCode()
                    }
                    .disabled(launcher.oauthCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(32)
    }
}

// MARK: - API Key Input View

/// Ocean-themed API key input view
public struct OceanApiKeyInputView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Ocean.warning.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .blur(radius: 10)

                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Ocean.warning)
            }

            VStack(spacing: 8) {
                Text("Enter API Key")
                    .font(Ocean.ui(18, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Text("Enter your Anthropic API key to connect.")
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                SecureField("sk-ant-...", text: $launcher.apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(Ocean.mono(12))
                    .padding(12)
                    .background(Ocean.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Ocean.border, lineWidth: 1)
                    )
                    .frame(maxWidth: 320)

                HStack(spacing: 12) {
                    OceanButton("Back", variant: .secondary) {
                        launcher.state = .needsAuth
                    }

                    OceanButton("Continue", icon: "→", variant: .primary) {
                        launcher.submitApiKey()
                    }
                    .disabled(launcher.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(32)
    }
}

// MARK: - Preview

#if DEBUG
struct AuthViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            OceanAuthChoiceView(launcher: OpenClawLauncher())
        }
        .frame(width: 400, height: 400)
        .background(Ocean.bg)
    }
}
#endif
