import Foundation

/// Docker binary & app discovery for macOS.
///
/// When the app is launched from a signed DMG (via Finder), it inherits the restricted
/// launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) which doesn't include Docker's location.
/// This module provides direct filesystem checks that work regardless of PATH.
///
/// Covers: Docker Desktop, OrbStack, Homebrew, Colima, Rancher Desktop, Podman, Lima, Nix, MacPorts
public enum DockerPaths {

    // MARK: - Docker CLI Binary Paths

    /// Known Docker CLI binary locations, ordered by likelihood on a typical macOS setup.
    /// The first match that exists and is executable wins.
    static let binarySearchPaths: [(backend: String, path: String)] = [
        // --- Docker Desktop ---
        ("Docker Desktop",  "/usr/local/bin/docker"),
        ("Docker Desktop",  "/Applications/Docker.app/Contents/Resources/bin/docker"),
        ("Docker Desktop",  "\(home)/.docker/bin/docker"),
        // --- OrbStack ---
        ("OrbStack",        "\(home)/.orbstack/bin/docker"),
        ("OrbStack",        "/Applications/OrbStack.app/Contents/Resources/bin/docker"),
        // --- Homebrew ---
        ("Homebrew",        "/opt/homebrew/bin/docker"),          // Apple Silicon
        // --- Colima (relies on Homebrew docker CLI; detect colima binary) ---
        ("Colima",          "/opt/homebrew/bin/colima"),
        ("Colima",          "/usr/local/bin/colima"),
        // --- Rancher Desktop ---
        ("Rancher Desktop", "\(home)/.rd/bin/docker"),
        ("Rancher Desktop", "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/bin/docker"),
        // --- Podman (Docker-compatible mode) ---
        ("Podman",          "/opt/homebrew/bin/podman"),
        ("Podman",          "/usr/local/bin/podman"),
        ("Podman",          "\(home)/.local/bin/podman"),
        // --- Lima ---
        ("Lima",            "/opt/homebrew/bin/limactl"),
        ("Lima",            "/usr/local/bin/limactl"),
        // --- Nix ---
        ("Nix",             "\(home)/.nix-profile/bin/docker"),
        ("Nix",             "/run/current-system/sw/bin/docker"),
        // --- MacPorts ---
        ("MacPorts",        "/opt/local/bin/docker"),
    ]

    // MARK: - App Bundle Paths

    /// Known macOS app bundle locations for Docker-compatible runtimes.
    static let appBundlePaths: [(backend: String, path: String)] = [
        ("Docker Desktop",  "/Applications/Docker.app"),
        ("OrbStack",        "/Applications/OrbStack.app"),
        ("Rancher Desktop", "/Applications/Rancher Desktop.app"),
        ("Podman Desktop",  "/Applications/Podman Desktop.app"),
    ]

    // MARK: - Helpers

    private static var home: String { NSHomeDirectory() }

    /// Find the first available docker binary via direct filesystem check (no PATH needed).
    public static func findDockerBinary() -> (backend: String, path: String)? {
        binarySearchPaths.first { entry in
            FileManager.default.isExecutableFile(atPath: entry.path)
        }
    }

    /// Check if any Docker-compatible runtime app is installed.
    public static func findInstalledApp() -> (backend: String, path: String)? {
        appBundlePaths.first { entry in
            FileManager.default.fileExists(atPath: entry.path)
        }
    }

    /// All binary directories to prepend to PATH for Process calls.
    public static var extraPathDirs: [String] {
        [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/Applications/Docker.app/Contents/Resources/bin",
            "\(home)/.docker/bin",
            "\(home)/.orbstack/bin",
            "\(home)/.rd/bin",
            "\(home)/.local/bin",
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/opt/local/bin",
        ]
    }

    /// Returns a copy of the current process environment with PATH augmented
    /// to include Docker and tool locations, and DOCKER_CONFIG set to the
    /// isolated OpenClaw config directory (avoids credential-helper TCC dialogs).
    public static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPathDirs + [currentPath]).joined(separator: ":")

        // Use isolated Docker config to avoid credential helper triggering TCC permission dialogs
        let dockerConfigDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-launcher/.docker")
        env["DOCKER_CONFIG"] = dockerConfigDir.path

        return env
    }
}
