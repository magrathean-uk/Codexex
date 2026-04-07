#if os(macOS)
import AppKit
import CodexMeterCore
import SwiftUI
import Observation

struct SettingsRootView: View {
    @Bindable var model: CodexMenuBarModel
    @State private var autoRefreshEnabled = CodexAppSettings.autoRefreshEnabled
    @State private var refreshIntervalSeconds = CodexAppSettings.refreshIntervalSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Refresh")
                        .font(.headline)

                    Toggle("Auto refresh", isOn: $autoRefreshEnabled)

                    Picker("Interval", selection: $refreshIntervalSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                    }
                    .pickerStyle(.segmented)
                    .disabled(autoRefreshEnabled == false)

                    Text("Menubar data updates from the local Codex CLI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Diagnostics")
                        .font(.headline)

                    if let snapshot = model.snapshot {
                        HStack(spacing: 8) {
                            pill("Binary", value: URL(fileURLWithPath: snapshot.executablePath).lastPathComponent)
                            pill("Updated", value: CodexFormatting.absoluteResetText(model.lastUpdatedAt))
                        }
                    }

                    Text(model.diagnosticsText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button("Refresh now") {
                            Task { @MainActor in
                                await model.refreshNow()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Copy diagnostics") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.diagnosticsText, forType: .string)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 420, height: 320)
        .onAppear {
            autoRefreshEnabled = CodexAppSettings.autoRefreshEnabled
            refreshIntervalSeconds = CodexAppSettings.refreshIntervalSeconds
        }
        .onChange(of: autoRefreshEnabled) { _, newValue in
            CodexAppSettings.autoRefreshEnabled = newValue
        }
        .onChange(of: refreshIntervalSeconds) { _, newValue in
            CodexAppSettings.refreshIntervalSeconds = newValue
        }
    }

    private func pill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}
#endif
