import Foundation

/// Polls `adb devices -l` every 2 seconds and updates AppState.
/// Handles automatic reconnection to the last-used device on first appearance.
class ADBManager {

    private weak var appState: AppState?
    private var timer: Timer?
    /// Prevents repeated auto-connect attempts in a single session.
    private var hasAttemptedAutoConnect = false

    init(appState: AppState) {
        self.appState = appState
        // Schedule on the main run loop so AppState can be accessed safely.
        DispatchQueue.main.async { [weak self] in
            self?.startPolling()
        }
    }

    // MARK: - Lifecycle

    func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.triggerPoll()
        }
        // Fire immediately so the UI is populated before the first interval.
        triggerPoll()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Reset so the next device appearance can trigger auto-connect again.
    func resetAutoConnect() {
        hasAttemptedAutoConnect = false
    }

    // MARK: - Polling

    private func triggerPoll() {
        guard let appState = appState else { return }
        let adbPath = appState.resolvedAdbPath()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = ADBManager.fetchDevices(adbPath: adbPath)
            DispatchQueue.main.async {
                self?.handleUpdate(devices: devices)
            }
        }
    }

    private func handleUpdate(devices: [ADBDevice]) {
        guard let appState = appState else { return }
        appState.connectedDevices = devices
        attemptAutoConnect(devices: devices, appState: appState)
    }

    // MARK: - Auto Connect

    private func attemptAutoConnect(devices: [ADBDevice], appState: AppState) {
        guard !hasAttemptedAutoConnect else { return }
        guard UserDefaults.standard.bool(forKey: "autoConnect") else { return }
        guard case .idle = appState.connectionStatus else { return }

        let lastSerial = UserDefaults.standard.string(forKey: "lastConnectedSerial") ?? ""
        guard !lastSerial.isEmpty else { return }

        if let lastDevice = devices.first(where: { $0.serial == lastSerial }) {
            hasAttemptedAutoConnect = true
            appState.scrcpyManager.connect(device: lastDevice)
        }
    }

    // MARK: - ADB Process

    private static func fetchDevices(adbPath: String) -> [ADBDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["devices", "-l"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = Pipe()   // suppress stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data   = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return parseDeviceList(output)
    }

    // MARK: - Output Parsing

    /// Parses the output of `adb devices -l`.
    ///
    /// Format (after the header line):
    /// ```
    /// SERIAL    device  product:xxx model:Pixel_9 device:xxx transport_id:1
    /// 192.0.2.5:5555  device  ...
    /// ```
    private static func parseDeviceList(_ output: String) -> [ADBDevice] {
        var devices: [ADBDevice] = []

        let lines = output
            .components(separatedBy: "\n")
            .dropFirst()    // skip "List of devices attached"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces)
            // second token must be "device" (not offline/unauthorized/etc.)
            guard parts.count >= 2, parts[1] == "device" else { continue }

            let serial = parts[0]

            // Extract the model name from "model:Pixel_9_Pro" tokens.
            var model = ""
            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") {
                    model = String(part.dropFirst("model:".count))
                        .replacingOccurrences(of: "_", with: " ")
                    break
                }
            }

            // TCP/IP devices look like "192.168.1.5:5555".
            let isTcpip = serial.contains(":") &&
                          (serial.components(separatedBy: ":").last.flatMap(Int.init) != nil)

            devices.append(ADBDevice(
                serial: serial,
                model: model,
                connectionType: isTcpip ? .tcpip : .usb
            ))
        }

        return devices
    }
}
