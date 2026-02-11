import SwiftUI

// MARK: - Check Status (shared)

private enum CheckStatus {
    case checking, success, failed, pending
}

/// Onboarding flow for first-time users
public struct OnboardingView: View {
    @ObservedObject var settings: LauncherSettings
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var dockerStatus: DockerCheckStatus = .checking

    public enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case dockerCheck = 1
        case complete = 2
    }

    public enum DockerCheckStatus {
        case checking
        case installed
        case notInstalled
        case notRunning
    }

    public init(settings: LauncherSettings, onComplete: @escaping () -> Void) {
        self.settings = settings
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Ocean.accent : Ocean.textDim.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStep(onContinue: {
                        withAnimation { currentStep = .dockerCheck }
                        checkDocker()
                    })
                case .dockerCheck:
                    DockerCheckStep(
                        status: dockerStatus,
                        onBack: { withAnimation { currentStep = .welcome } },
                        onContinue: { withAnimation { currentStep = .complete } },
                        onRetry: { checkDocker() },
                        onDownload: { openDockerDownload() },
                        onOpenDocker: { openDockerApp() }
                    )
                case .complete:
                    CompleteStep(
                        onBack: { withAnimation { currentStep = .dockerCheck } },
                        onLaunch: { completeOnboarding() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer()
        }
        .frame(width: 500, height: 400)
        .background(Ocean.bg)
    }

    private func checkDocker() {
        dockerStatus = .checking

        Task {
            // Direct filesystem check — no PATH dependency
            let dockerBinary = DockerPaths.findDockerBinary()
            let dockerApp = DockerPaths.findInstalledApp()

            guard dockerBinary != nil || dockerApp != nil else {
                await MainActor.run { dockerStatus = .notInstalled }
                return
            }

            // Check if Docker daemon is running
            let infoResult = await runCommand("docker info")
            await MainActor.run {
                dockerStatus = infoResult.exitCode == 0 ? .installed : .notRunning
            }
        }
    }

    private func runCommand(_ command: String) async -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = DockerPaths.augmentedEnvironment()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func openDockerDownload() {
        if let url = URL(string: "https://www.docker.com/products/docker-desktop/") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openDockerApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
    }

    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        settings.save()
        onComplete()
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            ZStack {
                // Glow effect
                Circle()
                    .fill(Ocean.accent.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)

                Text("🐙")
                    .font(.system(size: 64))
                    .frame(width: 100, height: 100)
                    .background(Ocean.logoGradient)
                    .cornerRadius(24)
            }

            VStack(spacing: 12) {
                Text("Welcome to OpenClaw")
                    .font(Ocean.ui(24, weight: .bold))
                    .foregroundColor(Ocean.text)

                Text("Run AI agents in a secure, isolated Docker environment.\nNo terminal required.")
                    .font(Ocean.ui(14))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            OceanButton("Get Started", icon: "→", variant: .primary) {
                onContinue()
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Docker Check Step

private struct DockerCheckStep: View {
    let status: OnboardingView.DockerCheckStatus
    let onBack: () -> Void
    let onContinue: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onOpenDocker: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Docker icon
            Text("🐳")
                .font(.system(size: 48))
                .frame(width: 80, height: 80)
                .background(dockerIconBackground)
                .cornerRadius(20)

            VStack(spacing: 12) {
                Text(titleText)
                    .font(Ocean.ui(20, weight: .semibold))
                    .foregroundColor(titleColor)

                Text(subtitleText)
                    .font(Ocean.ui(13))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
            }

            // Status checklist
            VStack(alignment: .leading, spacing: 12) {
                ChecklistItem(
                    label: "Docker Desktop installed",
                    status: checklistStatus(for: .installed)
                )
                ChecklistItem(
                    label: "Docker daemon running",
                    status: checklistStatus(for: .running)
                )
            }
            .padding(16)
            .background(Ocean.surface)
            .cornerRadius(Ocean.cardRadius)

            Spacer()

            // Actions
            HStack(spacing: 12) {
                OceanButton("Back", variant: .secondary) {
                    onBack()
                }

                switch status {
                case .checking:
                    OceanButton("Checking...", variant: .primary) {}
                        .disabled(true)
                case .installed:
                    OceanButton("Continue", icon: "→", variant: .primary) {
                        onContinue()
                    }
                case .notInstalled:
                    HStack(spacing: 8) {
                        OceanButton("Download Docker", icon: "⬇", variant: .primary) {
                            onDownload()
                        }
                        OceanButton("Check Again", icon: "↻", variant: .secondary) {
                            onRetry()
                        }
                    }
                case .notRunning:
                    HStack(spacing: 8) {
                        OceanButton("Open Docker", variant: .primary) {
                            onOpenDocker()
                        }
                        OceanButton("Check Again", icon: "↻", variant: .secondary) {
                            onRetry()
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
    }

    private var dockerIconBackground: Color {
        switch status {
        case .checking: return Ocean.info.opacity(0.2)
        case .installed: return Ocean.success.opacity(0.2)
        case .notInstalled, .notRunning: return Ocean.warning.opacity(0.2)
        }
    }

    private var titleText: String {
        switch status {
        case .checking: return "Checking Docker..."
        case .installed: return "Docker Ready!"
        case .notInstalled: return "Docker Not Found"
        case .notRunning: return "Docker Not Running"
        }
    }

    private var titleColor: Color {
        switch status {
        case .checking: return Ocean.text
        case .installed: return Ocean.success
        case .notInstalled, .notRunning: return Ocean.warning
        }
    }

    private var subtitleText: String {
        switch status {
        case .checking: return "Verifying Docker installation..."
        case .installed: return "Docker Desktop is installed and running."
        case .notInstalled: return "Docker Desktop is required to run OpenClaw.\nPlease download and install it."
        case .notRunning: return "Docker Desktop is installed but not running.\nPlease start it and try again."
        }
    }

    private func checklistStatus(for item: ChecklistItem.ItemType) -> CheckStatus {
        switch status {
        case .checking:
            return .checking
        case .installed:
            return .success
        case .notInstalled:
            return item == .installed ? .failed : .pending
        case .notRunning:
            return item == .installed ? .success : .failed
        }
    }
}

private struct ChecklistItem: View {
    enum ItemType {
        case installed, running
    }

    let label: String
    let status: CheckStatus

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch status {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 18, height: 18)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Ocean.success)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Ocean.error)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundColor(Ocean.textDim.opacity(0.5))
                }
            }
            .font(.system(size: 16))

            Text(label)
                .font(Ocean.ui(13))
                .foregroundColor(status == .pending ? Ocean.textDim : Ocean.text)
        }
    }
}

// MARK: - Complete Step

private struct CompleteStep: View {
    let onBack: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(Ocean.success.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .blur(radius: 15)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Ocean.success)
            }

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(Ocean.ui(24, weight: .bold))
                    .foregroundColor(Ocean.text)

                Text("OpenClaw is ready to launch your first\nisolated AI environment.")
                    .font(Ocean.ui(14))
                    .foregroundColor(Ocean.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Keyboard hint
            HStack(spacing: 6) {
                Text("Tip: Press")
                    .font(Ocean.ui(12))
                    .foregroundColor(Ocean.textDim)
                KeyboardKey("⌘")
                Text("+")
                    .font(Ocean.ui(12))
                    .foregroundColor(Ocean.textDim)
                KeyboardKey("L")
                Text("to launch anytime")
                    .font(Ocean.ui(12))
                    .foregroundColor(Ocean.textDim)
            }
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 12) {
                OceanButton("Back", variant: .secondary) {
                    onBack()
                }

                OceanButton("Launch Environment", icon: "▶", variant: .primary) {
                    onLaunch()
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
    }
}

private struct KeyboardKey: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(Ocean.mono(11, weight: .medium))
            .foregroundColor(Ocean.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Ocean.surface)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Ocean.border, lineWidth: 1)
            )
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(settings: LauncherSettings(), onComplete: {})
    }
}
#endif
