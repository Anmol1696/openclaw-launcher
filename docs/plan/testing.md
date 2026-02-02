# Integration Testing Plan

## Problem

The launcher's `shell()` method is private and tightly coupled to `Process`. We can't test Docker workflow, error handling, or state transitions without Docker running. CI (GitHub Actions `macos-14`) has no Docker Desktop.

Current tests cover only isolated units: token generation, OAuth PKCE, config JSON, error descriptions, UI state.

## Approach: Protocol-Based Shell Injection

### 1. `ShellExecutor` Protocol

Add to `app/macos/Sources/OpenClawLib/Models.swift`:

```swift
public protocol ShellExecutor: Sendable {
    func execute(_ args: [String]) async throws -> ShellResult
}
```

### 2. `ProcessShellExecutor` (Production)

Extract the current private `shell()` body into a public class in `OpenClawLauncher.swift`:

```swift
public final class ProcessShellExecutor: ShellExecutor {
    public init() {}

    public func execute(_ args: [String]) async throws -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/Applications/Docker.app/Contents/Resources/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        try process.run()

        let outData = try await Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        let errData = try await Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        process.waitUntilExit()

        return ShellResult(
            exitCode: Int(process.terminationStatus),
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
```

### 3. Update `OpenClawLauncher`

- Add `private let shellExecutor: ShellExecutor`
- Change init: `public init(shellExecutor: ShellExecutor = ProcessShellExecutor())`
- Replace all `try await shell("docker", "info")` → `try await shellExecutor.execute(["docker", "info"])`
- Remove the private `shell()` method

Existing code using `OpenClawLauncher()` with no args continues to work via the default parameter.

### 4. `MockShellExecutor` (Tests)

New file: `app/macos/Tests/OpenClawTests/MockShellExecutor.swift`

```swift
import OpenClawLib

final class MockShellExecutor: ShellExecutor, @unchecked Sendable {
    var responses: [([String]) -> ShellResult?] = []
    var defaultResponse = ShellResult(exitCode: 0, stdout: "", stderr: "")
    var commandLog: [[String]] = []

    func execute(_ args: [String]) async throws -> ShellResult {
        commandLog.append(args)
        for handler in responses {
            if let result = handler(args) {
                return result
            }
        }
        return defaultResponse
    }

    /// Helper: respond to commands starting with a specific prefix
    func on(_ prefix: String..., result: ShellResult) {
        let prefix = prefix
        responses.append { args in
            guard args.starts(with: prefix) else { return nil }
            return result
        }
    }
}
```

### 5. Integration Test Scenarios

New file: `app/macos/Tests/OpenClawTests/LauncherIntegrationTests.swift`

| Scenario | Mock Setup | Expected State |
|----------|-----------|----------------|
| **Happy path** | `which docker` → 0, `docker info` → 0, `docker pull` → 0, `docker run` → 0, `curl` → 0 | `.running`, all steps done |
| **Docker not installed** | `which docker` → 1, no `/Applications/Docker.app` | Error about Docker |
| **Docker not running** | `docker info` → 1 (all retries) | `.error`, timeout message |
| **Pull fails, cached image** | `docker pull` → 1, `docker image inspect` → 0 | Warning step, continues |
| **Pull fails, no cache** | `docker pull` → 1, `docker image inspect` → 1 | `.error` |
| **Container already running** | `docker ps` → returns container name | Skips start, step "already running" |
| **Restart failure** | `docker restart` → non-zero | `.error`, menu bar red |
| **Gateway timeout** | `curl` → always 1 | Warning step, still transitions to `.running` |
| **Stop clears state** | After running, call `stopContainer()` | `.stopped`, empty steps, timers stopped |

### 6. Docker Install Edge Cases (Future)

These can't be easily mocked but are worth documenting:

- First launch of Docker Desktop requires EULA acceptance (can't automate)
- Admin password prompt may be cancelled by user → `dockerInstallFailed`
- 90-second Docker startup timeout may not be enough on slow machines
- DMG download can fail (network issues) → should show clear error
- `/Volumes/Docker` mount path assumed — could differ in future Docker versions

## Files to Create/Modify

| File | Action |
|------|--------|
| `app/macos/Sources/OpenClawLib/Models.swift` | Add `ShellExecutor` protocol |
| `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift` | Extract executor, inject via init, update ~15 call sites |
| `app/macos/Tests/OpenClawTests/MockShellExecutor.swift` | New: mock implementation |
| `app/macos/Tests/OpenClawTests/LauncherIntegrationTests.swift` | New: integration tests |

Existing tests (`TokenTests`, `ConfigTests`, `ErrorTests`, `OAuthTests`, `UIStateTests`) need no changes — `OpenClawLauncher()` default init still works.
