import SwiftUI
import UIKit
import CodexMeterCore

struct CodexiOSRootView: View {
    @AppStorage(CodexiOSSettingsKeys.showSpark) private var showSpark = true
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
    @AppStorage(CodexiOSSettingsKeys.resetDisplayStyle) private var resetDisplayStyle = CodexiOSResetDisplayStyle.relative.rawValue
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.defaultHistoryMode) private var defaultHistoryMode = CodexiOSHistoryMode.dailyPeaks.rawValue
    @AppStorage(CodexiOSSettingsKeys.showPaceConfidence) private var showPaceConfidence = true
    @Bindable var model: CodexiOSModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 16) {
                        responsiveLayout
                    }
                } else {
                    responsiveLayout
                }
            }
            .background(CodexiOSTheme.background.ignoresSafeArea())
            .navigationTitle("Codexex")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CodexiOSSettingsView(model: model)
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing)
                }
            }
        }
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowStatusCard {
                statusCard
            }
            if let summary = presentedSummary {
                summaryCard(summary)
            }
            mainQuotaCards
            if showHistory {
                historyCard
            }
        }
        .frame(maxWidth: 760, alignment: .topLeading)
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                if shouldShowStatusCard {
                    statusCard
                }
                if let summary = presentedSummary {
                    summaryCard(summary)
                }
                if showHistory {
                    historyCard
                }
            }
            .frame(minWidth: 340, maxWidth: 430, alignment: .topLeading)

            mainQuotaCards
                .frame(minWidth: 340, maxWidth: 520, alignment: .topLeading)
        }
    }

    private var largeLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                if shouldShowStatusCard {
                    statusCard
                }
                if let summary = presentedSummary {
                    summaryCard(summary)
                }
            }
            .frame(minWidth: 300, maxWidth: 380, alignment: .topLeading)

            mainQuotaCards
                .frame(minWidth: 340, maxWidth: 520, alignment: .topLeading)

            if showHistory {
                historyCard
                    .frame(minWidth: 320, maxWidth: 430, alignment: .topLeading)
            }
        }
    }

    private var shouldShowStatusCard: Bool {
        model.snapshot == nil || model.hasPendingSignIn || model.errorMessage != nil
    }

    private var statusCard: some View {
        iOSCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(statusCardTitle)
                    .font(.headline)

                Text(model.statusMessage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = model.errorMessage, error != model.statusMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let code = model.deviceCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device code")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                authButtons
            }
        }
    }

    private var responsiveLayout: some View {
        ViewThatFits(in: .horizontal) {
            largeLayout
            wideLayout
            narrowLayout
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var authButtons: some View {
        if model.hasPendingSignIn {
            FlowLayout(spacing: 10) {
                Button("Open Safari") { Task { await model.openSignInPage() } }
                    .buttonStyle(CodexiOSPrimaryButtonStyle())
                Button("Copy Code") { model.copyCode() }
                    .buttonStyle(CodexiOSSecondaryButtonStyle())
                Button("Check Status") { Task { await model.checkSignIn() } }
                    .buttonStyle(CodexiOSSecondaryButtonStyle())
            }
        } else if model.isSignedIn {
            FlowLayout(spacing: 10) {
                Button("Refresh quota") { Task { await model.refresh() } }
                    .buttonStyle(CodexiOSPrimaryButtonStyle())
                Button("Sign out") { Task { await model.signOut() } }
                    .buttonStyle(CodexiOSSecondaryButtonStyle())
            }
        } else {
            Button {
                Task { await model.beginSignIn() }
            } label: {
                if model.isSigningIn {
                    Label("Starting sign-in", systemImage: "hourglass")
                } else {
                    Label("Sign in with ChatGPT", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .buttonStyle(CodexiOSPrimaryButtonStyle())
            .disabled(model.isSigningIn)
        }
    }

    private var mainQuotaCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = model.snapshot {
                ForEach(CodexQuotaPresentationRules.orderedLimits(snapshot.limits)) { limit in
                    if shouldShow(limit) {
                        quotaCard(limit)
                    }
                }
            } else {
                emptyCard
            }
        }
    }

    private func shouldShow(_ limit: CodexLimit) -> Bool {
        CodexQuotaPresentationRules.shouldShow(
            limit,
            showSpark: showSpark,
            hideIdleSecondaryLimits: true
        )
    }

    private func quotaCard(_ limit: CodexLimit) -> some View {
        iOSCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(limit.displayName)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if let headline = headlineWindow(for: limit) {
                        Text(headline.usedPercentText)
                            .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.7)
                    }
                }

                if let fiveHour = limit.fiveHourWindow {
                    quotaRow(title: "Five hours", window: fiveHour, tint: tint(for: limit.bucket))
                }
                if let weekly = limit.weeklyWindow, weekly != limit.fiveHourWindow {
                    quotaRow(title: "Weekly", window: weekly, tint: tint(for: limit.bucket))
                }
                if let credits = CodexQuotaPresentationRules.visibleCredits(limit.credits) {
                    Text("Credits: \(credits.displayText)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func quotaRow(title: String, window: CodexQuotaWindow, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 10)
                Text("\(window.usedPercentText) used")
                    .font(.headline.monospacedDigit())
            }
            Text(resetText(for: window))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: window.clampedUsedPercent / 100)
                .tint(tint)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
        }
    }

    private func resetText(for window: CodexQuotaWindow) -> String {
        guard CodexiOSResetDisplayStyle(rawValue: resetDisplayStyle) == .absolute,
              let resetsAt = window.resetsAt else {
            return CodexQuotaPresentationRules.resetText(style: .relative, now: .init(), resetAt: window.resetsAt)
        }
        return CodexQuotaPresentationRules.resetText(
            style: .absolute(prefix: "resets at"),
            now: .init(),
            resetAt: resetsAt
        )
    }

    private var historyCard: some View {
        iOSCard {
            CodexiOSHistoryCard(
                samples: model.usageHistory,
                mode: CodexiOSHistoryMode(rawValue: defaultHistoryMode) ?? .dailyPeaks,
                resetDisplayStyle: CodexiOSResetDisplayStyle(rawValue: resetDisplayStyle) ?? .relative,
                showPaceConfidence: showPaceConfidence,
                onModeChange: { defaultHistoryMode = $0.rawValue }
            )
        }
    }

    private var presentedInsights: CodexUsageInsights? {
        CodexUsageHistoryAnalytics.insights(
            snapshot: model.snapshot,
            samples: model.usageHistory,
            now: model.lastUpdatedAt ?? Date()
        )
    }

    private var presentedSummary: PopupSummaryPresentation? {
        let summary = PopupPresentation.summary(
            snapshot: model.snapshot,
            insights: presentedInsights,
            previewModeEnabled: model.previewModeEnabled,
            hasRefreshIssue: model.errorMessage != nil
        )
        guard let summary, model.isSummarySnoozed(summary) == false else { return nil }
        return summary
    }

    private func summaryCard(_ summary: PopupSummaryPresentation) -> some View {
        iOSCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summarySymbol(for: summary.severity))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(summaryColor(for: summary.severity))
                    .frame(width: 32, height: 32)
                    .background(summaryColor(for: summary.severity).opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(summaryColor(for: summary.severity))

                    Text(summary.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text([summary.supportingLabel, summary.supportingValue, summary.supportingDetail].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 8) {
                    if summary.action == .refresh {
                        Button("Refresh") { Task { await model.refresh() } }
                            .buttonStyle(CodexiOSSecondaryButtonStyle())
                    }
                    if summary.severity == .watch || summary.severity == .risk {
                        Button("Snooze") { model.snoozeSummary(summary) }
                            .buttonStyle(CodexiOSSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func summaryColor(for severity: CodexQuotaSeverity) -> Color {
        switch severity {
        case .tooEarly:
            return .secondary
        case .safe:
            return .green
        case .watch:
            return .orange
        case .risk:
            return .red
        }
    }

    private func summarySymbol(for severity: CodexQuotaSeverity) -> String {
        switch severity {
        case .tooEarly:
            return "clock.badge.questionmark"
        case .safe:
            return "checkmark.circle.fill"
        case .watch:
            return "exclamationmark.triangle"
        case .risk:
            return "exclamationmark.triangle.fill"
        }
    }

    private var emptyCard: some View {
        iOSCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(CodexiOSTheme.secondary)
                Text("Private by default")
                    .font(.title2.weight(.bold))
                Text("No server, no Mac bridge, no browser cookies. Sign in happens on-device and tokens stay in Keychain.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headlineWindow(for limit: CodexLimit) -> CodexQuotaWindow? {
        [limit.fiveHourWindow, limit.weeklyWindow]
            .compactMap { $0 }
            .max { $0.clampedUsedPercent < $1.clampedUsedPercent }
    }

    private func tint(for bucket: CodexLimitBucket) -> Color {
        bucket == .spark ? CodexiOSTheme.tertiary : CodexiOSTheme.secondary
    }

    private var statusCardTitle: String {
        if model.hasPendingSignIn {
            return "Finish sign-in"
        }
        if model.errorMessage != nil {
            return "Needs attention"
        }
        return "Sign in"
    }

    private func iOSCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .codexiOSGlassCard()
    }
}

private struct CodexiOSHistoryCard: View {
    let samples: [CodexUsageHistorySample]
    let mode: CodexiOSHistoryMode
    let resetDisplayStyle: CodexiOSResetDisplayStyle
    let showPaceConfidence: Bool
    let onModeChange: (CodexiOSHistoryMode) -> Void

    private var fiveHourPoints: [CodexUsageHistoryPoint] {
        points(for: .fiveHour)
    }

    private var weeklyPoints: [CodexUsageHistoryPoint] {
        points(for: .weekly)
    }

    private var fiveHourForecast: CodexUsageForecast {
        CodexUsageHistoryAnalytics.forecast(from: samples, series: .fiveHour)
    }

    private var weeklyForecast: CodexUsageForecast {
        CodexUsageHistoryAnalytics.forecast(from: samples, series: .weekly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage history")
                    .font(.title3.weight(.bold))
                Spacer()
            }

            Picker("History", selection: Binding(get: { mode }, set: onModeChange)) {
                ForEach(CodexiOSHistoryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            weeklyPace
            historyContent
        }
    }

    private var weeklyPace: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weekly pace")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(forecastHeadline(weeklyForecast))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weeklyForecast.tone.color)
            }

            if showPaceConfidence, let detail = forecastDetail(weeklyForecast) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let current = weeklyForecast.currentPercent,
               let projected = weeklyForecast.projectedPercentAtReset {
                CodexiOSForecastBar(currentPercent: current, projectedPercent: projected)
                HStack {
                    Text("Now \(Int(current.rounded()))%")
                    Spacer()
                    Text("Reset \(Int(projected.rounded()))%")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        switch mode {
        case .dailyPeaks:
            CodexiOSHistoryGraph(fiveHourPoints: fiveHourPoints, weeklyPoints: weeklyPoints)
            FlowLayout(spacing: 8) {
                chip("5H", PopupPresentation.historyLegendValue(for: fiveHourForecast))
                chip("Weekly", PopupPresentation.historyLegendValue(for: weeklyForecast))
            }
        case .thisCycle:
            CodexiOSHistoryGraph(
                fiveHourPoints: CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .fiveHour),
                weeklyPoints: CodexUsageHistoryAnalytics.currentCyclePoints(from: samples, series: .weekly)
            )
            FlowLayout(spacing: 8) {
                if let range = likelyRange(weeklyForecast) {
                    chip("Range", range)
                }
                chip("Data", "\(weeklyForecast.sampleCount) samples")
                if let resetAt = weeklyForecast.resetAt {
                    chip("Reset", resetText(resetAt))
                }
            }
        case .monthly:
            CodexiOSHistoryGraph(fiveHourPoints: [], weeklyPoints: weeklyPoints)
            FlowLayout(spacing: 8) {
                if let month = CodexUsageHistoryAnalytics.monthlyHistory(from: samples, series: .weekly) {
                    chip("Peak", "\(Int(month.peakPercent.rounded()))%")
                    chip("Average", "\(Int(month.averageDailyPeakPercent.rounded()))%")
                    chip("Data", "\(month.dayCount) days")
                } else {
                    chip("Data", "No samples")
                }
            }
        }
    }

    private func points(for series: CodexUsageHistorySeries) -> [CodexUsageHistoryPoint] {
        CodexUsageHistoryAnalytics.points(from: samples, series: series)
    }

    private func forecastHeadline(_ forecast: CodexUsageForecast) -> String {
        switch forecast.confidence {
        case .tooEarly, .learning, .estimatedFromHistory:
            return forecast.message
        case .patternMatched:
            return "Pattern matched"
        case .machineLearned:
            return "ML tuned"
        case .stable:
            return "Stable"
        case .volatile:
            return "Volatile"
        }
    }

    private func forecastDetail(_ forecast: CodexUsageForecast) -> String? {
        guard let detail = forecast.detail else { return nil }
        let parts = detail
            .components(separatedBy: " · ")
            .filter { $0 != forecast.confidence.label && $0.hasSuffix("samples") == false && $0.hasSuffix("cycles") == false }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func likelyRange(_ forecast: CodexUsageForecast) -> String? {
        guard let lower = forecast.likelyLowerPercent,
              let upper = forecast.likelyUpperPercent,
              upper - lower >= 2 else { return nil }
        return "\(Int(lower.rounded()))-\(Int(upper.rounded()))%"
    }

    private func resetText(_ resetAt: Date) -> String {
        switch resetDisplayStyle {
        case .relative:
            return CodexQuotaPresentationRules.resetText(style: .relative, now: Date(), resetAt: resetAt)
        case .absolute:
            return CodexQuotaPresentationRules.resetText(style: .absolute(prefix: "resets"), now: Date(), resetAt: resetAt)
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CodexiOSHistoryGraph: View {
    let fiveHourPoints: [CodexUsageHistoryPoint]
    let weeklyPoints: [CodexUsageHistoryPoint]

    var body: some View {
        Canvas { context, size in
            drawBars(in: &context, size: size)
            drawLine(in: &context, size: size)
        }
        .frame(height: 58)
        .accessibilityLabel("Usage history graph")
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize) {
        guard fiveHourPoints.isEmpty == false else { return }
        for (index, point) in fiveHourPoints.enumerated() {
            let rect = PopupPresentation.historyBarRect(
                usedPercent: point.usedPercent,
                index: index,
                count: fiveHourPoints.count,
                size: size
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2)),
                with: .color(CodexiOSTheme.primary.opacity(0.42))
            )
        }
    }

    private func drawLine(in context: inout GraphicsContext, size: CGSize) {
        guard weeklyPoints.count >= 2, size.width > 0, size.height > 0 else { return }
        var path = Path()
        for (index, point) in weeklyPoints.enumerated() {
            let x = CGFloat(index) / CGFloat(weeklyPoints.count - 1) * size.width
            let clamped = min(max(point.usedPercent, 0), 100)
            let y = size.height - (size.height * CGFloat(clamped / 100))
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(CodexiOSTheme.secondary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

private struct CodexiOSForecastBar: View {
    let currentPercent: Double
    let projectedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentX = width * min(max(currentPercent / 100, 0), 1)
            let projectedX = width * min(max(projectedPercent / 100, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(CodexiOSTheme.inset)
                Capsule()
                    .fill(CodexiOSTheme.primaryGradient)
                    .frame(width: max(8, currentX))
                Circle()
                    .fill(.primary)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, currentX - 6))
                RoundedRectangle(cornerRadius: 1)
                    .fill(.orange)
                    .frame(width: 2, height: 16)
                    .offset(x: max(0, projectedX - 1))
            }
        }
        .frame(height: 9)
    }
}

enum CodexiOSTheme {
    static let primary = Color(red: 0.10, green: 0.15, blue: 1.00)
    static let secondary = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let tertiary = Color(red: 0.42, green: 0.85, blue: 1.00)
    static let page = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1)
            : UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.03, green: 0.06, blue: 0.13, alpha: 1)
            : UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
    })
    static let surfaceStrong = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.08, blue: 0.15, alpha: 1)
            : UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
    })
    static let border = Color(red: 0.37, green: 0.67, blue: 1.00).opacity(0.20)
    static let background = LinearGradient(
        colors: [
            page,
            surface,
            surfaceStrong
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let card = surface.opacity(0.88)
    static let inset = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.055)
    })
    static let primaryGradient = LinearGradient(
        colors: [primary, secondary, tertiary],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct CodexiOSGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodexiOSTheme.card, in: shape)
                .glassEffect(.regular.tint(CodexiOSTheme.card), in: .rect(cornerRadius: 26))
                .overlay {
                    shape.strokeBorder(CodexiOSTheme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        } else {
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: shape)
                .background(CodexiOSTheme.card, in: shape)
                .overlay {
                    shape.strokeBorder(CodexiOSTheme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        }
    }
}

private extension View {
    func codexiOSGlassCard() -> some View {
        modifier(CodexiOSGlassCardModifier())
    }
}

struct CodexiOSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .scaleEffect(configuration.isPressed && reduceMotion == false ? 0.97 : 1)
            .background(
                CodexiOSTheme.primaryGradient.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(Rectangle())
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct CodexiOSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .scaleEffect(configuration.isPressed && reduceMotion == false ? 0.97 : 1)
            .background(CodexiOSTheme.inset.opacity(configuration.isPressed ? 0.70 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CodexiOSTheme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + size.width + spacing > width {
                totalHeight += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += (lineWidth == 0 ? 0 : spacing) + size.width
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: totalHeight + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
