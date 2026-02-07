import Foundation

public enum StepStatus { case pending, running, done, error, warning }

public enum LauncherState { case idle, working, needsAuth, selectingProvider, waitingForApiKey, waitingForOAuthCode, running, stopped, error }

public enum MenuBarStatus { case starting, running, stopped }

// MARK: - Auth Providers

public enum AuthProvider: String, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Google AI"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "GPT (OpenAI)"
        case .google: return "Gemini (Google AI)"
        }
    }

    public var description: String {
        switch self {
        case .anthropic: return "Sign in with your Claude account or use an API key"
        case .openai: return "Enter your OpenAI API key"
        case .google: return "Enter your Google AI API key"
        }
    }

    public var supportsOAuth: Bool {
        switch self {
        case .anthropic: return true
        case .openai, .google: return false
        }
    }

    public var apiKeyPrefix: String {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai: return "sk-"
        case .google: return ""  // Google AI keys don't have a standard prefix
        }
    }

    public var apiKeyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-api..."
        case .openai: return "sk-proj-..."
        case .google: return "AIza..."
        }
    }
}

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

// MARK: - Shell Executor Protocol

public protocol ShellExecutor: Sendable {
    func run(_ args: [String]) async throws -> ShellResult
}

public enum LauncherError: LocalizedError {
    case dockerNotRunning
    case dockerNotInstalled
    case pullFailed(String)
    case runFailed(String)
    case noToken

    public var errorDescription: String? {
        switch self {
        case .dockerNotRunning:
            return "Docker Desktop is not running. Please start it and try again."
        case .dockerNotInstalled:
            return "Docker Desktop is required. Please install it and try again."
        case .pullFailed(let msg):
            return "Failed to pull Docker image: \(msg.prefix(200))"
        case .runFailed(let msg):
            return "Failed to start container: \(msg.prefix(200))"
        case .noToken:
            return "Gateway token not generated. Try resetting: rm -rf ~/.openclaw-launcher"
        }
    }
}
