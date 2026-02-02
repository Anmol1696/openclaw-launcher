import SwiftUI
import OpenClawLib

@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()

    var body: some Scene {
        WindowGroup {
            LauncherView(launcher: launcher)
                .frame(width: 520, height: launcher.state == .running ? 580 : 520)
                .animation(.easeInOut(duration: 0.25), value: launcher.state)
                .onAppear { launcher.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Menu Bar Extra (macOS 13+)
        MenuBarExtra {
            MenuBarContent(launcher: launcher)
        } label: {
            HStack(spacing: 2) {
                Text("🐙")
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle({
                        switch launcher.menuBarStatus {
                        case .running: return Color.green
                        case .starting: return Color.yellow
                        case .stopped: return Color.red
                        }
                    }())
            }
        }
    }
}
