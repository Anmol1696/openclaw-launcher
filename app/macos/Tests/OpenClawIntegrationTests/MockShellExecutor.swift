import Foundation
@testable import OpenClawLib

final class MockShellExecutor: ShellExecutor, @unchecked Sendable {
    /// Commands that were executed, for assertions.
    var commandLog: [[String]] = []

    /// Handlers checked in order. First non-nil result wins.
    var handlers: [([String]) -> ShellResult?] = []

    /// Default result if no handler matches.
    var defaultResult = ShellResult(exitCode: 1, stdout: "", stderr: "command not mocked")

    func run(_ args: [String]) async throws -> ShellResult {
        commandLog.append(args)
        for handler in handlers {
            if let result = handler(args) {
                return result
            }
        }
        return defaultResult
    }

    // MARK: - Convenience Builders

    /// Respond to commands where first arg matches.
    func on(_ command: String, return result: ShellResult) {
        handlers.append { args in
            args.first == command ? result : nil
        }
    }

    /// Respond to commands matching a predicate.
    func on(_ predicate: @escaping ([String]) -> Bool, return result: ShellResult) {
        handlers.append { args in
            predicate(args) ? result : nil
        }
    }

    /// Match commands containing a specific substring in any argument.
    func onContaining(_ substring: String, return result: ShellResult) {
        handlers.append { args in
            args.contains(where: { $0.contains(substring) }) ? result : nil
        }
    }

    static let ok = ShellResult(exitCode: 0, stdout: "", stderr: "")
    static let fail = ShellResult(exitCode: 1, stdout: "", stderr: "mock error")

    static func ok(stdout: String) -> ShellResult {
        ShellResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    static func fail(stderr: String) -> ShellResult {
        ShellResult(exitCode: 1, stdout: "", stderr: stderr)
    }
}
