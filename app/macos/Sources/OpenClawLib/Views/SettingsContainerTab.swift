import SwiftUI

/// Container settings tab
public struct SettingsContainerTab: View {
    @ObservedObject var settings: LauncherSettings

    public init(settings: LauncherSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsSectionHeader("Resource Limits")

            SettingsDropdownRow(
                "Memory limit",
                subtitle: "Maximum RAM for the container",
                options: LauncherSettings.MemoryLimit.allCases,
                optionLabel: { $0.displayName },
                selection: $settings.memoryLimit
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsDropdownRow(
                "CPU limit",
                subtitle: "Maximum CPU cores",
                options: LauncherSettings.CPULimit.allCases,
                optionLabel: { $0.displayName },
                selection: $settings.cpuLimit
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Security")

            SettingsToggleRow(
                "Network isolation",
                subtitle: "Restrict container network access",
                isOn: $settings.networkIsolation
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsToggleRow(
                "Filesystem isolation",
                subtitle: "Read-only root filesystem",
                isOn: $settings.filesystemIsolation
            )

            Spacer()

            // Warning box
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Ocean.warning)
                    .font(.system(size: 12))

                Text("Changing resource limits requires restart")
                    .font(Ocean.ui(11))
                    .foregroundColor(Ocean.textDim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ocean.warning.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsContainerTab_Previews: PreviewProvider {
    static var previews: some View {
        SettingsContainerTab(settings: LauncherSettings())
            .padding(20)
            .background(Ocean.bg)
            .frame(width: 350)
    }
}
#endif
