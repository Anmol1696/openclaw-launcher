import SwiftUI
import OpenClawLib

@main
struct OpenClawApp: App {
    @StateObject private var launcher = OpenClawLauncher()

    var body: some Scene {
        WindowGroup {
            LauncherView(launcher: launcher)
                .frame(width: 480, height: 520)
                .onAppear { launcher.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
