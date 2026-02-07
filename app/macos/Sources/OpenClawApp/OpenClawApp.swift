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
                .onOpenURL { url in
                    handleOAuthCallback(url)
                }
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

    /// Handle OAuth callback from custom URL scheme
    /// Expected format: openclaw://oauth/callback?code=XXX&state=YYY
    private func handleOAuthCallback(_ url: URL) {
        guard url.scheme == "openclaw",
              url.host == "oauth",
              url.path == "/callback" || url.path.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            return
        }

        // The state parameter contains the PKCE verifier in our implementation
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value

        // Pass the code to the launcher to complete the exchange
        Task { @MainActor in
            launcher.handleOAuthCallback(code: code, state: state)
        }
    }
}
