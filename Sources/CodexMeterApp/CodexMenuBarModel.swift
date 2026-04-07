#if os(macOS)
import Foundation
import AppKit
import CodexMeterCore
import Observation

@MainActor
@Observable
final class CodexMenuBarModel {
    private final class Lifecycle {
        var refreshLoopTask: Task<Void, Never>?
        var wakeObserver: NSObjectProtocol?

        deinit {
            refreshLoopTask?.cancel()
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
        }
    }

    private(set) var snapshot: CodexSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var lastUpdatedAt: Date?

    private let probe = CodexAppServerProbe()
    private let lifecycle = Lifecycle()
    private var didStart = false

    func start() async {
        guard didStart == false else { return }
        didStart = true

        registerWakeObserver()
        await refreshNow()

        lifecycle.refreshLoopTask = Task { [weak self] in
            while Task.isCancelled == false {
                if CodexAppSettings.autoRefreshEnabled == false {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        break
                    }
                    continue
                }

                let refreshInterval = CodexAppSettings.refreshInterval
                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    break
                }

                guard Task.isCancelled == false else { break }
                await self?.refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await probe.capture()
            snapshot = result
            lastUpdatedAt = result.capturedAt
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    var diagnosticsText: String {
        let lines = [
            "Auto refresh: \(CodexAppSettings.autoRefreshEnabled ? "on" : "off")",
            "Refresh interval: \(CodexAppSettings.refreshIntervalLabel)",
            "Last refresh: \(lastUpdatedAt.map { CodexFormatting.absoluteResetText($0) } ?? "never")",
            "Executable: \(snapshot?.executablePath ?? "unknown")",
            "Account: \(snapshot?.account.displaySubtitle ?? "unknown")",
            "Error: \(lastError ?? "none")"
        ]
        return lines.joined(separator: "\n")
    }

    private func registerWakeObserver() {
        lifecycle.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshNow()
            }
        }
    }
}
#endif
