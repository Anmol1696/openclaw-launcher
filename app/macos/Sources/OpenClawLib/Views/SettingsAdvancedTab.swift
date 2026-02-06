import SwiftUI

/// Advanced settings tab
public struct SettingsAdvancedTab: View {
    @ObservedObject var settings: LauncherSettings
    @State private var portString: String = ""
    @State private var showResetConfirm = false

    public init(settings: LauncherSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsSectionHeader("Health Check")

            SettingsStepperRow(
                "Check interval",
                subtitle: "Seconds between health checks",
                value: $settings.healthCheckInterval,
                range: 1...30,
                step: 1,
                formatter: { "\(Int($0))s" }
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Network")

            SettingsTextFieldRow(
                "Gateway port",
                subtitle: "Port for the gateway server",
                value: $portString,
                placeholder: "18789"
            )
            .onAppear {
                portString = String(settings.customPort)
            }
            .onChange(of: portString) { _, newValue in
                if let port = Int(newValue), port > 0 && port < 65536 {
                    settings.customPort = port
                }
            }

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Debug")

            SettingsToggleRow(
                "Debug mode",
                subtitle: "Enable verbose logging",
                isOn: $settings.debugMode
            )

            Spacer()

            // Reset button
            HStack {
                Spacer()

                Button {
                    showResetConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Reset to Defaults")
                            .font(Ocean.ui(12))
                    }
                    .foregroundColor(Ocean.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ocean.error.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Reset Settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                portString = String(settings.customPort)
            }
        } message: {
            Text("This will reset all settings to their default values.")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsAdvancedTab_Previews: PreviewProvider {
    static var previews: some View {
        SettingsAdvancedTab(settings: LauncherSettings())
            .padding(20)
            .background(Ocean.bg)
            .frame(width: 350)
    }
}
#endif
