import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    // ── Device ─────────────────────────────────────────────────────────────
    @AppStorage("autoConnect")         private var autoConnect: Bool   = true

    // ── Video ──────────────────────────────────────────────────────────────
    @AppStorage("maxResolution")       private var maxResolution: Int    = 1080
    @AppStorage("maxBitrateMbps")      private var maxBitrateMbps: Double = 8.0
    @AppStorage("maxFps")              private var maxFps: Int            = 60

    // ── Audio ──────────────────────────────────────────────────────────────
    @AppStorage("forwardAudio")        private var forwardAudio: Bool    = true
    @AppStorage("audioBitrateKbps")    private var audioBitrateKbps: Int = 128

    // ── Connection ─────────────────────────────────────────────────────────
    @AppStorage("preferWireless")      private var preferWireless: Bool  = false
    @AppStorage("tcpPort")             private var tcpPort: Int           = 5555

    // ── Recording ──────────────────────────────────────────────────────────
    @AppStorage("autoRecord")          private var autoRecord: Bool      = false
    @AppStorage("recordingPath")       private var recordingPath: String = ""

    // ── Paths ──────────────────────────────────────────────────────────────
    @AppStorage("scrcpyBinaryPath")    private var scrcpyBinaryPath: String = ""
    @AppStorage("adbBinaryPath")       private var adbBinaryPath: String    = ""

    var body: some View {
        Form {
            deviceSection
            videoSection
            audioSection
            connectionSection
            recordingSection
            binariesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 580)
        .frame(minHeight: 540)
    }

    // MARK: - Sections

    private var deviceSection: some View {
        Section("Device") {
            Toggle("Auto-connect to last used device", isOn: $autoConnect)

            LabeledContent("Last Connected") {
                let serial = UserDefaults.standard.string(forKey: "lastConnectedSerial") ?? ""
                Text(serial.isEmpty ? "None" : serial)
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var videoSection: some View {
        Section("Video") {
            LabeledContent("Max Resolution") {
                Picker("", selection: $maxResolution) {
                    Text("480p").tag(480)
                    Text("720p").tag(720)
                    Text("1080p").tag(1080)
                    Text("1440p").tag(1440)
                    Text("4K").tag(2160)
                }
                .labelsHidden()
                .frame(width: 110)
            }

            LabeledContent("Bit Rate") {
                HStack(spacing: 10) {
                    Slider(value: $maxBitrateMbps, in: 1...20, step: 1)
                        .frame(width: 140)
                    Text("\(Int(maxBitrateMbps)) Mbps")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }

            LabeledContent("Frame Rate") {
                Picker("", selection: $maxFps) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Toggle("Forward device audio to Mac", isOn: $forwardAudio)

            if forwardAudio {
                LabeledContent("Audio Bit Rate") {
                    Picker("", selection: $audioBitrateKbps) {
                        Text("64 kbps").tag(64)
                        Text("96 kbps").tag(96)
                        Text("128 kbps").tag(128)
                        Text("192 kbps").tag(192)
                        Text("256 kbps").tag(256)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            Toggle("Prefer wireless (Wi-Fi) devices", isOn: $preferWireless)

            LabeledContent("TCP/IP Port") {
                TextField("Port", value: $tcpPort, format: .number)
                    .frame(width: 68)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var recordingSection: some View {
        Section("Recording") {
            Toggle("Auto-record sessions to file", isOn: $autoRecord)

            if autoRecord {
                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        if recordingPath.isEmpty {
                            Text("Not set")
                                .foregroundStyle(.secondary.opacity(0.7))
                        } else {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.callout)
                            Text(URL(fileURLWithPath: recordingPath).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .leading)
                        }

                        Button("Choose…") {
                            pickFolder { recordingPath = $0.path }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var binariesSection: some View {
        Section {
            binaryRow(
                label: "scrcpy",
                path: $scrcpyBinaryPath,
                isDetected: appState.isScrcpyAvailable
            )
            binaryRow(
                label: "adb",
                path: $adbBinaryPath,
                isDetected: appState.isAdbAvailable
            )

            if !appState.isScrcpyAvailable || !appState.isAdbAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.callout)
                    Text("Install missing tools: **brew install scrcpy**")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tool Paths")
        } footer: {
            Text("Leave blank to use the auto-detected Homebrew binaries.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Reusable Binary Row

    @ViewBuilder
    private func binaryRow(
        label: String,
        path: Binding<String>,
        isDetected: Bool
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Image(systemName: isDetected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isDetected ? .green : .red)
                    .font(.callout)

                Group {
                    if path.wrappedValue.isEmpty {
                        Text(isDetected ? "Auto-detected" : "Not found")
                            .foregroundStyle(isDetected ? Color.secondary : Color.red)
                    } else {
                        Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
                .font(.callout)

                Spacer(minLength: 0)

                Button("Browse…") {
                    pickFile { path.wrappedValue = $0.path }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                if !path.wrappedValue.isEmpty {
                    Button {
                        path.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.mini)
                    .help("Clear custom path")
                }
            }
        }
    }

    // MARK: - Panel Helpers

    private func pickFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories  = true
        panel.canChooseFiles        = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    private func pickFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = true
        panel.canChooseDirectories  = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }
}
