import SwiftUI
import Combine

// MARK: - ADB Device

struct ADBDevice: Identifiable, Equatable, Hashable {
    /// Serial number doubles as unique ID.
    var id: String { serial }
    let serial: String
    let model: String
    let connectionType: ConnectionType

    enum ConnectionType: Equatable {
        case usb
        case tcpip

        var label: String {
            switch self {
            case .usb:   return "USB"
            case .tcpip: return "Wi-Fi"
            }
        }

        var systemImage: String {
            switch self {
            case .usb:   return "cable.connector"
            case .tcpip: return "wifi"
            }
        }
    }

    /// Human-readable name (model if available, otherwise serial).
    var displayName: String {
        model.isEmpty ? serial : model
    }

    /// Shortened serial for display.
    var shortSerial: String {
        serial.count > 14
            ? String(serial.prefix(6)) + "…" + String(serial.suffix(4))
            : serial
    }

    static func == (lhs: ADBDevice, rhs: ADBDevice) -> Bool { lhs.serial == rhs.serial }
    func hash(into hasher: inout Hasher) { hasher.combine(serial) }
}

// MARK: - Connection Status

enum ConnectionStatus {
    case idle
    case connecting
    case scanning
    case running(device: ADBDevice)
    case failed(message: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        if case .scanning = self { return true }
        return false
    }

    var runningDevice: ADBDevice? {
        if case .running(let d) = self { return d }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let m) = self { return m }
        return nil
    }

    var animationTag: String {
        switch self {
        case .idle:             return "idle"
        case .connecting:       return "connecting"
        case .scanning:         return "scanning"
        case .running(let d):   return "running-\(d.serial)"
        case .failed:           return "failed"
        }
    }
}

// MARK: - AppState

/// Central runtime state. Settings are stored in UserDefaults and read on demand
/// by managers; views read them via @AppStorage.
class AppState: ObservableObject {

    // MARK: Published runtime state
    @Published var connectedDevices: [ADBDevice] = []
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var scrcpyOutput: String = ""

    // MARK: Managers (set up in init to avoid circular references)
    let binaries     = BinaryManager()
    var adbManager:   ADBManager!
    var scrcpyManager: ScrcpyManager!

    init() {
        adbManager    = ADBManager(appState: self)
        scrcpyManager = ScrcpyManager(appState: self)
        binaries.refreshInstalledVersions()
        binaries.checkForUpdates()
    }

    // MARK: Tool path resolution (delegated to BinaryManager)

    func resolvedScrcpyPath() -> String { binaries.scrcpyPath() }
    func resolvedAdbPath()    -> String { binaries.adbPath() }

    var isScrcpyAvailable: Bool { binaries.isScrcpyAvailable }
    var isAdbAvailable:    Bool { binaries.isAdbAvailable }
}
