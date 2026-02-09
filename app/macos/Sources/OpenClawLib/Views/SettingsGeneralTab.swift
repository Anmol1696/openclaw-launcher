import SwiftUI

/// General settings tab
public struct SettingsGeneralTab: View {
    @ObservedObject var settings: LauncherSettings

    public init(settings: LauncherSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsSectionHeader("Startup")

            SettingsToggleRow(
                "Launch at startup",
                subtitle: "Start OpenClaw when you log in",
                isOn: $settings.launchAtStartup
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsToggleRow(
                "Show in menu bar",
                subtitle: "Quick access from the menu bar",
                isOn: $settings.showInMenuBar
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Updates")

            SettingsToggleRow(
                "Check for updates",
                subtitle: "Automatically check for new versions",
                isOn: $settings.checkForUpdates
            )

            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsGeneralTab_Previews: PreviewProvider {
    static var previews: some View {
        SettingsGeneralTab(settings: LauncherSettings())
            .padding(20)
            .background(Ocean.bg)
            .frame(width: 350)
    }
}
#endif
