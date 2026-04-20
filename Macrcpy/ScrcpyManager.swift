import Foundation

/// Manages the scrcpy child process lifecycle.
///
/// Wireless flow (TCP/IP devices):
///   1. `adb connect <ip>:<port>`  — establishes the ADB over TCP connection
///   2. `scrcpy -K -s <ip>:<port>` — mirrors the screen with keyboard forwarding
class ScrcpyManager {

    private weak var appState: AppState?
    private var process:    Process?
    private var outputPipe: Pipe?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    func connect(device: ADBDevice) {
        guard let appState = appState else { return }

        UserDefaults.standard.set(device.serial, forKey: "lastConnectedSerial")
        appState.connectionStatus = .connecting
        appState.scrcpyOutput     = ""
        appState.adbManager.resetAutoConnect()

        if device.connectionType == .tcpip {
            // Wireless: adb connect first, then scrcpy
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.adbConnect(device: device)
            }
        } else {
            // USB: jump straight to scrcpy
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.launch(device: device)
            }
        }
    }

    func disconnect() {
        process?.terminate()
        if process == nil { cleanup() }
    }

    // MARK: - Step 1: adb connect (wireless only)

    private func adbConnect(device: ADBDevice) {
        guard let appState = appState else { return }

        let adbPath = appState.resolvedAdbPath()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments     = ["connect", device.serial]   // e.g. ["connect", "100.64.1.1:5555"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            DispatchQueue.main.async {
                appState.connectionStatus = .failed(
                    message: "Could not run adb:\n\(error.localizedDescription)"
                )
            }
            return
        }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async {
            appState.scrcpyOutput = "adb connect → \(output)\n\n"
        }

        // ADB prints "connected to X" or "already connected to X" on success.
        let success = output.lowercased().contains("connected to")
        if success {
            launch(device: device)
        } else {
            DispatchQueue.main.async {
                appState.connectionStatus = .failed(
                    message: "ADB connect failed:\n\(output)"
                )
            }
        }
    }

    // MARK: - Step 2: scrcpy

    private func launch(device: ADBDevice) {
        guard let appState = appState else { return }

        let scrcpyPath = appState.resolvedScrcpyPath()
        let defaults   = UserDefaults.standard

        // ── Build argument list ───────────────────────────────────────────────
        var args: [String] = ["-s", device.serial]

        // Keyboard forwarding (-K) — standard for wireless usage
        args.append("-K")

        // Video
        let resolution  = defaults.integer(forKey: "maxResolution").nonZero  ?? 1080
        let bitrateMbps = defaults.double(forKey: "maxBitrateMbps").nonZero  ?? 8.0
        let fps         = defaults.integer(forKey: "maxFps").nonZero          ?? 60

        args += ["--max-size",       "\(resolution)"]
        args += ["--video-bit-rate", "\(Int(bitrateMbps))M"]
        args += ["--max-fps",        "\(fps)"]

        // Audio
        let audioEnabled = defaults.object(forKey: "forwardAudio") as? Bool ?? true
        if !audioEnabled {
            args.append("--no-audio")
        } else {
            let audioBitrate = defaults.integer(forKey: "audioBitrateKbps").nonZero ?? 128
            args += ["--audio-bit-rate", "\(audioBitrate)k"]
        }

        // Recording
        if defaults.bool(forKey: "autoRecord") {
            let folder = defaults.string(forKey: "recordingPath") ?? ""
            if !folder.isEmpty {
                let filename = "recording_\(Int(Date().timeIntervalSince1970)).mp4"
                let path = (folder as NSString).appendingPathComponent(filename)
                args += ["--record", path]
            }
        }

        // ── Setup process ─────────────────────────────────────────────────────
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: scrcpyPath)
        proc.arguments     = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        self.process    = proc
        self.outputPipe = pipe

        // Stream output
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let appState = self?.appState else { return }
                appState.scrcpyOutput += str
                if appState.scrcpyOutput.count > 8_000 {
                    appState.scrcpyOutput = String(appState.scrcpyOutput.suffix(8_000))
                }
            }
        }

        // Detect exit
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.cleanup() }
        }

        // ── Run ───────────────────────────────────────────────────────────────
        do {
            try proc.run()
            DispatchQueue.main.async {
                appState.connectionStatus = .running(device: device)
            }
        } catch {
            DispatchQueue.main.async {
                appState.connectionStatus = .failed(
                    message: "Could not launch scrcpy:\n\(error.localizedDescription)"
                )
            }
            cleanup()
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process    = nil
        outputPipe = nil
        appState?.connectionStatus = .idle
    }

    deinit { process?.terminate() }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
