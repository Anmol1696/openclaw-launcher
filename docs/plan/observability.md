# Observability Improvements

## Current State

- Errors logged to console via `os.log`
- No crash reporting
- No analytics/telemetry
- Docker pull shows no progress
- Log viewer is static (300-line snapshot)

---

## 1. Crash Reporting (Sentry)

### Problem
No visibility into production crashes or errors.

### Solution
Integrate Sentry Swift SDK for crash and error reporting.

### Implementation

#### 1.1 Add Sentry Dependency

**File:** `app/macos/Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0")
],
targets: [
    .executableTarget(
        name: "OpenClawLauncher",
        dependencies: [
            "OpenClawLib",
            .product(name: "Sentry", package: "sentry-cocoa")
        ]
    ),
]
```

#### 1.2 Initialize Sentry

**File:** `app/macos/Sources/OpenClawApp/OpenClawApp.swift`

```swift
import Sentry

@main
struct OpenClawApp: App {
    init() {
        SentrySDK.start { options in
            options.dsn = "https://YOUR_DSN@sentry.io/PROJECT_ID"
            options.debug = false
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true

            // Sanitize sensitive data
            options.beforeSend = { event in
                return sanitizeEvent(event)
            }
        }
    }
}

private func sanitizeEvent(_ event: Event) -> Event? {
    // Remove sensitive paths
    if let message = event.message?.formatted {
        event.message = SentryMessage(formatted: sanitizePath(message))
    }

    // Remove breadcrumbs with sensitive data
    event.breadcrumbs = event.breadcrumbs?.filter { crumb in
        guard let data = crumb.data else { return true }
        // Filter out API keys, tokens, etc.
        return !data.keys.contains(where: { $0.contains("token") || $0.contains("key") })
    }

    return event
}

private func sanitizePath(_ message: String) -> String {
    // Replace home directory with ~
    return message.replacingOccurrences(
        of: FileManager.default.homeDirectoryForCurrentUser.path,
        with: "~"
    )
}
```

#### 1.3 Add Breadcrumbs

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

```swift
import Sentry

// In addStep() method
private func addStep(_ status: StepStatus, _ message: String) {
    // ... existing code ...

    // Add Sentry breadcrumb
    let crumb = Breadcrumb()
    crumb.level = status == .error ? .error : .info
    crumb.category = "launcher"
    crumb.message = message
    SentrySDK.addBreadcrumb(crumb)
}

// Capture errors
private func handleError(_ error: LauncherError) {
    SentrySDK.capture(error: error) { scope in
        scope.setTag(value: state.rawValue, key: "launcher_state")
        scope.setContext(value: [
            "docker_running": dockerRunning,
            "step_count": steps.count
        ], key: "launcher")
    }
}
```

### Data to Exclude

**Never send:**
- Gateway tokens
- API keys
- OAuth credentials
- File contents from workspace
- User email/name

**Safe to send:**
- Launch step descriptions
- Error types (not messages with user data)
- App version
- macOS version
- Docker version
- Performance timings

### Sentry Setup

1. Create Sentry account at sentry.io
2. Create new Swift project
3. Copy DSN to app
4. Configure alerts for error rate

### Effort
Medium (2 hrs)

---

## 2. Docker Pull Progress

### Problem
First-time image pull can take 5+ minutes with no feedback.

### Current State
- `pullProgressText` property exists but is never populated
- `ensureImage()` runs `docker pull` but doesn't parse output

### Solution
Parse Docker pull output and update progress.

### Implementation

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

```swift
@Published public var pullProgressText: String = ""
@Published public var pullProgress: Double = 0.0

private func ensureImage() async throws {
    addStep(.running, "Pulling latest Docker image...")

    // Use streaming output to parse progress
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["docker", "pull", dockerImage]
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()

    // Parse output line by line
    let handle = pipe.fileHandleForReading
    var totalLayers = 0
    var completedLayers = 0

    for try await line in handle.bytes.lines {
        // Parse layer progress
        // Format: "abc123: Downloading [====>   ] 45.2MB/100MB"
        // Format: "abc123: Pull complete"

        if line.contains("Pulling from") {
            pullProgressText = "Starting download..."
        } else if line.contains("Downloading") {
            // Extract layer info
            if let match = line.firstMatch(of: /(\w+): Downloading.*?(\d+\.?\d*)([MG]B)\/(\d+\.?\d*)([MG]B)/) {
                let current = Double(match.2) ?? 0
                let total = Double(match.4) ?? 1
                let percent = Int((current / total) * 100)
                pullProgressText = "Downloading: \(percent)%"
            }
        } else if line.contains("Pull complete") {
            completedLayers += 1
            if totalLayers > 0 {
                pullProgress = Double(completedLayers) / Double(totalLayers)
                pullProgressText = "Layer \(completedLayers)/\(totalLayers) complete"
            }
        } else if line.contains("Pulling fs layer") {
            totalLayers += 1
        } else if line.contains("Already exists") {
            completedLayers += 1
            totalLayers += 1
        }
    }

    process.waitUntilExit()

    if process.terminationStatus == 0 {
        addStep(.done, "Image updated")
        pullProgressText = ""
        pullProgress = 0
    } else {
        // Handle failure...
    }
}
```

### UI Integration

**File:** `app/macos/Sources/OpenClawLib/LauncherViews.swift`

In SetupView, add progress indicator:
```swift
if !launcher.pullProgressText.isEmpty {
    VStack(spacing: 4) {
        ProgressView(value: launcher.pullProgress)
        Text(launcher.pullProgressText)
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding(.horizontal)
}
```

### Effort
Low (30 min)

---

## 3. Container Log Streaming

### Problem
Log viewer shows static 300-line snapshot, requires manual refresh.

### Current State
```swift
func getContainerLogs() async throws -> String {
    let result = try await shell("docker", "logs", "--tail", "300", containerName)
    return result.stdout
}
```

### Solution
Stream logs in real-time using `docker logs -f`.

### Implementation

#### 3.1 Add Streaming Log Method

**File:** `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift`

```swift
@Published public var logLines: [String] = []
@Published public var isStreamingLogs: Bool = false

private var logStreamTask: Task<Void, Never>?

public func startLogStream() {
    guard !isStreamingLogs else { return }
    isStreamingLogs = true
    logLines = []

    logStreamTask = Task {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "logs", "-f", "--tail", "100", containerName]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self.logLines.append(line)
                    // Keep last 1000 lines
                    if self.logLines.count > 1000 {
                        self.logLines.removeFirst(self.logLines.count - 1000)
                    }
                }
            }
        } catch {
            // Log stream ended
        }

        await MainActor.run {
            self.isStreamingLogs = false
        }
    }
}

public func stopLogStream() {
    logStreamTask?.cancel()
    logStreamTask = nil
    isStreamingLogs = false
}
```

#### 3.2 Update Log Viewer UI

**File:** `app/macos/Sources/OpenClawLib/LauncherViews.swift`

```swift
struct LogViewerSheet: View {
    @ObservedObject var launcher: OpenClawLauncher
    @State private var followTail = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Follow", isOn: $followTail)
                Spacer()
                Button(launcher.isStreamingLogs ? "Stop" : "Start") {
                    if launcher.isStreamingLogs {
                        launcher.stopLogStream()
                    } else {
                        launcher.startLogStream()
                    }
                }
                Button("Copy") {
                    NSPasteboard.general.setString(
                        launcher.logLines.joined(separator: "\n"),
                        forType: .string
                    )
                }
            }
            .padding()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(launcher.logLines.enumerated()), id: \.0) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding()
                }
                .onChange(of: launcher.logLines.count) { _ in
                    if followTail, let last = launcher.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            launcher.startLogStream()
        }
        .onDisappear {
            launcher.stopLogStream()
        }
    }
}
```

### Effort
Medium (2 hrs)

---

## 4. Performance Metrics

### Future Consideration
Track key performance metrics:
- App startup time
- Docker startup time
- Image pull duration
- Gateway startup time
- Health check latency

Could integrate with Sentry Performance or custom metrics.

### Effort
Medium (deferred)

---

## Implementation Order

1. **Docker Pull Progress** - Quick UX win
2. **Sentry Integration** - Production visibility
3. **Log Streaming** - Better debugging (may overlap with UI revamp)

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/macos/Package.swift` | Add Sentry dependency |
| `app/macos/Sources/OpenClawApp/OpenClawApp.swift` | Initialize Sentry |
| `app/macos/Sources/OpenClawLib/OpenClawLauncher.swift` | Breadcrumbs, pull progress, log streaming |
| `app/macos/Sources/OpenClawLib/LauncherViews.swift` | Progress UI, log viewer update |

---

## External Setup

| Item | Action |
|------|--------|
| Sentry account | Create at sentry.io |
| Sentry project | Create Swift/macOS project |
| DSN | Copy to app code |
| Alerts | Configure error rate alerts |
