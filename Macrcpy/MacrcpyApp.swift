import SwiftUI

@main
struct MacrcpyApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("forwardAudio") private var forwardAudio: Bool = true

    var body: some Scene {
        // ── Main window ─────────────────────────────────────────────────────
        WindowGroup("Macrcpy") {
            ContentView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .commands {
            // Replace default About
            CommandGroup(replacing: .appInfo) {
                Button("About Macrcpy") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }

            // ── Device menu ──────────────────────────────────────────────────
            CommandMenu("Device") {
                if appState.connectionStatus.isRunning {
                    Button("Disconnect") {
                        appState.scrcpyManager.disconnect()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                } else {
                    Button("Connect First Device") {
                        if let first = appState.connectedDevices.first {
                            appState.scrcpyManager.connect(device: first)
                        }
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(
                        appState.connectionStatus.isConnecting ||
                        appState.connectedDevices.isEmpty
                    )
                }

                Divider()

                Toggle("Forward Audio", isOn: $forwardAudio)
                    .keyboardShortcut("a", modifiers: [.command, .option])

                Divider()

                Button("Refresh Device List") {
                    appState.adbManager.resetAutoConnect()
                    appState.adbManager.startPolling()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // ── Settings window (⌘,) ────────────────────────────────────────────
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
