import SwiftUI
import OpenClawLib

@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()
    @StateObject private var settings = LauncherSettings.load()
    @AppStorage("useNewUI") private var useNewUI = true  // Feature flag for new Ocean UI

    var body: some Scene {
        WindowGroup {
            if !settings.hasCompletedOnboarding {
                OnboardingView(settings: settings) {
                    // Onboarding complete - launcher will auto-start if user clicked "Launch"
                    launcher.start()
                }
                .frame(width: 500, height: 400)
            } else if useNewUI {
                NewLauncherView(launcher: launcher, settings: settings)
                    .frame(width: 650, height: launcher.state == .running ? 480 : 420)
                    .animation(.easeInOut(duration: 0.3), value: launcher.state)
                    // No auto-start - user clicks Launch button
            } else {
                LauncherView(launcher: launcher)
                    .frame(width: 520, height: launcher.state == .running ? 580 : 520)
                    .animation(.easeInOut(duration: 0.25), value: launcher.state)
                    .onAppear { launcher.start() }
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
