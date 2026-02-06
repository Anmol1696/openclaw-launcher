import SwiftUI

/// Main settings view with tabs
public struct SettingsView: View {
    @ObservedObject var settings: LauncherSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SettingsTab = .general

    public enum SettingsTab: String, CaseIterable {
        case general = "General"
        case container = "Container"
        case advanced = "Advanced"
    }

    public init(settings: LauncherSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(Ocean.ui(16, weight: .semibold))
                    .foregroundColor(Ocean.text)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Ocean.textDim)
                        .frame(width: 24, height: 24)
                        .background(Ocean.surface)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Ocean.surface)

            Divider().background(Ocean.border)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Ocean.surface)

            Divider().background(Ocean.border)

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .general:
                        SettingsGeneralTab(settings: settings)
                    case .container:
                        SettingsContainerTab(settings: settings)
                    case .advanced:
                        SettingsAdvancedTab(settings: settings)
                    }
                }
                .padding(20)
            }
            .background(Ocean.bg)
        }
        .frame(width: 400, height: 450)
        .background(Ocean.bg)
        .onChange(of: settings.launchAtStartup) { _, _ in settings.save() }
        .onChange(of: settings.showInMenuBar) { _, _ in settings.save() }
        .onChange(of: settings.checkForUpdates) { _, _ in settings.save() }
        .onChange(of: settings.memoryLimit) { _, _ in settings.save() }
        .onChange(of: settings.cpuLimit) { _, _ in settings.save() }
        .onChange(of: settings.networkIsolation) { _, _ in settings.save() }
        .onChange(of: settings.filesystemIsolation) { _, _ in settings.save() }
        .onChange(of: settings.healthCheckInterval) { _, _ in settings.save() }
        .onChange(of: settings.customPort) { _, _ in settings.save() }
        .onChange(of: settings.debugMode) { _, _ in settings.save() }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Ocean.ui(12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Ocean.accent : Ocean.textDim)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? Ocean.accentDim : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: LauncherSettings())
    }
}
#endif
