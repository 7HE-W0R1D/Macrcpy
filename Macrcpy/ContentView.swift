import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("autoConnect") private var autoConnect: Bool = true

    @State private var ipInput: String = ""
    @State private var showLog = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {

            // ── IP / hostname input ───────────────────────────────────────────
            TextField("IP or hostname  (e.g. 100.64.x.x)", text: $ipInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .controlSize(.large)
                .onSubmit { performConnect() }
                .disabled(
                    appState.connectionStatus.isRunning ||
                    appState.connectionStatus.isConnecting
                )

            // ── Main button ───────────────────────────────────────────────────
            actionButton

            // ── Log (hidden until there's output; auto-opens on failure) ─────
            if !appState.scrcpyOutput.isEmpty {
                DisclosureGroup(isExpanded: $showLog) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(appState.scrcpyOutput)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                                .id("logBottom")
                        }
                        .frame(height: 140)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: appState.scrcpyOutput) { _, _ in
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 4) {
                        if case .failed = appState.connectionStatus {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Text("Log")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 310)
        .fixedSize()
        .onAppear(perform: onLaunch)
        .onChange(of: appState.connectionStatus.animationTag) { _, tag in
            switch tag {
            case "failed":
                showLog = true
            case "idle":
                showLog = false
            default:
                break
            }
        }
    }

    // MARK: - Launch

    private func onLaunch() {
        // Disable full-screen mode globally for our main application window
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Macrcpy" || $0.canBecomeMain }) {
            window.collectionBehavior.insert(.fullScreenNone)
            window.collectionBehavior.remove(.fullScreenPrimary)
        }

        let saved = UserDefaults.standard.string(forKey: "lastConnectedSerial") ?? ""
        ipInput = stripPort(saved)

        // Auto-connect to the last device if the setting is on
        guard autoConnect, !saved.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            performConnect()
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
        if case .failed = appState.connectionStatus {
            appState.connectionStatus = .idle
        }
        guard case .idle = appState.connectionStatus else { return }

        let raw = ipInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        inputFocused = false
        let serial = hasExplicitPort(raw) ? raw : "\(raw):5555"

        let device = ADBDevice(serial: serial, model: "", connectionType: .tcpip)
        appState.scrcpyManager.connect(device: device)
    }

    // MARK: - Helpers

    private func stripPort(_ serial: String) -> String {
        let parts = serial.components(separatedBy: ":")
        if parts.count == 2, Int(parts[1]) != nil { return parts[0] }
        return serial
    }

    private func hasExplicitPort(_ s: String) -> Bool {
        let parts = s.components(separatedBy: ":")
        return parts.count == 2 && Int(parts[1]) != nil
    }
}
