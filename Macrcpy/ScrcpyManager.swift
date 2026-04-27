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

        // ── 1c. Historical & Nmap Scan Fallback ───────────────────────────────
        let host = device.serial.components(separatedBy: ":").first ?? device.serial

        Task {
            var foundTarget: ADBDevice? = nil
            
            // Try historical ports first
            let history = self.getHistoricalPorts(host: host)
            if !history.isEmpty {
                await MainActor.run {
                    appState.scrcpyOutput += "→ Connection failed. Trying historical ports: \(history.map { String($0) }.joined(separator: ", "))...\n\n"
                }
                
                for port in history {
                    let scanSerial = "\(host):\(port)"
                    await MainActor.run {
                        appState.scrcpyOutput += "→ Trying historical port \(port)...\n"
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
            }
            
            if let target = foundTarget {
                await MainActor.run {
                    appState.scrcpyOutput += "→ Successfully connected to \(target.serial)\n\n"
                }
                let portStr = target.serial.components(separatedBy: ":").last ?? ""
                if let port = UInt16(portStr) {
                    self.saveHistoricalPort(host: host, port: port)
                }
                self.launch(device: target)
                return
            }
            
            // Fallback to nmap scan
            await MainActor.run {
                appState.connectionStatus = .scanning
                appState.scrcpyOutput += "→ Historical ports failed. Scanning ports on \(host) with nmap (this may take up to 90 seconds)...\n\n"
            }
            
            let ports = await self.scanPortsWithNmap(host: host)
            
            if ports.isEmpty {
                await MainActor.run {
                    appState.connectionStatus = .failed(message: "No open ports found via nmap. Please enter hostname and port manually.")
                }
                return
            }

            let portsToTry = Array(ports.prefix(2))
            await MainActor.run {
                let portsString = portsToTry.map { String($0) }.joined(separator: ", ")
                appState.scrcpyOutput += "→ Found open ports: \(portsString)\n"
            }

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
                let portStr = target.serial.components(separatedBy: ":").last ?? ""
                if let port = UInt16(portStr) {
                    self.saveHistoricalPort(host: host, port: port)
                }
                self.launch(device: target)
            } else {
                await MainActor.run {
                    appState.connectionStatus = .failed(message: "Could not connect to any open port. Please enter hostname and port manually.")
                }
            }
        }
    }

    // MARK: - Nmap Port Scanner & History
    
    private func getHistoricalPorts(host: String) -> [UInt16] {
        let dict = UserDefaults.standard.dictionary(forKey: "historicalPorts") as? [String: [UInt16]] ?? [:]
        return dict[host] ?? []
    }

    private func saveHistoricalPort(host: String, port: UInt16) {
        var dict = UserDefaults.standard.dictionary(forKey: "historicalPorts") as? [String: [UInt16]] ?? [:]
        var ports = dict[host] ?? []
        ports.removeAll { $0 == port }
        ports.insert(port, at: 0)
        if ports.count > 5 { ports = Array(ports.prefix(5)) }
        dict[host] = ports
        UserDefaults.standard.set(dict, forKey: "historicalPorts")
    }

    private func resolvedNmapPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/nmap",  // Homebrew on Apple Silicon
            "/usr/local/bin/nmap",     // Homebrew on Intel
            "/opt/local/bin/nmap",     // MacPorts
            "/usr/bin/nmap",           // system fallback
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func scanPortsWithNmap(host: String) async -> [UInt16] {
        guard let nmapPath = resolvedNmapPath() else {
            await MainActor.run {
                appState?.scrcpyOutput += "→ nmap not found. Install it via: brew install nmap\n"
            }
            return []
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nmapPath)
        proc.arguments = ["-p", "30000-49999", host]
        proc.environment = ProcessInfo.processInfo.environment
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            var openPorts: [UInt16] = []
            
            for line in output.components(separatedBy: .newlines) {
                if line.contains("/tcp") && line.contains("open") {
                    if let portStr = line.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces),
                       let port = UInt16(portStr) {
                        openPorts.append(port)
                    }
                }
            }
            return openPorts
        } catch {
            print("Nmap error: \(error)")
            return []
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
            let resolution = defaults.string(forKey: "newDisplayResolution") ?? ""
            let dpi        = defaults.string(forKey: "newDisplayDpi") ?? ""
            let trimRes = resolution.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimDpi = dpi.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimRes.isEmpty {
                let spec = trimDpi.isEmpty ? trimRes : "\(trimRes)/\(trimDpi)"
                args.append("--new-display=\(spec)")
            } else {
                args.append("--new-display")
            }
        }

        let turnScreenOff = defaults.bool(forKey: "turnScreenOff")
        if turnScreenOff { args.append("-S") }

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
