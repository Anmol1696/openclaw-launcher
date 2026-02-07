import SwiftUI

/// Advanced settings tab
public struct SettingsAdvancedTab: View {
    @ObservedObject var settings: LauncherSettings
    @State private var portString: String = ""
    @State private var showResetConfirm = false
    @State private var showResetAllConfirm = false

    var onReAuthenticate: (() -> Void)?
    var onResetAll: (() -> Void)?

    public init(
        settings: LauncherSettings,
        onReAuthenticate: (() -> Void)? = nil,
        onResetAll: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.onReAuthenticate = onReAuthenticate
        self.onResetAll = onResetAll
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

            SettingsToggleRow(
                "Use random port",
                subtitle: "More secure - assigns a random available port",
                isOn: $settings.useRandomPort
            )

            if !settings.useRandomPort {
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
                    // Restrict to non-privileged ports (1024+) to avoid requiring root
                    if let port = Int(newValue), port >= 1024 && port < 65536 {
                        settings.customPort = port
                    }
                }
            }

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Debug")

            SettingsToggleRow(
                "Debug mode",
                subtitle: "Enable verbose logging",
                isOn: $settings.debugMode
            )

            Divider().background(Ocean.border.opacity(0.3))

            SettingsSectionHeader("Account")

            // Re-authenticate button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-authenticate")
                        .font(Ocean.ui(13))
                        .foregroundColor(Ocean.text)
                    Text("Sign in again with a different account")
                        .font(Ocean.ui(11))
                        .foregroundColor(Ocean.textDim)
                }

                Spacer()

                Button {
                    onReAuthenticate?()
                } label: {
                    Text("Sign In")
                        .font(Ocean.ui(12, weight: .medium))
                        .foregroundColor(Ocean.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ocean.accentDim)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                // Reset & Clean Up
                Button {
                    showResetAllConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Reset & Clean Up")
                            .font(Ocean.ui(12))
                    }
                    .foregroundColor(Ocean.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ocean.error.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()

                // Reset to Defaults
                Button {
                    showResetConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Reset Settings")
                            .font(Ocean.ui(12))
                    }
                    .foregroundColor(Ocean.textDim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ocean.surface)
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
        .alert("Reset & Clean Up?", isPresented: $showResetAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                onResetAll?()
            }
        } message: {
            Text("This will stop the container, remove all local config (~/.openclaw-launcher), and require you to set up again.")
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
