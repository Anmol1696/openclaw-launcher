import SwiftUI

/// New launcher view with Ocean theme - Horizontal layout like Docker Desktop
public struct NewLauncherView: View {
    @ObservedObject var launcher: OpenClawLauncher
    @ObservedObject var settings: LauncherSettings
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false
    @State private var selectedNavItem: NavItem = .status

    public init(launcher: OpenClawLauncher, settings: LauncherSettings? = nil) {
        self.launcher = launcher
        self.settings = settings ?? LauncherSettings()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main content: Sidebar + Content
            HStack(spacing: 0) {
                // Left Sidebar
                SidebarView(
                    status: pulseStatus,
                    statusText: sidebarStatusText,
                    selectedNavItem: $selectedNavItem,
                    isRunning: launcher.state == .running,
                    onOpenBrowser: { launcher.openBrowser() },
                    onViewLogs: { launcher.viewLogs() },
                    onReAuthenticate: { launcher.reAuthenticate() }
                )
                .frame(width: 160)

                // Divider between sidebar and content
                Rectangle()
                    .fill(Ocean.border)
                    .frame(width: 1)

                // Main Content Area
                MainContentView(
                    launcher: launcher,
                    settings: settings,
                    stepInfos: stepInfos,
                    progress: progress,
                    progressLeftText: progressLeftText,
                    progressRightText: progressRightText,
                    pulseStatus: pulseStatus,
                    statusText: statusText,
                    badgeStyle: badgeStyle,
                    errorType: errorType,
                    errorSecondaryAction: errorSecondaryAction,
                    errorTertiaryAction: errorTertiaryAction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Footer spanning full width
            FooterBar(
                cpuText: nil,
                memoryText: nil,
                buttons: footerButtons,
                onSettings: { showSettings = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ocean.bg)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                settings: settings,
                onReAuthenticate: {
                    showSettings = false
                    launcher.reAuthenticate()
                },
                onResetAll: {
                    showSettings = false
                    launcher.resetEverything()
                }
            )
        }
        .sheet(isPresented: $launcher.showLogSheet) {
            LogViewerView(launcher: launcher)
        }
    }

    // MARK: - Navigation Item

    enum NavItem: String, CaseIterable {
        case status = "Status"
        case logs = "Logs"
    }

    // MARK: - Error State Properties

    private var errorType: ErrorStateView.ErrorType {
        guard let error = launcher.lastError else {
            if let errorStep = launcher.steps.first(where: { $0.status == .error }) {
                return .generic(message: errorStep.message)
            }
            return .generic(message: "An unexpected error occurred.")
        }

        switch error {
        case .dockerNotInstalled:
            return .dockerNotInstalled
        case .dockerNotRunning:
            return .dockerNotRunning
        case .pullFailed(let details):
            return .pullFailed(details: details)
        case .runFailed(let details):
            if details.lowercased().contains("port") || details.lowercased().contains("bind") {
                let suggestedPort = launcher.findAvailablePort()
                return .portConflict(port: launcher.activePort, suggestedPort: suggestedPort)
            }
            return .containerCrashed(exitCode: nil)
        case .noToken:
            return .generic(message: "Gateway token not generated. Try resetting the app.")
        }
    }

    private var errorSecondaryAction: (() -> Void)? {
        switch errorType {
        case .dockerNotInstalled, .dockerNotRunning:
            return { self.launcher.openDockerApp() }
        case .pullFailed:
            return { self.launcher.state = .idle }
        case .portConflict:
            return nil
        case .containerCrashed:
            return { self.launcher.viewLogs() }
        case .generic:
            return { self.launcher.state = .idle }
        }
    }

    private var errorTertiaryAction: (() -> Void)? {
        switch errorType {
        case .containerCrashed:
            return nil
        default:
            return nil
        }
    }

    // MARK: - Status Properties

    private var pulseStatus: PulseIndicator.Status {
        switch launcher.state {
        case .idle, .stopped:
            return .idle
        case .working:
            return .active
        case .running:
            return launcher.gatewayHealthy ? .success : .warning
        case .needsAuth, .waitingForOAuthCode:
            return .active
        case .error:
            return .error
        }
    }

    private var sidebarStatusText: String {
        switch launcher.state {
        case .idle:
            return "Ready"
        case .working:
            return "Starting..."
        case .running:
            return launcher.gatewayHealthy ? "Running" : "Unhealthy"
        case .stopped:
            return "Stopped"
        case .needsAuth, .waitingForOAuthCode:
            return "Auth Required"
        case .error:
            return "Error"
        }
    }

    private var statusText: String {
        switch launcher.state {
        case .idle:
            return "Ready to Launch"
        case .working:
            if let current = launcher.steps.first(where: { $0.status == .running }) {
                return current.message
            }
            return "Initializing..."
        case .running:
            return "Environment Running"
        case .stopped:
            return "Environment Stopped"
        case .needsAuth:
            return "Authentication Required"
        case .waitingForOAuthCode:
            return "Waiting for Sign In"
        case .error:
            return "Error Occurred"
        }
    }

    private var badgeStyle: OceanBadge.Style {
        switch launcher.state {
        case .error:
            return .error
        case .stopped:
            return .warning
        default:
            return .default
        }
    }

    private var stepInfos: [StatusPanel.StepInfo] {
        let stepMappings: [(label: String, keywords: [String])] = [
            ("Docker connection", ["checking docker", "docker is ready", "docker not running"]),
            ("Container image", ["pulling latest image", "docker image up to date", "using cached image"]),
            ("Container setup", ["starting container", "container started", "container already running"]),
            ("Gateway service", ["waiting for gateway", "gateway is ready", "gateway is still"]),
            ("Configuration", ["first-time setup", "configuration created", "loaded existing", "recovered running"])
        ]

        return stepMappings.map { mapping in
            let matchingStep = launcher.steps.last { step in
                let msg = step.message.lowercased()
                return mapping.keywords.contains { keyword in
                    msg.contains(keyword)
                }
            }

            let status: OceanStepRow.Status
            let time: String?

            if let step = matchingStep {
                switch step.status {
                case .done:
                    status = .done
                    time = nil
                case .running:
                    status = .active
                    // Show pull progress for the "Container image" step
                    time = mapping.label == "Container image" ? launcher.pullProgressText : nil
                case .error:
                    status = .error
                    time = "failed"
                case .warning:
                    status = .done
                    time = nil
                case .pending:
                    status = .pending
                    time = nil
                }
            } else if launcher.state == .idle || launcher.state == .stopped {
                status = .pending
                time = nil
            } else {
                status = .pending
                time = nil
            }

            return StatusPanel.StepInfo(status: status, label: mapping.label, time: time)
        }
    }

    private var progress: Double? {
        guard launcher.state == .working || launcher.state == .running else {
            return nil
        }
        let completed = stepInfos.filter { $0.status == .done }.count
        let total = stepInfos.count
        return Double(completed) / Double(total)
    }

    private var progressLeftText: String? {
        guard progress != nil else { return nil }
        let completed = stepInfos.filter { $0.status == .done }.count
        let total = stepInfos.count
        return "\(completed) of \(total) steps"
    }

    private var progressRightText: String? {
        guard progress != nil else { return nil }
        if launcher.state == .running {
            return launcher.uptimeString
        }
        return nil
    }

    private var footerButtons: [FooterBar.FooterButton] {
        switch launcher.state {
        case .idle, .stopped:
            return [
                .init(title: "Launch", icon: "▶") {
                    launcher.configurePort(useRandomPort: settings.useRandomPort, customPort: settings.customPort)
                    launcher.configureResources(memoryLimit: settings.memoryLimit.rawValue, cpuLimit: settings.cpuLimit.rawValue)
                    launcher.start()
                }
            ]
        case .working, .needsAuth, .waitingForOAuthCode:
            return [
                .init(title: "Cancel", variant: .secondary) {
                    launcher.stopContainer()
                }
            ]
        case .running:
            return [
                .init(title: "Open Browser", icon: "🌐") {
                    launcher.openBrowser()
                },
                .init(title: "Stop", icon: "■", variant: .secondary) {
                    launcher.stopContainer()
                }
            ]
        case .error:
            return [
                .init(title: "Retry", icon: "↻") {
                    launcher.configurePort(useRandomPort: settings.useRandomPort, customPort: settings.customPort)
                    launcher.configureResources(memoryLimit: settings.memoryLimit.rawValue, cpuLimit: settings.cpuLimit.rawValue)
                    launcher.start()
                },
                .init(title: "Dismiss", variant: .secondary) {
                    launcher.state = .idle
                }
            ]
        }
    }
}

// MARK: - Sidebar View

private struct SidebarView: View {
    let status: PulseIndicator.Status
    let statusText: String
    let selectedNavItem: Binding<NewLauncherView.NavItem>
    let isRunning: Bool
    let onOpenBrowser: () -> Void
    let onViewLogs: () -> Void
    let onReAuthenticate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Logo and branding section
            VStack(spacing: 8) {
                // Logo with subtle glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Ocean.accentDim, .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 40
                            )
                        )
                        .frame(width: 80, height: 60)

                    Text("🐙")
                        .font(.system(size: 28))
                        .frame(width: 48, height: 48)
                        .background(Ocean.logoGradient)
                        .cornerRadius(12)
                        .shadow(color: Ocean.accent.opacity(0.3), radius: 8, y: 2)
                }

                Text("OpenClaw")
                    .font(Ocean.ui(16, weight: .bold))
                    .foregroundColor(Ocean.text)
                Text("Launcher")
                    .font(Ocean.ui(11, weight: .medium))
                    .foregroundColor(Ocean.textDim)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Status indicator
            HStack(spacing: 8) {
                PulseIndicator(status: status, size: 10)
                Text(statusText)
                    .font(Ocean.ui(12, weight: .medium))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Ocean.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(statusBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 16)

            Spacer()

            // Quick actions (only when running)
            if isRunning {
                VStack(spacing: 4) {
                    SidebarButton(icon: "globe", title: "Open UI") {
                        onOpenBrowser()
                    }
                    SidebarButton(icon: "doc.text", title: "View Logs") {
                        onViewLogs()
                    }

                    Divider()
                        .background(Ocean.border.opacity(0.3))
                        .padding(.vertical, 4)

                    SidebarButton(icon: "person.badge.key", title: "Re-auth") {
                        onReAuthenticate()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }

            // Version info
            VStack(spacing: 2) {
                Text("Docker Powered")
                    .font(Ocean.mono(9))
                    .foregroundColor(Ocean.textDim.opacity(0.7))
                Text("Lockdown Mode")
                    .font(Ocean.mono(9))
                    .foregroundColor(Ocean.accent.opacity(0.8))
            }
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .background(Ocean.surface)
    }

    private var statusColor: Color {
        switch status {
        case .idle: return Ocean.textDim
        case .active: return Ocean.accent
        case .success: return Ocean.success
        case .warning: return Ocean.warning
        case .error: return Ocean.error
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .idle: return Ocean.border
        case .active: return Ocean.border
        case .success: return Ocean.success.opacity(0.3)
        case .warning: return Ocean.warning.opacity(0.3)
        case .error: return Ocean.error.opacity(0.3)
        }
    }
}

// MARK: - Sidebar Button

private struct SidebarButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(Ocean.ui(12))
                Spacer()
            }
            .foregroundColor(Ocean.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Ocean.bg.opacity(0.5))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Main Content View

private struct MainContentView: View {
    @ObservedObject var launcher: OpenClawLauncher
    @ObservedObject var settings: LauncherSettings
    let stepInfos: [StatusPanel.StepInfo]
    let progress: Double?
    let progressLeftText: String?
    let progressRightText: String?
    let pulseStatus: PulseIndicator.Status
    let statusText: String
    let badgeStyle: OceanBadge.Style
    let errorType: ErrorStateView.ErrorType
    let errorSecondaryAction: (() -> Void)?
    let errorTertiaryAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch launcher.state {
                case .idle, .stopped:
                    // Clean idle view - no checklist
                    IdleContentView(port: launcher.activePort)

                case .working:
                    // Launching checklist with progress
                    StatusPanel(
                        status: pulseStatus,
                        statusText: "Launching OpenClaw...",
                        badgeStyle: badgeStyle,
                        steps: stepInfos,
                        progress: progress,
                        progressLeftText: progressLeftText
                    )

                case .running:
                    // Dashboard with stats grid
                    RunningDashboardView(launcher: launcher)

                case .error:
                    ErrorStateView(
                        errorType: errorType,
                        onRetry: {
                            launcher.configurePort(useRandomPort: settings.useRandomPort, customPort: settings.customPort)
                            launcher.configureResources(memoryLimit: settings.memoryLimit.rawValue, cpuLimit: settings.cpuLimit.rawValue)
                            launcher.start()
                        },
                        onSecondary: errorSecondaryAction,
                        onTertiary: errorTertiaryAction
                    )

                case .needsAuth:
                    OceanAuthChoiceView(launcher: launcher)

                case .waitingForOAuthCode:
                    if launcher.showApiKeyField {
                        OceanApiKeyInputView(launcher: launcher)
                    } else {
                        OceanOAuthCodeInputView(launcher: launcher)
                    }
                }
            }
            .padding(20)
        }
        .background(Ocean.bg)
    }
}

// MARK: - Tip Card

private struct TipCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("💡")
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Tip")
                    .font(Ocean.ui(12, weight: .semibold))
                    .foregroundColor(Ocean.text)
                Text("Use the menu bar icon for quick access when the window is closed.")
                    .font(Ocean.ui(11))
                    .foregroundColor(Ocean.textDim)
            }

            Spacer()
        }
        .padding(14)
        .background(Ocean.surface)
        .cornerRadius(Ocean.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Ocean.cardRadius)
                .stroke(Ocean.border, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct NewLauncherView_Previews: PreviewProvider {
    static var previews: some View {
        NewLauncherView(launcher: OpenClawLauncher())
            .frame(width: 600, height: 450)
    }
}
#endif
