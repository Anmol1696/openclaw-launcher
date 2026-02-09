import SwiftUI

// MARK: - Menu Bar Content

/// Menu bar dropdown content (used by MenuBarExtra)
public struct MenuBarContent: View {
    @ObservedObject var launcher: OpenClawLauncher

    public init(launcher: OpenClawLauncher) {
        self.launcher = launcher
    }

    public var body: some View {
        Button("Open Control UI") {
            launcher.openBrowser()
        }
        .disabled(launcher.state != .running)

        Divider()

        Button("Restart") {
            Task {
                await launcher.restartContainer()
            }
        }
        .disabled(launcher.state != .running)

        Button("Stop") {
            launcher.stopContainer()
        }
        .disabled(launcher.state != .running)

        Divider()

        Button("View Logs") {
            launcher.fetchLogs()
        }

        Button("Show Window") {
            NSApp.activate(ignoringOtherApps: true)
            let window = NSApp.windows.first { $0.contentView != nil && $0.title != "" }
                ?? NSApp.windows.first
            window?.makeKeyAndOrderFront(nil)
        }

        Button("Sign In Again...") {
            launcher.reAuthenticate()
        }

        Divider()

        Button("Reset & Clean Up...") {
            launcher.showResetConfirm = true
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
