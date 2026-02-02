import Foundation

public enum StepStatus { case pending, running, done, error, warning }

public enum LauncherState { case idle, working, needsAuth, waitingForOAuthCode, running, stopped, error }

public enum MenuBarStatus { case starting, running, stopped }

public struct GatewayStatus: Codable {
    public let uptime: Int?
}

public struct LaunchStep: Identifiable {
    public let id = UUID()
    public let status: StepStatus
    public let message: String

    public init(status: StepStatus, message: String) {
        self.status = status
        self.message = message
    }
}

public struct ShellResult {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum LauncherError: LocalizedError {
    case dockerNotRunning
    case dockerInstallFailed(String)
    case pullFailed(String)
    case runFailed(String)
    case noToken

    public var errorDescription: String? {
        switch self {
        case .dockerNotRunning:
            return "Docker Desktop is not running. Please start it and try again."
        case .dockerInstallFailed(let msg):
            return "Failed to install Docker Desktop: \(msg)"
        case .pullFailed(let msg):
            return "Failed to pull Docker image: \(msg.prefix(200))"
        case .runFailed(let msg):
            return "Failed to start container: \(msg.prefix(200))"
        case .noToken:
            return "Gateway token not generated. Try resetting: rm -rf ~/.openclaw-launcher"
        }
    }
}
