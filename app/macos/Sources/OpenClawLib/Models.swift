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

// MARK: - Shell Executor Protocol

public protocol ShellExecutor: Sendable {
    func run(_ args: [String]) async throws -> ShellResult
}

// MARK: - Settings

public struct LauncherSettings: Codable, Equatable {
    public var healthCheckInterval: TimeInterval
    public var openBrowserOnStart: Bool
    public var dockerImage: String
    public var memoryLimit: String
    public var cpuLimit: Double
    public var port: Int

    public init(
        healthCheckInterval: TimeInterval = 5.0,
        openBrowserOnStart: Bool = true,
        dockerImage: String = "ghcr.io/openclaw/openclaw:latest",
        memoryLimit: String = "2g",
        cpuLimit: Double = 2.0,
        port: Int = 18789
    ) {
        self.healthCheckInterval = healthCheckInterval
        self.openBrowserOnStart = openBrowserOnStart
        self.dockerImage = dockerImage
        self.memoryLimit = memoryLimit
        self.cpuLimit = cpuLimit
        self.port = port
    }

    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-launcher")
            .appendingPathComponent("settings.json")
    }

    public static func load() -> LauncherSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data)
        else {
            return LauncherSettings()
        }
        return settings
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        // Ensure directory exists
        let dir = LauncherSettings.settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: LauncherSettings.settingsURL)
    }
}

// MARK: - Errors

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
