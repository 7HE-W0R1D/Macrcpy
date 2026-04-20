import Foundation

/// Manages the scrcpy child process lifecycle.
///
/// Wireless flow (TCP/IP devices):
///   1. `adb connect <ip>:<port>`  — best-effort TCP connect (ignored if it fails)
///   2. `adb devices`              — resolve the real serial to use
///   3. `scrcpy -K -s <serial>`   — mirror with keyboard forwarding
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
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.adbConnect(device: device)
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.launch(device: device)
            }
        }
    }

    func disconnect() {
        process?.terminate()
        if process == nil { cleanup() }
    }

    // MARK: - Step 1: adb connect + device resolution

    private func adbConnect(device: ADBDevice) {
        guard let appState = appState else { return }

        let adbPath = appState.resolvedAdbPath()

        // ── 1a. Run adb connect (best-effort, ignore result) ─────────────────
        let connectProc = Process()
        connectProc.executableURL = URL(fileURLWithPath: adbPath)
        connectProc.arguments     = ["connect", device.serial]
        let connectPipe = Pipe()
        connectProc.standardOutput = connectPipe
        connectProc.standardError  = connectPipe

        do {
            try connectProc.run()
            connectProc.waitUntilExit()
            let data   = connectPipe.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: data, encoding: .utf8) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                appState.scrcpyOutput += "adb connect → \(output)\n\n"
            }
        } catch {
            DispatchQueue.main.async {
                appState.scrcpyOutput += "adb connect error: \(error.localizedDescription)\n\n"
            }
        }

        // ── 1b. Resolve the best available ADB device ─────────────────────────
        // Prefer user's serial if it shows up in `adb devices`.
        // Fall back to the only connected device (handles ADB-TLS, USB, etc.)
        let target = resolveDevice(preferred: device, adbPath: adbPath)

        if target.serial != device.serial {
            DispatchQueue.main.async {
                appState.scrcpyOutput += "→ Using device: \(target.serial)\n\n"
            }
        }

        // ── 1c. Launch scrcpy ─────────────────────────────────────────────────
        launch(device: target)
    }

    /// Runs `adb devices` and returns the best serial to use.
    ///
    /// Priority:
    ///   1. `preferred.serial` if it appears in the device list
    ///   2. The only connected device (any type) as a fallback
    ///   3. `preferred` unchanged if nothing was found
    private func resolveDevice(preferred: ADBDevice, adbPath: String) -> ADBDevice {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments     = ["devices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        guard (try? proc.run()) != nil else { return preferred }
        proc.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        // Each "device" line is: "<serial>\tdevice"
        var found: [String] = []
        for line in output.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 2,
                  cols[1].trimmingCharacters(in: .whitespaces) == "device" else { continue }
            let serial = cols[0].trimmingCharacters(in: .whitespaces)
            guard !serial.isEmpty else { continue }
            found.append(serial)
        }

        // Preferred serial is directly available
        if found.contains(preferred.serial) { return preferred }

        // Exactly one device available — use it regardless of type
        if found.count == 1 {
            let s   = found[0]
            let tcp = s.contains(":") || s.hasPrefix("adb-")   // ip:port or ADB-TLS mDNS
            return ADBDevice(serial: s, model: "", connectionType: tcp ? .tcpip : .usb)
        }

        // Multiple devices but none match — pass preferred and let scrcpy report
        return preferred
    }

    // MARK: - Step 2: scrcpy

    private func launch(device: ADBDevice) {
        guard let appState = appState else { return }

        let scrcpyPath = appState.resolvedScrcpyPath()
        let defaults   = UserDefaults.standard

        // ── Build argument list ───────────────────────────────────────────────
        var args: [String] = ["-s", device.serial]

        // Keyboard forwarding (-K)
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

        // Inject ADB path — scrcpy uses the ADB env var for all internal adb calls.
        // Also extend PATH so any adb sub-process can be found.
        var env = ProcessInfo.processInfo.environment
        env["ADB"]  = appState.resolvedAdbPath()
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(env["PATH"] ?? "/usr/bin:/bin")"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        self.process    = proc
        self.outputPipe = pipe

        // Track whether scrcpy produced any output
        var hadOutput = false

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            hadOutput = true
            DispatchQueue.main.async {
                guard let appState = self?.appState else { return }
                appState.scrcpyOutput += str
                if appState.scrcpyOutput.count > 8_000 {
                    appState.scrcpyOutput = String(appState.scrcpyOutput.suffix(8_000))
                }
            }
        }

        // Only report failure if scrcpy produced zero output (launch-level error)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                if hadOutput {
                    self?.cleanup()   // normal exit — log already visible
                } else {
                    self?.appState?.connectionStatus = .failed(
                        message: "scrcpy exited with no output.\nCheck that scrcpy is installed and the device is reachable."
                    )
                    self?.cleanupProcess()
                }
            }
        }

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

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process    = nil
        outputPipe = nil
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
