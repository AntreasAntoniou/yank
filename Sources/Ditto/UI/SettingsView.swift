import SwiftUI
import AppKit

/// Observable wrapper over the app's persisted settings so the in-bar settings
/// UI can bind to them with two-way bindings. Reads current values on init and
/// writes through on change.
@MainActor
final class AppSettings: ObservableObject {
    let store: ClipStore

    @Published var soundEnabled: Bool { didSet { Feedback.soundEnabled = soundEnabled } }
    @Published var soundName: String { didSet { Feedback.soundName = soundName } }
    @Published var debugLogging: Bool { didSet { UserDefaults.standard.set(debugLogging, forKey: "debugLog") } }
    @Published var historyLimit: Int { didSet { store.historyLimit = historyLimit } }
    @Published var launchAtLogin: Bool { didSet { LoginItem.set(launchAtLogin) } }

    init(store: ClipStore) {
        self.store = store
        soundEnabled = Feedback.soundEnabled
        soundName = Feedback.soundName
        debugLogging = DebugLog.enabled
        historyLimit = store.historyLimit
        launchAtLogin = LoginItem.enabled
    }

    func previewSound() { Feedback.play(named: soundName) }
}

/// The settings surface shown *inside* the bar (toggled from the toolbar gear).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipStore
    /// Re-read on each render so the Accessibility row reflects live state.
    private var axTrusted: Bool { AXIsProcessTrusted() }

    private let limits: [(Int, String)] = [
        (0, "Unlimited"), (100, "100"), (200, "200"), (500, "500"), (1000, "1000"), (5000, "5000")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                section("General") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    HStack {
                        Text("Global shortcut").foregroundStyle(.secondary)
                        Spacer()
                        keycap("⌃⌥⌘V")
                    }
                }

                section("Sound") {
                    Toggle("Play sound on copy", isOn: $settings.soundEnabled)
                    HStack {
                        Text("Copy sound").foregroundStyle(settings.soundEnabled ? .primary : .secondary)
                        Spacer()
                        Picker("", selection: $settings.soundName) {
                            ForEach(Feedback.availableSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        .disabled(!settings.soundEnabled)
                        Button {
                            settings.previewSound()
                        } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.plain)
                        .disabled(!settings.soundEnabled)
                    }
                }

                section("History") {
                    HStack {
                        Text("Keep")
                        Spacer()
                        Picker("", selection: $settings.historyLimit) {
                            ForEach(limits, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    HStack {
                        Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") stored")
                            .foregroundStyle(.secondary).font(.system(size: 12))
                        Spacer()
                        Button("Clear Unpinned", role: .destructive) { store.clearUnpinned() }
                            .controlSize(.small)
                    }
                }

                section("Permissions & Advanced") {
                    HStack {
                        Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(axTrusted ? .green : .orange)
                        Text(axTrusted ? "Accessibility granted (auto-paste enabled)"
                                        : "Accessibility needed for auto-paste")
                            .font(.system(size: 12))
                        Spacer()
                        if !axTrusted {
                            Button("Grant…") { promptAccessibility() }
                                .controlSize(.small)
                        }
                    }
                    Toggle("Debug logging", isOn: $settings.debugLogging)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
        .font(.system(size: 13))
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    private func promptAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary)
    }
}
