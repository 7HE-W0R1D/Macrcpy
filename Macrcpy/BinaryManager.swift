import Foundation
import Combine

// MARK: - BinaryManager

/// Manages the scrcpy and adb binaries stored in Application Support.
/// Handles path resolution, version detection, and GitHub-based updates.
final class BinaryManager: ObservableObject {

    // ── Published state ───────────────────────────────────────────────────────
    @Published var scrcpyInstalled: String?    // installed version string, nil = not found
    @Published var adbInstalled: String?
    @Published var scrcpyLatest: String?       // latest tag from GitHub, nil = unknown
    @Published var isDownloadingScrcpy = false
    @Published var isDownloadingAdb    = false
    @Published var downloadError: String?

    // ── Storage location ──────────────────────────────────────────────────────
    var binDir: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Macrcpy/bin", isDirectory: true)
    }

    // ── Path Resolution ───────────────────────────────────────────────────────
    // Priority: userDefault custom → App Support → Homebrew → fallback name

    func scrcpyPath() -> String { resolvedPath(name: "scrcpy", defaultsKey: "scrcpyBinaryPath") }
    func adbPath()    -> String { resolvedPath(name: "adb",    defaultsKey: "adbBinaryPath") }

    private func resolvedPath(name: String, defaultsKey: String) -> String {
        // 1. Custom user path
        let custom = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        if !custom.isEmpty, FileManager.default.fileExists(atPath: custom) { return custom }

        // 2. App Support (downloaded by Macrcpy)
        let appSupportPath = binDir.appendingPathComponent(name).path
        if FileManager.default.fileExists(atPath: appSupportPath) { return appSupportPath }

        // 3. Homebrew / system
        for prefix in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let p = "\(prefix)/\(name)"
            if FileManager.default.fileExists(atPath: p) { return p }
        }

        return name   // fallback: hope it's on PATH
    }

    var isScrcpyAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: scrcpyPath())
    }
    var isAdbAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: adbPath())
    }

    // ── Installed version detection ───────────────────────────────────────────

    func refreshInstalledVersions() {
        Task.detached {
            let sv = await self.runVersion(path: self.scrcpyPath(), args: ["--version"])
            let av = await self.runVersion(path: self.adbPath(),    args: ["version"])
            await MainActor.run {
                self.scrcpyInstalled = self.parseScrcpyVersion(sv)
                self.adbInstalled    = self.parseAdbVersion(av)
            }
        }
    }

    private func runVersion(path: String, args: [String]) async -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments     = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        guard (try? proc.run()) != nil else { return "" }
        proc.waitUntilExit()
        return String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
    }

    private func parseScrcpyVersion(_ s: String) -> String? {
        // "scrcpy 3.3.4 <https://…>" → "3.3.4"
        guard !s.isEmpty else { return nil }
        let parts = s.components(separatedBy: " ")
        return parts.count >= 2 ? parts[1] : parts.first
    }

    private func parseAdbVersion(_ s: String) -> String? {
        // "Android Debug Bridge version 1.0.41" → "1.0.41"
        guard !s.isEmpty else { return nil }
        for line in s.components(separatedBy: "\n") {
            if line.contains("Android Debug Bridge version") {
                return line.components(separatedBy: " ").last
            }
        }
        return s.components(separatedBy: "\n").first
    }

    // ── Update check (GitHub API) ────────────────────────────────────────────

    func checkForUpdates() {
        Task {
            guard let tag = try? await fetchLatestScrcpyTag() else { return }
            await MainActor.run { self.scrcpyLatest = tag }
        }
    }

    private func fetchLatestScrcpyTag() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/Genymobile/scrcpy/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["tag_name"] as? String) ?? "unknown"
    }

    /// True when a newer scrcpy version is available.
    var scrcpyUpdateAvailable: Bool {
        guard let installed = scrcpyInstalled,
              let latest    = scrcpyLatest else { return false }
        let latestClean = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
        return latestClean != installed
    }

    // ── Download: scrcpy ─────────────────────────────────────────────────────

    func downloadScrcpy() {
        guard !isDownloadingScrcpy else { return }
        isDownloadingScrcpy = true
        downloadError = nil

        Task {
            do {
                let tag = try await fetchLatestScrcpyTag()
                let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

                // Pick architecture-appropriate asset
                #if arch(arm64)
                let arch = "aarch64"
                #else
                let arch = "x86_64"
                #endif
                let assetName = "scrcpy-macos-\(arch)-v\(ver).tar.gz"
                let urlStr    = "https://github.com/Genymobile/scrcpy/releases/download/\(tag)/\(assetName)"

                guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

                let (tmpURL, _) = try await URLSession.shared.download(from: url)
                try self.ensureBinDir()
                try self.extractTarGz(from: tmpURL, to: self.binDir)
                try? FileManager.default.removeItem(at: tmpURL)
                self.makeExecutable(self.binDir.appendingPathComponent("scrcpy"))
                self.makeExecutable(self.binDir.appendingPathComponent("scrcpy-server"))

                await MainActor.run {
                    self.isDownloadingScrcpy = false
                    self.refreshInstalledVersions()
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingScrcpy = false
                    self.downloadError = "scrcpy download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── Download: adb ────────────────────────────────────────────────────────

    func downloadAdb() {
        guard !isDownloadingAdb else { return }
        isDownloadingAdb = true
        downloadError    = nil

        Task {
            do {
                let urlStr = "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
                guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

                let (tmpURL, _) = try await URLSession.shared.download(from: url)
                try self.ensureBinDir()

                // Extract only the adb binary from the zip
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("macrcpy-pt-\(UUID().uuidString)")
                try FileManager.default.createDirectory(
                    at: tmpDir, withIntermediateDirectories: true)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments     = ["-q", tmpURL.path, "platform-tools/adb", "-d", tmpDir.path]
                try unzip.run(); unzip.waitUntilExit()

                let src  = tmpDir.appendingPathComponent("platform-tools/adb")
                let dest = self.binDir.appendingPathComponent("adb")
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
                self.makeExecutable(dest)
                try? FileManager.default.removeItem(at: tmpDir)
                try? FileManager.default.removeItem(at: tmpURL)

                await MainActor.run {
                    self.isDownloadingAdb = false
                    self.refreshInstalledVersions()
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingAdb = false
                    self.downloadError = "adb download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func ensureBinDir() throws {
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
    }

    private func extractTarGz(from tarURL: URL, to destDir: URL) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        // --strip-components=1 removes the top-level "scrcpy-macos-aarch64-v3.x.x/" folder
        tar.arguments     = ["xzf", tarURL.path, "--strip-components=1", "-C", destDir.path]
        try tar.run(); tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw NSError(domain: "BinaryManager",
                          code: Int(tar.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "tar exited with \(tar.terminationStatus)"])
        }
    }

    private func makeExecutable(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
