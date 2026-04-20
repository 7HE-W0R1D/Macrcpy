import SwiftUI

// MARK: - Connected View

/// Shown while scrcpy is actively running.
struct ConnectedView: View {
    @EnvironmentObject var appState: AppState

    private var device: ADBDevice? { appState.connectionStatus.runningDevice }

    var body: some View {
        VStack(spacing: 0) {
            if let device = device {
                statusBanner(device: device)
                Divider()
            }
            outputLog
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Status Banner

    @ViewBuilder
    private func statusBanner(device: ADBDevice) -> some View {
        HStack(spacing: 16) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.green.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: "iphone")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 5) {
                // Name + live badge
                HStack(spacing: 8) {
                    Text(device.displayName)
                        .font(.system(.headline, design: .default, weight: .bold))

                    LiveBadge()
                }

                // Connection meta
                HStack(spacing: 8) {
                    Label(device.connectionType.label, systemImage: device.connectionType.systemImage)
                        .font(.caption)
                        .foregroundStyle(device.connectionType == .usb ? .orange : .blue)

                    Text("·").foregroundStyle(.tertiary)

                    Text(device.shortSerial)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                appState.scrcpyManager.disconnect()
            } label: {
                Label("Disconnect", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Output Log

    private var outputLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(appState.scrcpyOutput.isEmpty
                     ? "scrcpy is running. Output will appear here…"
                     : appState.scrcpyOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(appState.scrcpyOutput.isEmpty ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .id("bottom")
            }
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.textBackgroundColor).opacity(0.35))
            .onChange(of: appState.scrcpyOutput) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Live Badge

private struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)

            Text("LIVE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.green.opacity(0.12), in: Capsule())
        .onAppear { pulsing = true }
    }
}

// MARK: - Connecting View

struct ConnectingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ProgressView()
                .scaleEffect(1.4)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("Connecting…")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Launching scrcpy — waiting for device response")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button("Cancel") {
                appState.scrcpyManager.disconnect()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Failed View

struct FailedView: View {
    let message: String
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Connection Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .lineSpacing(3)
            }

            Button("Dismiss") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    appState.connectionStatus = .idle
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            Spacer()
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
