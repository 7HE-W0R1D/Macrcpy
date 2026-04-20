import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var ipInput: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            TextField("IP address  (e.g. 100.64.x.x)", text: $ipInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .controlSize(.large)
                .onSubmit { performConnect() }
                .disabled(
                    appState.connectionStatus.isRunning ||
                    appState.connectionStatus.isConnecting
                )

            actionButton
        }
        .padding(20)
        .frame(width: 310)
        .onAppear {
            // Pre-fill with last-used IP
            ipInput = UserDefaults.standard.string(forKey: "lastConnectedSerial") ?? ""
        }
    }

    // MARK: - Button

    @ViewBuilder
    private var actionButton: some View {
        switch appState.connectionStatus {

        case .idle, .failed:
            Button(action: performConnect) {
                Text("Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

        case .connecting:
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Connecting…")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)

        case .running:
            Button("Disconnect") {
                appState.scrcpyManager.disconnect()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Connect

    private func performConnect() {
        // Allow retrying from failed state
        if case .failed = appState.connectionStatus {
            appState.connectionStatus = .idle
        }
        guard case .idle = appState.connectionStatus else { return }

        let raw = ipInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        inputFocused = false

        // Append default ADB port if user typed bare IP
        let serial = raw.contains(":") ? raw : "\(raw):5555"
        ipInput = serial

        let device = ADBDevice(serial: serial, model: "", connectionType: .tcpip)
        appState.scrcpyManager.connect(device: device)
    }
}
