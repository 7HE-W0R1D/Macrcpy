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

    // ── Input ──────────────────────────────────────────────────────────────
    @AppStorage("forwardKeyboard")     private var forwardKeyboard: Bool = true
    @AppStorage("forwardMouse")        private var forwardMouse: Bool    = false

    // ── Virtual Display & Power ──────────────────────────────────────────────
    @AppStorage("useNewDisplay")       private var useNewDisplay: Bool   = false
    @AppStorage("newDisplaySpec")      private var newDisplaySpec: String = "1920x1080/300"
    @AppStorage("powerOffOnClose")     private var powerOffOnClose: Bool = false

    // ── Recording ──────────────────────────────────────────────────────────
    @AppStorage("autoRecord")          private var autoRecord: Bool      = false
    @AppStorage("recordingPath")       private var recordingPath: String = ""

    // ── Paths (custom overrides) ───────────────────────────────────────────
    @AppStorage("scrcpyBinaryPath")    private var scrcpyBinaryPath: String = ""
    @AppStorage("adbBinaryPath")       private var adbBinaryPath: String    = ""

    var body: some View {
        Form {
            deviceSection
            inputSection
            videoSection
            extraDisplaySection
            audioSection
            recordingSection
            toolsSection
            customPathsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 580)
        .frame(minHeight: 560)
    }

    // MARK: - Device

    private var deviceSection: some View {
        Section("Device") {
            Toggle("Auto-connect to last used device on launch", isOn: $autoConnect)

            LabeledContent("Last Connected") {
                let serial = UserDefaults.standard.string(forKey: "lastConnectedSerial") ?? ""
                Text(serial.isEmpty ? "None" : serial)
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

        }
    }

    // MARK: - Input

    private var inputSection: some View {
        Section("Input") {
            Toggle("Forward Keyboard (-K)", isOn: $forwardKeyboard)
            Toggle("Forward Mouse (-M)", isOn: $forwardMouse)
        }
    }

    // MARK: - Virtual Display & Power

    private var extraDisplaySection: some View {
        Section("Virtual Display & Power") {
            Toggle("Use New Virtual Display", isOn: $useNewDisplay)
            
            if useNewDisplay {
                LabeledContent("Resolution & DPI") {
                    TextField("e.g. 1920x1080/300", text: $newDisplaySpec)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
            }
            
            Toggle("Turn Screen Off on Close", isOn: $powerOffOnClose)
        }
    }

    // MARK: - Video

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

    // MARK: - Audio

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

    // MARK: - Recording

    private var recordingSection: some View {
        Section("Recording") {
            Toggle("Auto-record sessions to file", isOn: $autoRecord)

            if autoRecord {
                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        if recordingPath.isEmpty {
                            Text("Not set").foregroundStyle(.secondary.opacity(0.7))
                        } else {
                            Image(systemName: "folder.fill").foregroundStyle(Color.accentColor).font(.callout)
                            Text(URL(fileURLWithPath: recordingPath).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .leading)
                        }
                        Button("Choose…") { pickFolder { recordingPath = $0.path } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Tools (download / update)

    private var toolsSection: some View {
        let bm = appState.binaries
        return Section {
            // ── scrcpy row ────────────────────────────────────────────────
            LabeledContent("scrcpy") {
                HStack(spacing: 10) {
                    // Installed version
                    Group {
                        if let v = bm.scrcpyInstalled {
                            Text("v\(v)")
                        } else {
                            Text("Not installed").foregroundStyle(.red)
                        }
                    }
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)

                    // Latest badge
                    if let latest = bm.scrcpyLatest {
                        if bm.scrcpyUpdateAvailable {
                            Text("→ \(latest) available")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: Capsule())
                        } else if bm.scrcpyInstalled != nil {
                            Text("Up to date")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Spacer(minLength: 0)

                    if bm.isDownloadingScrcpy {
                        ProgressView().scaleEffect(0.7)
                        Text(bm.scrcpyInstalled == nil ? "Downloading…" : "Updating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(bm.scrcpyInstalled == nil ? "Download" :
                               bm.scrcpyUpdateAvailable ? "Update" : "Reinstall") {
                            bm.downloadScrcpy()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // ── adb row ───────────────────────────────────────────────────
            LabeledContent("adb") {
                HStack(spacing: 10) {
                    Group {
                        if let v = bm.adbInstalled {
                            Text(v)
                        } else {
                            Text("Not installed").foregroundStyle(.red)
                        }
                    }
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if bm.isDownloadingAdb {
                        ProgressView().scaleEffect(0.7)
                        Text(bm.adbInstalled == nil ? "Downloading…" : "Updating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(bm.adbInstalled == nil ? "Download" : "Update") {
                            bm.downloadAdb()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // ── Error banner ──────────────────────────────────────────────
            if let err = bm.downloadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
            }

            // ── Refresh button ────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Check for Updates") {
                    bm.checkForUpdates()
                    bm.refreshInstalledVersions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        } header: {
            Text("Tools")
        } footer: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(bm.binDir.path)
                    .font(.caption)
                    .fontDesign(.monospaced)
            }
            .foregroundStyle(.tertiary)
            .font(.caption)
        }
    }

    // MARK: - Custom Binary Paths (override)

    private var customPathsSection: some View {
        Section {
            binaryPathRow(label: "scrcpy path", path: $scrcpyBinaryPath)
            binaryPathRow(label: "adb path",    path: $adbBinaryPath)
        } header: {
            Text("Custom Paths (optional)")
        } footer: {
            Text("Leave blank to use auto-managed binaries from the Tools section above.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func binaryPathRow(label: String, path: Binding<String>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                if path.wrappedValue.isEmpty {
                    Text("Auto").foregroundStyle(.secondary.opacity(0.6)).font(.callout)
                } else {
                    Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                        .font(.callout)
                }
                Spacer(minLength: 0)
                Button("Browse…") { pickFile { path.wrappedValue = $0.path } }
                    .buttonStyle(.bordered).controlSize(.mini)
                if !path.wrappedValue.isEmpty {
                    Button { path.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain).controlSize(.mini)
                    .help("Clear custom path")
                }
            }
        }
    }

    // MARK: - Helpers

    private func pickFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    private func pickFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }
}
