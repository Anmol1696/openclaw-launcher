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
                    launcher.start()
                }
                .frame(width: 500, height: 400)
            } else {
                NewLauncherView(launcher: launcher, settings: settings)
                    .frame(width: 650, height: launcher.state == .running ? 480 : 420)
                    .animation(.easeInOut(duration: 0.3), value: launcher.state)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings Window
        Window("Settings", id: "settings") {
            SettingsView(settings: settings)
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
}
