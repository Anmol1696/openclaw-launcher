import SwiftUI

/// Ocean-themed menu bar popover
public struct MenuBarPopover: View {
    @ObservedObject var launcher: OpenClawLauncher
    @Environment(\.openWindow) private var openWindow

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                // Logo
                Text("🐙")
                    .font(.system(size: 20))
                    .frame(width: 32, height: 32)
                    .background(Ocean.logoGradient)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenClaw")
                        .font(Ocean.ui(13, weight: .semibold))
                        .foregroundColor(Ocean.text)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(Ocean.ui(11))
                            .foregroundColor(Ocean.textDim)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(Ocean.surface)

            Divider().background(Ocean.border)

            // Stats (when running)
            if launcher.state == .running {
                HStack(spacing: 0) {
                    StatBox(label: "Uptime", value: launcher.uptimeString)
                    Divider().background(Ocean.border)
                    StatBox(label: "Status", value: launcher.gatewayHealthy ? "Healthy" : "Checking...")
                }
                .frame(height: 50)
                .background(Ocean.surface)

                Divider().background(Ocean.border)
            }

            // Actions
            VStack(spacing: 0) {
                if launcher.state == .running {
                    MenuAction(icon: "globe", label: "Open Control UI") {
                        launcher.openBrowser()
                    }

                    MenuAction(icon: "doc.text", label: "View Logs") {
                        launcher.fetchLogs()
                    }

                    Divider().background(Ocean.border.opacity(0.5)).padding(.horizontal, 12)

                    MenuAction(icon: "arrow.clockwise", label: "Restart") {
                        Task { await launcher.restartContainer() }
                    }

                    MenuAction(icon: "stop.fill", label: "Stop", color: Ocean.error) {
                        launcher.stopContainer()
                    }
                } else if launcher.state == .idle || launcher.state == .stopped {
                    MenuAction(icon: "play.fill", label: "Launch", color: Ocean.accent) {
                        launcher.start()
                    }
                } else if launcher.state == .working {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Starting...")
                            .font(Ocean.ui(12))
                            .foregroundColor(Ocean.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(.vertical, 4)
            .background(Ocean.bg)

            Divider().background(Ocean.border)

            // Footer
            HStack {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .buttonStyle(.plain)
                .font(Ocean.ui(11))
                .foregroundColor(Ocean.textDim)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(Ocean.ui(11))
                .foregroundColor(Ocean.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Ocean.surface)
        }
        .frame(width: 260)
        .background(Ocean.bg)
    }

    private var statusColor: Color {
        switch launcher.state {
        case .running:
            return launcher.gatewayHealthy ? Ocean.success : Ocean.warning
        case .working:
            return Ocean.accent
        case .error:
            return Ocean.error
        default:
            return Ocean.textDim
        }
    }

    private var statusText: String {
        switch launcher.state {
        case .idle, .stopped:
            return "Stopped"
        case .working:
            return "Starting..."
        case .running:
            return "Running"
        case .error:
            return "Error"
        case .needsAuth, .waitingForOAuthCode:
            return "Auth Required"
        }
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Ocean.mono(12, weight: .medium))
                .foregroundColor(Ocean.text)
            Text(label)
                .font(Ocean.ui(10))
                .foregroundColor(Ocean.textDim)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Menu Action

private struct MenuAction: View {
    let icon: String
    let label: String
    var color: Color = Ocean.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(Ocean.ui(12))
                Spacer()
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { isHovered in
            // Hover effect handled by system
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MenuBarPopover_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarPopover(launcher: OpenClawLauncher())
    }
}
#endif
