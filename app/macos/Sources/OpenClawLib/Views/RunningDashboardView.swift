import SwiftUI
import AppKit

/// Dashboard view shown when container is running
/// Shows access URL, 2x2 stats grid (uptime, port, CPU, memory)
public struct RunningDashboardView: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(Ocean.success)
                    .frame(width: 10, height: 10)

                Text("OpenClaw is Running")
                    .font(Ocean.ui(20, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Spacer()

                OceanBadge("Lockdown", style: .default)
            }

            // Access URL Card
            AccessUrlCard(
                url: "localhost:\(launcher.activePort)",
                onCopy: {
                    // Copy handled in component
                },
                onOpen: {
                    launcher.openBrowser()
                }
            )

            // 2x2 Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    label: "UPTIME",
                    value: launcher.uptimeString,
                    valueColor: Ocean.accent
                )
                StatCard(
                    label: "PORT",
                    value: "\(launcher.activePort)",
                    valueColor: Ocean.text
                )
                StatCard(
                    label: "CPU",
                    value: cpuUsage,
                    valueColor: Ocean.accent
                )
                StatCard(
                    label: "MEMORY",
                    value: memoryUsage,
                    valueColor: Ocean.text
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // TODO: Get actual container stats from docker stats
    private var cpuUsage: String {
        "—"
    }

    private var memoryUsage: String {
        "—"
    }
}

#if DEBUG
struct RunningDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        RunningDashboardView(launcher: OpenClawLauncher())
            .padding(20)
            .background(Ocean.bg)
            .frame(width: 500, height: 450)
    }
}
#endif
