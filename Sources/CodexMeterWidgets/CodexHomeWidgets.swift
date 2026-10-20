import CodexMeterCore
import SwiftUI
import WidgetKit

struct MonitoringWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MonitoringWidgetSnapshot
}

struct MonitoringTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonitoringWidgetEntry { sample }
    func getSnapshot(in context: Context, completion: @escaping (MonitoringWidgetEntry) -> Void) {
        completion(context.isPreview ? sample : .init(date: .now, snapshot: MonitoringWidgetStore().load() ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MonitoringWidgetEntry>) -> Void) {
        let now = Date()
        let value = MonitoringWidgetStore().load() ?? .empty
        // These entries age the cached observation; only the app obtains new provider data.
        let staleDates = [value.quotaUpdatedAt, value.apiUpdatedAt].compactMap { $0 }
            .map { $0.addingTimeInterval(MonitoringWidgetSnapshot.freshnessInterval) }
        let resetDates = [value.weeklyResetAt, value.fiveHourResetAt].compactMap { $0 }
        let dates = Set([now] + (staleDates + resetDates).filter { $0 > now }).sorted()
        let entries = dates
            .map { MonitoringWidgetEntry(date: $0, snapshot: value) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
    private var sample: MonitoringWidgetEntry {
        let now = Date()
        let quota = CodexSnapshot(capturedAt: now, executablePath: "", account: .init(authType: "preview", email: nil, planType: nil),
            limits: [.init(id: "codex", rawLimitName: nil, bucket: .codex,
                          primary: .init(usedPercent: 12, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(3600)),
                          secondary: .init(usedPercent: 32, windowDurationMinutes: 10080, resetsAt: now.addingTimeInterval(86400)), credits: nil)])
        return .init(date: now, snapshot: .init(snapshot: quota, apiRemainingUSD: Decimal(string: "2.37"), apiUpdatedAt: now, isPreview: true))
    }
}

struct CodexSubscriptionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MonitoringWidgetStore.quotaKind, provider: MonitoringTimelineProvider()) { entry in
            MonitoringHomeWidgetView(entry: entry, showsAPI: false)
        }
        .configurationDisplayName("Subscription quota")
        .description("Codex allowance and reset times from your latest check.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CodexAPIBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MonitoringWidgetStore.apiKind, provider: MonitoringTimelineProvider()) { entry in
            MonitoringHomeWidgetView(entry: entry, showsAPI: true)
        }
        .configurationDisplayName("API balance")
        .description("Dollars remaining from your latest API balance check.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MonitoringHomeWidgetView: View {
    static let backgroundColor = Color(red: 0.025, green: 0.04, blue: 0.07)
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: MonitoringWidgetEntry
    let showsAPI: Bool
    #if DEBUG
    var familyOverride: WidgetFamily? = nil
    #endif
    private var family: WidgetFamily {
        #if DEBUG
        return familyOverride ?? environmentFamily
        #else
        return environmentFamily
        #endif
    }
    private let accent = Color(red: 0.23, green: 0.64, blue: 1)
    private var compactText: Bool { dynamicTypeSize.isAccessibilitySize }
    private var weeklyPercent: Int? { entry.snapshot.weeklyPercentLeft }
    private var fiveHourPercent: Int? { entry.snapshot.fiveHourPercentLeft }
    private var weeklyResetAt: Date? { entry.snapshot.weeklyResetAt }
    private var fiveHourResetAt: Date? { entry.snapshot.fiveHourResetAt }
    private var balance: Decimal? { entry.snapshot.apiRemainingUSD }
    private var updatedAt: Date? { showsAPI ? entry.snapshot.apiUpdatedAt : entry.snapshot.quotaUpdatedAt }
    private var stale: Bool { showsAPI ? entry.snapshot.apiIsStale(at: entry.date) : entry.snapshot.quotaIsStale(at: entry.date) }
    private var isPreview: Bool { entry.snapshot.isPreview }
    private var hasValue: Bool { showsAPI ? balance != nil : weeklyPercent != nil || fiveHourPercent != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: compactText ? 6 : 8) {
            if compactText {
                Text(showsAPI ? "API" : weeklyPercent != nil ? "Weekly" : fiveHourPercent != nil ? "5-hour" : "Quota")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } else {
                Label(showsAPI ? "Codexex API" : "Codexex",
                      systemImage: showsAPI ? "chart.bar.xaxis" : "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            Text(headline)
                .font(headlineFont.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            if !compactText && hasValue {
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            Text(status)
                .font(.caption2)
                .foregroundStyle(stale && updatedAt != nil ? Color.orange : .white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Self.backgroundColor }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsAPI ? "Codexex API balance" : "Codexex subscription quota")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Opens Codexex")
        .widgetURL(URL(string: "codexex://refresh"))
    }

    private var headlineFont: Font {
        guard hasValue else { return .headline }
        if compactText { return family == .systemSmall && showsAPI ? .title3 : .title2 }
        return family == .systemSmall ? .title2 : .largeTitle
    }

    private var headline: String {
        guard hasValue else { return compactText ? "—" : "Unavailable" }
        if showsAPI, let balance { return balance.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) }
        guard let percent = weeklyPercent ?? fiveHourPercent else { return "Unavailable" }
        return compactText && family == .systemSmall ? "\(percent)%" : "\(percent)% left"
    }

    private var detail: String {
        if showsAPI { return balance == nil ? "Open app to connect" : "USD remaining" }
        guard hasValue else { return "Open app to connect" }
        if family == .systemMedium, weeklyPercent != nil, let fiveHourPercent {
            return "Weekly · 5-hour \(fiveHourPercent)% left"
        }
        let name = weeklyPercent != nil ? "Weekly" : "5-hour"
        let reset = weeklyPercent != nil ? weeklyResetAt : fiveHourResetAt
        guard let reset else { return name }
        return weeklyPercent != nil
            ? "\(name) · \(reset.formatted(.dateTime.weekday(.abbreviated)))"
            : "\(name) · \(reset.formatted(date: .omitted, time: .shortened))"
    }

    private var status: String {
        if isPreview { return compactText ? "Preview" : "Preview data" }
        guard let updatedAt else { return compactText ? "Open app" : "Open app to connect" }
        if compactText && family == .systemSmall { return stale ? "Stale" : "Updated" }
        return "\(stale ? "Stale" : "Updated") \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if showsAPI {
            parts.append(balance.map { "\($0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))) remaining in US dollars" } ?? "Balance unavailable")
        } else {
            if let weeklyPercent { parts.append("\(weeklyPercent)% left of weekly quota") }
            if let weeklyResetAt { parts.append("Weekly resets \(weeklyResetAt.formatted(date: .complete, time: .shortened))") }
            if let fiveHourPercent { parts.append("\(fiveHourPercent)% left of 5-hour quota") }
            if let fiveHourResetAt { parts.append("5-hour resets \(fiveHourResetAt.formatted(date: .complete, time: .shortened))") }
            if !hasValue { parts.append("Quota unavailable") }
        }
        if isPreview {
            parts.append("Preview data")
        } else if let updatedAt {
            parts.append(stale ? "Stale. Update needed" : "Up to date")
            parts.append("Checked \(updatedAt.formatted(date: .complete, time: .shortened))")
        } else {
            parts.append("Open app to connect")
        }
        return parts.joined(separator: ". ")
    }
}

#if DEBUG
/// Renders the production presentation without reading storage or asking WidgetKit for a timeline.
@MainActor enum CodexWidgetDesignFixtures {
    static var homeBackground: Color { MonitoringHomeWidgetView.backgroundColor }

    static func home(
        snapshot: MonitoringWidgetSnapshot,
        date: Date,
        family: WidgetFamily,
        showsAPI: Bool
    ) -> some View {
        MonitoringHomeWidgetView(
            entry: .init(date: date, snapshot: snapshot), showsAPI: showsAPI, familyOverride: family
        )
            .background(MonitoringHomeWidgetView.backgroundColor)
    }
}
#endif
