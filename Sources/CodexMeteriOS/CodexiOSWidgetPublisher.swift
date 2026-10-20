import Foundation
import WidgetKit
import CodexMeterCore

@MainActor
protocol CodexiOSWidgetPublishing {
    func publish(_ value: MonitoringWidgetSnapshot)
    func clear()
    func hasInstalledWidgets() async -> Bool
    func currentSnapshot() -> MonitoringWidgetSnapshot?
}

extension CodexiOSWidgetPublishing {
    func currentSnapshot() -> MonitoringWidgetSnapshot? { nil }
}

@MainActor
struct CodexiOSWidgetPublisher: CodexiOSWidgetPublishing {
    private let store = MonitoringWidgetStore()

    func publish(_ value: MonitoringWidgetSnapshot) {
        guard store.load() != value, (try? store.save(value)) == true else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: MonitoringWidgetStore.quotaKind)
        WidgetCenter.shared.reloadTimelines(ofKind: MonitoringWidgetStore.apiKind)
    }

    func clear() { publish(.empty) }
    func currentSnapshot() -> MonitoringWidgetSnapshot? { store.load() }

    func hasInstalledWidgets() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let kinds = [MonitoringWidgetStore.quotaKind, MonitoringWidgetStore.apiKind]
                let installed = (try? result.get().contains { kinds.contains($0.kind) }) ?? false
                continuation.resume(returning: installed)
            }
        }
    }
}
