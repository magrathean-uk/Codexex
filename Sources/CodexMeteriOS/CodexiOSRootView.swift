import SwiftUI
import UIKit
import CodexMeterCore

struct CodexiOSRootView: View {
    @AppStorage(CodexiOSSettingsKeys.showSpark) private var showSpark = true
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
    @AppStorage(CodexiOSSettingsKeys.resetDisplayStyle) private var resetDisplayStyle = CodexiOSResetDisplayStyle.relative.rawValue
    @AppStorage(CodexiOSSettingsKeys.appearanceMode) private var appearanceMode = CodexiOSAppearanceMode.system.rawValue
    @AppStorage(CodexiOSSettingsKeys.defaultHistoryMode) private var defaultHistoryMode = CodexiOSHistoryMode.dailyPeaks.rawValue
    @AppStorage(CodexiOSSettingsKeys.showFiveHourPresentation) private var showFiveHourPresentation = false
    @Bindable var model: CodexiOSModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 12) {
                        responsiveLayout
                    }
                } else {
                    responsiveLayout
                }
            }
            .background(CodexiOSTheme.background.ignoresSafeArea())
        }
        .preferredColorScheme(CodexiOSAppearanceMode(rawValue: appearanceMode)?.colorScheme)
        .onAppear(perform: normalizeHistoryMode)
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shouldShowStatusCard {
                statusCard
            }
            mainQuotaCards
            if showHistory {
                historyCard
            }
        }
        .frame(maxWidth: 760, alignment: .topLeading)
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if shouldShowStatusCard {
                    statusCard
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if shouldShowStatusCard {
                    statusCard
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
            VStack(alignment: .leading, spacing: 10) {
                Text(statusCardTitle)
                    .font(.headline.weight(.semibold))

                Text(model.statusMessage)
                    .font(.callout)
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
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                authButtons
            }
        }
    }

    private var responsiveLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            contentHeader

            ViewThatFits(in: .horizontal) {
                largeLayout
                wideLayout
                narrowLayout
            }

            bottomActionBar
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var contentHeader: some View {
        Text("Codexex")
            .font(.system(size: 38, weight: .bold))
            .lineLimit(1)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            settingsActionButton
            Spacer(minLength: 12)
            refreshActionButton
        }
    }

    private var settingsActionButton: some View {
        NavigationLink {
            CodexiOSSettingsView(model: model)
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(CodexiOSTopButtonStyle())
    }

    private var refreshActionButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            if model.isRefreshing {
                Label {
                    Text("Refreshing")
                } icon: {
                    CodexiOSRefreshingIcon()
                }
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(CodexiOSTopButtonStyle())
        .disabled(model.isRefreshing)
    }

    @ViewBuilder
    private var authButtons: some View {
        if model.isCheckingSavedAccount {
            Label {
                Text("Loading quota")
            } icon: {
                CodexiOSRefreshingIcon()
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
        } else if model.hasPendingSignIn {
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
                Text(model.isSigningIn ? "Starting sign-in" : "Sign in with ChatGPT")
            }
            .buttonStyle(CodexiOSPrimaryButtonStyle())
            .disabled(model.isSigningIn)
        }
    }

    private var mainQuotaCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isCheckingSavedAccount {
                loadingQuotaCard
            } else if let snapshot = model.snapshot {
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(limit.displayName)
                        .font(.headline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    if let headline = headlineWindow(for: limit) {
                        Text(headline.remainingPercentText)
                            .font(.system(size: 36, weight: .semibold).monospacedDigit())
                            .minimumScaleFactor(0.7)
                    }
                }

                if showFiveHourPresentation, let fiveHour = limit.fiveHourWindow {
                    quotaRow(title: "5H", window: fiveHour, tint: tint(for: limit.bucket))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text(window.remainingPercentText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(resetText(for: window))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            CodexiOSQuotaBar(progress: window.remainingPercent / 100, tint: tint)
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
                mode: selectedHistoryMode,
                showFiveHour: showFiveHourPresentation,
                onModeChange: { defaultHistoryMode = $0.rawValue }
            )
        }
    }

    private var selectedHistoryMode: CodexiOSHistoryMode {
        CodexiOSHistoryMode(rawValue: defaultHistoryMode) ?? .dailyPeaks
    }

    private func normalizeHistoryMode() {
        guard CodexiOSHistoryMode(rawValue: defaultHistoryMode) == nil else { return }
        defaultHistoryMode = CodexiOSHistoryMode.dailyPeaks.rawValue
    }

    private var emptyCard: some View {
        iOSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Private by default")
                    .font(.headline.weight(.semibold))
                Text("No server, no Mac bridge, no browser cookies. Sign in happens on-device and tokens stay in Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var loadingQuotaCard: some View {
        iOSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Loading quota")
                    .font(.headline.weight(.semibold))
                Text("Checking the saved ChatGPT session before showing account actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CodexiOSLoadingBar(tint: CodexiOSTheme.secondary)
            }
        }
    }

    private func headlineWindow(for limit: CodexLimit) -> CodexQuotaWindow? {
        [limit.weeklyWindow, showFiveHourPresentation ? limit.fiveHourWindow : nil]
            .compactMap { $0 }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    private func tint(for bucket: CodexLimitBucket) -> Color {
        bucket == .spark ? CodexiOSTheme.tertiary : CodexiOSTheme.secondary
    }

    private var statusCardTitle: String {
        if model.isCheckingSavedAccount {
            return "Loading quota"
        }
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
    let showFiveHour: Bool
    let onModeChange: (CodexiOSHistoryMode) -> Void

    private var fiveHourPoints: [CodexUsageHistoryPoint] {
        showFiveHour ? points(for: .fiveHour) : []
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage history")
                    .font(.headline.weight(.semibold))
                Spacer()
            }

            CodexiOSModeTabs(selection: mode, onChange: onModeChange)

            historyContent
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
        .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CodexiOSQuotaBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress = 0.0
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CodexiOSTheme.inset)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * visibleProgress))
            }
        }
        .frame(height: 8)
        .onAppear {
            syncProgress(animated: true)
        }
        .onChange(of: progress) { _, _ in
            syncProgress(animated: true)
        }
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var visibleProgress: Double {
        reduceMotion ? clampedProgress : displayedProgress
    }

    private func syncProgress(animated: Bool) {
        let target = clampedProgress
        guard reduceMotion == false, animated else {
            displayedProgress = target
            return
        }

        withAnimation(.easeOut(duration: 0.42)) {
            displayedProgress = target
        }
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
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodexiOSTheme.card, in: shape)
                .overlay {
                    shape.strokeBorder(CodexiOSTheme.border, lineWidth: 1)
                }
        } else {
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodexiOSTheme.card, in: shape)
                .overlay {
                    shape.strokeBorder(CodexiOSTheme.border, lineWidth: 1)
                }
        }
    }
}

private extension View {
    func codexiOSGlassCard() -> some View {
        modifier(CodexiOSGlassCardModifier())
    }
}

struct CodexiOSTopButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .scaleEffect(configuration.isPressed && reduceMotion == false ? 0.98 : 1)
            .background(CodexiOSTheme.card.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CodexiOSTheme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.20, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

private struct CodexiOSModeTabs: View {
    let selection: CodexiOSHistoryMode
    let onChange: (CodexiOSHistoryMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CodexiOSHistoryMode.allCases) { mode in
                CodexiOSModeTabButton(
                    mode: mode,
                    isSelected: selection == mode,
                    onSelect: { onChange(mode) }
                )
            }
        }
        .padding(3)
        .background(CodexiOSTheme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CodexiOSTheme.border.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct CodexiOSModeTabButton: View {
    let mode: CodexiOSHistoryMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(mode.title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(selectionBackground)
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? CodexiOSTheme.card : Color.clear)
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
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            .background(CodexiOSTheme.inset.opacity(configuration.isPressed ? 0.70 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
