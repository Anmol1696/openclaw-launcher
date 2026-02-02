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
            let color: Color = {
                switch launcher.menuBarStatus {
                case .running: return .green
                case .starting: return .yellow
                case .stopped: return .red
                }
            }()
            Image(systemName: "circle.fill")
                .foregroundStyle(color)
        }
    }
}
