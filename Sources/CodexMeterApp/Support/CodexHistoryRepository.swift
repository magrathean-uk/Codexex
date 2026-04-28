#if os(macOS)
import Foundation
import CodexMeterCore

struct CodexHistoryRepositoryState: Equatable {
    let samples: [CodexUsageHistorySample]
    let forecastSamples: [CodexUsageHistorySample]
    let insights: CodexUsageInsights?
}

actor CodexHistoryRepository {
    private let store: CodexUsageHistoryStore

    init(store: CodexUsageHistoryStore = CodexUsageHistoryStore()) {
        self.store = store
    }

    func load(
        snapshot: CodexSnapshot?,
        now: Date = Date()
    ) async -> CodexHistoryRepositoryState {
        let samples = await store.load(now: now)
        return state(snapshot: snapshot, samples: samples, now: now)
    }

    func append(
        snapshot: CodexSnapshot,
        now: Date = Date()
    ) async -> CodexHistoryRepositoryState {
        let samples = await store.append(snapshot: snapshot, now: now)
        return state(snapshot: snapshot, samples: samples, now: snapshot.capturedAt)
    }

    private func state(
        snapshot: CodexSnapshot?,
        samples: [CodexUsageHistorySample],
        now: Date
    ) -> CodexHistoryRepositoryState {
        let forecastSamples = samples.filter { sample in
            sample.fiveHour != nil || sample.weekly != nil
        }
        return CodexHistoryRepositoryState(
            samples: samples,
            forecastSamples: forecastSamples,
            insights: CodexUsageHistoryAnalytics.insights(
                snapshot: snapshot,
                samples: forecastSamples,
                now: snapshot?.capturedAt ?? now
            )
        )
    }
}
#endif
