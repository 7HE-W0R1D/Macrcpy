import Foundation
import Network

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

        // Helper to run `adb connect`
        func runConnect(serial: String) -> String {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: adbPath)
            proc.arguments = ["connect", serial]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }

        // ── 1a. Run adb connect (best-effort, ignore result) ─────────────────
        let output = runConnect(serial: device.serial)
        DispatchQueue.main.async {
            appState.scrcpyOutput += "adb connect → \(output)\n\n"
        }

        // ── 1b. Resolve the best available ADB device ─────────────────────────
        if let target = resolveDevice(preferred: device, adbPath: adbPath) {
            if target.serial != device.serial {
                DispatchQueue.main.async {
                    appState.scrcpyOutput += "→ Using device: \(target.serial)\n\n"
                }
            }
            launch(device: target)
            return
        }

        // ── 1c. Native Port Scan Fallback ──────────────────────────────────────
        let host = device.serial.components(separatedBy: ":").first ?? device.serial

        DispatchQueue.main.async {
            appState.scrcpyOutput += "→ Connection failed. Scanning ports on \(host) natively...\n\n"
        }

        Task {
            let ports = await self.scanPortsNatively(host: host, range: 30000...49999, maxConcurrency: 500)
            
            if ports.isEmpty {
                await MainActor.run {
                    appState.connectionStatus = .failed(message: "No open ports found. Please enter hostname and port manually.")
                }
                return
            }

            let portsToTry = Array(ports.prefix(2))
            await MainActor.run {
                let portsString = portsToTry.map { String($0) }.joined(separator: ", ")
                appState.scrcpyOutput += "→ Found ports: \(portsString)\n"
            }

            var foundTarget: ADBDevice? = nil
            for port in portsToTry {
                let scanSerial = "\(host):\(port)"
                await MainActor.run {
                    appState.scrcpyOutput += "→ Trying port \(port)...\n"
                }
                let out = runConnect(serial: scanSerial)
                await MainActor.run {
                    appState.scrcpyOutput += "adb connect \(port) → \(out)\n\n"
                }

                if let target = self.resolveDevice(preferred: ADBDevice(serial: scanSerial, model: "", connectionType: .tcpip), adbPath: adbPath) {
                    foundTarget = target
                    break
                }
            }

            if let target = foundTarget {
                await MainActor.run {
                    appState.scrcpyOutput += "→ Successfully connected to \(target.serial)\n\n"
                }
                self.launch(device: target)
            } else {
                await MainActor.run {
                    appState.connectionStatus = .failed(message: "Could not connect to any open port. Please enter hostname and port manually.")
                }
            }
        }
    }

    // MARK: - Native Port Scanner
    
    private class ScanState: @unchecked Sendable {
        var isFinished = false
        let lock = NSLock()
    }

    private func scanPortsNatively(host: String, range: ClosedRange<UInt16>, maxConcurrency: Int) async -> [UInt16] {
        var openPorts: [UInt16] = []
        
        await withTaskGroup(of: (UInt16, Bool).self) { group in
            var index = range.lowerBound
            
            for _ in 0..<min(maxConcurrency, range.count) {
                let port = index
                group.addTask { return (port, await self.checkPort(host: host, port: port)) }
                if index == range.upperBound { break }
                index += 1
            }
            
            for await (port, isOpen) in group {
                if isOpen {
                    openPorts.append(port)
                    if openPorts.count >= 2 {
                        group.cancelAll()
                        break
                    }
                }
                
                if index <= range.upperBound, !group.isCancelled {
                    let port = index
                    group.addTask { return (port, await self.checkPort(host: host, port: port)) }
                    index += 1
                }
            }
        }
        return openPorts.sorted()
    }

    private func checkPort(host: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            let hostEndpoint = NWEndpoint.Host(host)
            guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: .tcp)
            
            let state = ScanState()
            
            connection.stateUpdateHandler = { newState in
                state.lock.lock()
                if state.isFinished {
                    state.lock.unlock()
                    return
                }
                switch newState {
                case .ready:
                    state.isFinished = true
                    state.lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed(_), .cancelled:
                    state.isFinished = true
                    state.lock.unlock()
                    continuation.resume(returning: false)
                default:
                    state.lock.unlock()
                }
            }
            
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                state.lock.lock()
                if state.isFinished {
                    state.lock.unlock()
                    return
                }
                state.isFinished = true
                state.lock.unlock()
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    /// Runs `adb devices` and returns the best serial to use.
    ///
    /// Priority:
    ///   1. `preferred.serial` if it appears in the device list
    ///   2. The only connected device (any type) as a fallback
    ///   3. `nil` if nothing was found
    private func resolveDevice(preferred: ADBDevice, adbPath: String) -> ADBDevice? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.arguments     = ["devices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        guard (try? proc.run()) != nil else { return nil }
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

        // Multiple devices but none match
        return nil
    }

    // MARK: - Step 2: scrcpy

    private func launch(device: ADBDevice) {
        guard let appState = appState else { return }

        let scrcpyPath = appState.resolvedScrcpyPath()
        let defaults   = UserDefaults.standard

        // ── Build argument list ───────────────────────────────────────────────
        var args: [String] = ["-s", device.serial]

        // Input
        let forwardKeyboard = defaults.object(forKey: "forwardKeyboard") as? Bool ?? true
        if forwardKeyboard { args.append("-K") }

        let forwardMouse = defaults.bool(forKey: "forwardMouse")
        if forwardMouse { args.append("-M") }

        // Virtual Display & Power
        let useNewDisplay = defaults.bool(forKey: "useNewDisplay")
        if useNewDisplay {
            let spec = defaults.string(forKey: "newDisplaySpec") ?? "1920x1080/300"
            let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSpec.isEmpty {
                args.append("--new-display=\(trimmedSpec)")
            } else {
                args.append("--new-display")
            }
        }

        let powerOffOnClose = defaults.bool(forKey: "powerOffOnClose")
        if powerOffOnClose {
            args.append("--power-off-on-close")
        }

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
