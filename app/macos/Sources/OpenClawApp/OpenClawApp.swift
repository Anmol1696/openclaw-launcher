import SwiftUI
import OpenClawLib

@main
struct OpenClawApp: App {
    @StateObject private var launcher: OpenClawLauncher
    @StateObject private var settings: LauncherSettings

    init() {
        // Proper StateObject initialization - load settings once at startup
        _launcher = StateObject(wrappedValue: OpenClawLauncher())
        _settings = StateObject(wrappedValue: LauncherSettings.load())
    }

    var body: some Scene {
        WindowGroup {
            if !settings.hasCompletedOnboarding {
                OnboardingView(settings: settings) {
                    // Onboarding complete - launcher will auto-start if user clicked "Launch"
                    configureLauncher()
                    launcher.start()
                }
                .frame(width: 500, height: 400)
            } else {
                NewLauncherView(launcher: launcher, settings: settings)
                    .frame(width: 700, height: launcher.state == .running ? 520 : 480)
                    .animation(.easeInOut(duration: 0.3), value: launcher.state)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings Window
        Window("Settings", id: "settings") {
            SettingsView(
                settings: settings,
                onReAuthenticate: { launcher.reAuthenticate() },
                onResetAll: { launcher.resetEverything() }
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Menu Bar Extra (macOS 13+)
        MenuBarExtra {
            MenuBarContent(launcher: launcher)
        } label: {
            Text("🐙")
        }
    }

    /// Configure launcher with current settings (port + resources)
    private func configureLauncher() {
        launcher.configurePort(useRandomPort: settings.useRandomPort, customPort: settings.customPort)
        launcher.configureResources(memoryLimit: settings.memoryLimit.rawValue, cpuLimit: settings.cpuLimit.rawValue)
    }
}
