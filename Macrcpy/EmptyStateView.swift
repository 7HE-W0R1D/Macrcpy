import SwiftUI

/// Shown when no Android device is detected.
/// Gives the user clear guidance on what to do next.
struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Icon ────────────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(.gray.opacity(0.08))
                        .frame(width: 100, height: 100)

                    Circle()
                        .strokeBorder(.gray.opacity(0.12), lineWidth: 1)
                        .frame(width: 100, height: 100)

                    Image(systemName: appState.isAdbAvailable ? "iphone.slash" : "wrench.and.screwdriver")
                        .font(.system(size: 42, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 28)
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1.0 : 0.0)

                // ── Title ────────────────────────────────────────────────────
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                Spacer().frame(height: 10)

                // ── Subtitle ─────────────────────────────────────────────────
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                Spacer().frame(height: 36)

                // ── Actions ───────────────────────────────────────────────────
                VStack(spacing: 12) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape.fill")
                            .frame(minWidth: 170)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                    if appState.isAdbAvailable {
                        Link(destination: URL(string: "https://github.com/Genymobile/scrcpy#getting-started")!) {
                            HStack(spacing: 4) {
                                Text("How to connect a device")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .opacity(appeared ? 1 : 0)
                    }
                }

                Spacer()
            }
            .padding(48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                appeared = true
            }
        }
        .onDisappear {
            appeared = false
        }
    }

    // MARK: - Computed text

    private var title: String {
        if !appState.isScrcpyAvailable { return "scrcpy Not Found" }
        if !appState.isAdbAvailable    { return "adb Not Found" }
        return "No Device Connected"
    }

    private var subtitle: String {
        if !appState.isScrcpyAvailable {
            return "Install scrcpy via Homebrew (`brew install scrcpy`) or set a custom path in Settings."
        }
        if !appState.isAdbAvailable {
            return "Install Android Platform Tools via Homebrew (`brew install android-platform-tools`) or set a custom path in Settings."
        }
        return "Connect your Android phone via USB cable, or configure wireless ADB. Macrcpy will detect it automatically."
    }
}

#Preview {
    EmptyStateView()
        .environmentObject(AppState())
}
