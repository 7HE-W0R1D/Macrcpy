import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("autoConnect") private var autoConnect: Bool = true

    @State private var ipInput: String = ""
    @State private var portInput: String = ""
    @FocusState private var inputFocused: Bool

    private var nmapAvailable: Bool {
        ["/opt/homebrew/bin/nmap", "/usr/local/bin/nmap", "/opt/local/bin/nmap", "/usr/bin/nmap"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            switch appState.connectionStatus {
            case .idle, .failed:
                inputView
                
            case .connecting:
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.bottom, 4)
                Text("Connecting to your phone...")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    
            case .scanning:
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.bottom, 4)
                Text("Scanning ports... This can take up to 2 minutes")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    
            case .running:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                    .padding(.bottom, 4)
                Text("Connected")
                    .font(.headline)
                
                Button("Disconnect") {
                    appState.scrcpyManager.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(width: 340, height: 200)
        .onAppear(perform: onLaunch)
        .onChange(of: appState.connectionStatus.animationTag) { _, tag in
            switch tag {
            case "failed":
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            default:
                break
            }
        }
    }

    // MARK: - Input View
    
    @ViewBuilder
    private var inputView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("IP Address", text: $ipInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($inputFocused)
                    .onSubmit { performConnect() }
                
                TextField("Port (opt)", text: $portInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 100)
                    .onSubmit { performConnect() }
            }
            .controlSize(.large)
            
            Toggle("Auto-connect next time", isOn: $autoConnect)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)

            if !nmapAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Port scanning requires nmap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install nmap", forType: .string)
                    } label: {
                        Text("brew install nmap")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 2)
            }
            
            Button(action: performConnect) {
                Text("Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
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
        portInput = getPort(saved)

        // Auto-connect to the last device if the setting is on
        guard autoConnect, !saved.isEmpty else { return }
        
        // Immediately perform connect so the state changes to .connecting instantly, avoiding UI flash
        performConnect()
    }

    // MARK: - Connect

    private func performConnect() {
        if case .failed = appState.connectionStatus {
            appState.connectionStatus = .idle
        }
        guard case .idle = appState.connectionStatus else { return }

        let rawIp = ipInput.trimmingCharacters(in: .whitespaces)
        guard !rawIp.isEmpty else { return }

        inputFocused = false
        
        let serial: String
        if hasExplicitPort(rawIp) {
            serial = rawIp
        } else {
            let p = portInput.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty {
                serial = "\(rawIp):\(p)"
            } else {
                serial = "\(rawIp):5555"
            }
        }

        let device = ADBDevice(serial: serial, model: "", connectionType: .tcpip)
        appState.scrcpyManager.connect(device: device)
    }

    // MARK: - Helpers

    private func stripPort(_ serial: String) -> String {
        let parts = serial.components(separatedBy: ":")
        if parts.count == 2, Int(parts[1]) != nil { return parts[0] }
        return serial
    }
    
    private func getPort(_ serial: String) -> String {
        let parts = serial.components(separatedBy: ":")
        if parts.count == 2, Int(parts[1]) != nil { return parts[1] }
        return ""
    }

    private func hasExplicitPort(_ s: String) -> Bool {
        let parts = s.components(separatedBy: ":")
        return parts.count == 2 && Int(parts[1]) != nil
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
