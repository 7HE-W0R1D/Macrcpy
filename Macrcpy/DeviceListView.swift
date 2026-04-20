import SwiftUI

/// Shown when one or more devices are detected but none is connected yet.
struct DeviceListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack {
                Text("Available Devices")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(appState.connectedDevices.count) found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // ── Device List ───────────────────────────────────────────────────
            List(appState.connectedDevices) { device in
                DeviceRowView(device: device)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color(NSColor.separatorColor).opacity(0.5))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Device Row

struct DeviceRowView: View {
    let device: ADBDevice
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    private var accentColor: Color {
        device.connectionType == .usb ? .orange : .blue
    }

    var body: some View {
        HStack(spacing: 14) {

            // ── Icon ──────────────────────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "iphone")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(accentColor)
            }

            // ── Info ──────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    // Connection type pill
                    Label(device.connectionType.label, systemImage: device.connectionType.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.12), in: Capsule())

                    // Serial
                    Text(device.shortSerial)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // ── Connect Button ────────────────────────────────────────────────
            Button {
                appState.scrcpyManager.connect(device: device)
            } label: {
                Text("Connect")
                    .fontWeight(.semibold)
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.07) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
