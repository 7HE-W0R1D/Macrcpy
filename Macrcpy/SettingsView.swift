import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var showLog = false

    // ── Device ─────────────────────────────────────────────────────────────
    @AppStorage("autoConnect")         private var autoConnect: Bool   = true

    // ── Video ──────────────────────────────────────────────────────────────
    @AppStorage("maxResolution")       private var maxResolution: Int    = 1080
    @AppStorage("maxBitrateMbps")      private var maxBitrateMbps: Double = 8.0
    @AppStorage("maxFps")              private var maxFps: Int            = 60
    @AppStorage("videoCodec")          private var videoCodec: String    = "h264"

    // ── Audio ──────────────────────────────────────────────────────────────
    @AppStorage("forwardAudio")        private var forwardAudio: Bool    = true
    @AppStorage("audioBitrateKbps")    private var audioBitrateKbps: Int = 128

    // ── Input ──────────────────────────────────────────────────────────────
    @AppStorage("forwardKeyboard")     private var forwardKeyboard: Bool = true
    @AppStorage("forwardMouse")        private var forwardMouse: Bool    = false

    // ── Virtual Display & Power ──────────────────────────────────────────────
    @AppStorage("useNewDisplay")         private var useNewDisplay: Bool    = false
    @AppStorage("newDisplayResolution")  private var newDisplayResolution: String = "1920x1080"
    @AppStorage("newDisplayDpi")         private var newDisplayDpi: String  = ""
    @AppStorage("flexDisplay")           private var flexDisplay: Bool      = false
    @AppStorage("powerOffOnClose")       private var powerOffOnClose: Bool  = false
    @AppStorage("turnScreenOff")         private var turnScreenOff: Bool    = false
    @AppStorage("keepActive")            private var keepActive: Bool       = false
    @AppStorage("noWindowAspectRatioLock") private var noWindowAspectRatioLock: Bool = false
    @AppStorage("autoLockOnDisconnect")  private var autoLockOnDisconnect: Bool = false
    @AppStorage("displayImePolicyLocal") private var displayImePolicyLocal: Bool = true

    // ── Recording ──────────────────────────────────────────────────────────
    @AppStorage("autoRecord")          private var autoRecord: Bool      = false
    @AppStorage("recordingPath")       private var recordingPath: String = ""

    // ── Paths (custom overrides) ───────────────────────────────────────────
    @AppStorage("scrcpyBinaryPath")    private var scrcpyBinaryPath: String = ""
    @AppStorage("adbBinaryPath")       private var adbBinaryPath: String    = ""

    private let commonBitrates: [Double] = [2, 4, 8, 12, 16, 24, 32, 48, 64]

    var body: some View {
        Form {
            deviceSection
            inputSection
            videoSection
            powerSection
            audioSection
            recordingSection
            toolsSection
            customPathsSection
            logSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 580)
        .frame(minHeight: 560)
    }

    // MARK: - Log

    private var logSection: some View {
        Section("Log") {
            Button(showLog ? "Hide Log" : "Show Log") {
                withAnimation { showLog.toggle() }
            }
            if showLog {
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
                    .frame(height: 200)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: appState.scrcpyOutput) { _, _ in
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
                .padding(.top, 4)
            }
        }
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

    // MARK: - Video & Virtual Display

    private var videoSection: some View {
        Section("Video & Virtual Display") {
            Toggle("Use New Virtual Display", isOn: $useNewDisplay)

            LabeledContent("Resolution") {
                if useNewDisplay {
                    Picker("", selection: $newDisplayResolution) {
                        Text("1080p (1920x1080)").tag("1920x1080")
                        Text("2K (2560x1440)").tag("2560x1440")
                        Text("4K (3840x2160)").tag("3840x2160")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                } else {
                    Text("Native Resolution")
                        .foregroundStyle(.secondary)
                }
            }

            if useNewDisplay {
                LabeledContent("Text Size") {
                    HStack(spacing: 8) {
                        Text("Larger Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Slider(value: Binding(
                            get: {
                                if let dpiInt = Int(newDisplayDpi) {
                                    let dpis = [320, 280, 240, 200, 160]
                                    return Double(dpis.firstIndex(of: dpiInt) ?? 2)
                                }
                                return 2.0
                            },
                            set: { newVal in
                                let dpis = [320, 280, 240, 200, 160]
                                let index = Int(newVal.rounded())
                                let selectedDpi = dpis[index]
                                newDisplayDpi = "\(selectedDpi)"
                            }
                        ), in: 0...4, step: 1)
                        .frame(width: 150)
                        
                        Text("More Space")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Dynamic Resizing (--flex-display)", isOn: $flexDisplay)
                Toggle("Show Input Candidates locally on Virtual Display", isOn: $displayImePolicyLocal)
            }

            LabeledContent("Bit Rate") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: {
                            let index = commonBitrates.firstIndex(of: maxBitrateMbps) ?? 2 // Default to 8 (index 2)
                            return Double(index)
                        },
                        set: { newVal in
                            let index = Int(newVal.rounded())
                            if index >= 0 && index < commonBitrates.count {
                                maxBitrateMbps = commonBitrates[index]
                            }
                        }
                    ), in: 0...Double(commonBitrates.count - 1), step: 1)
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

            LabeledContent("Video Codec") {
                Picker("", selection: $videoCodec) {
                    Text("H.264 (default)").tag("h264")
                    Text("H.265 (HEVC)").tag("h265")
                    Text("AV1").tag("av1")
                }
                .labelsHidden()
                .frame(width: 120)
            }

            Toggle("Unlock Window Aspect Ratio (--no-window-aspect-ratio-lock)", isOn: $noWindowAspectRatioLock)
        }
    }

    // MARK: - Power

    private var powerSection: some View {
        Section("Power") {
            Toggle("Prevent Device Sleeping (--keep-active)", isOn: $keepActive)
            Toggle("Turn Screen Off when Connected (-S)", isOn: $turnScreenOff)
            Toggle("Turn Screen Off on Close", isOn: $powerOffOnClose)
            Toggle("Auto-Lock Screen on Disconnect (via ADB)", isOn: $autoLockOnDisconnect)
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
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        } else if bm.scrcpyInstalled != nil {
                            Text("Up to date")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Spacer(minLength: 0)

                    if bm.isDownloadingScrcpy {
                        Text(bm.scrcpyInstalled == nil ? "Downloading…" : "Updating…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(bm.scrcpyInstalled == nil ? "Download" :
                               bm.scrcpyUpdateAvailable ? "Update" : "Reinstall") {
                            bm.downloadScrcpy()
                        }
                        .buttonStyle(.bordered)
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
                        Text(bm.adbInstalled == nil ? "Downloading…" : "Updating…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(bm.adbInstalled == nil ? "Download" : "Update") {
                            bm.downloadAdb()
                        }
                        .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
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

#Preview {
    let _ = UserDefaults.standard.set(true, forKey: "useNewDisplay")
    return SettingsView()
        .environmentObject(AppState())
}
