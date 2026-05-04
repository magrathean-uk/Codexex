import SwiftUI
import CodexMeterCore

struct CodexiOSRootView: View {
    @AppStorage(CodexiOSSettingsKeys.showSpark) private var showSpark = true
    @AppStorage(CodexiOSSettingsKeys.showHistory) private var showHistory = true
    @AppStorage(CodexiOSSettingsKeys.resetDisplayStyle) private var resetDisplayStyle = CodexiOSResetDisplayStyle.countdown.rawValue
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
        .preferredColorScheme(.dark)
    }

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
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
                Button("Open Safari") { model.openSignInPage() }
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
        guard CodexiOSResetDisplayStyle(rawValue: resetDisplayStyle) == .clock,
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Usage radar")
                    .font(.title3.weight(.bold))

                if let limit = model.snapshot?.codexLimit,
                   let weekly = limit.weeklyWindow {
                    Text("Weekly is at \(weekly.usedPercentText). \(CodexFormatting.relativeResetText(now: .init(), resetAt: weekly.resetsAt)).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Once signed in, Codexex watches your quota locally on this phone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let updated = model.lastUpdatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

enum CodexiOSTheme {
    static let primary = Color(red: 0.10, green: 0.15, blue: 1.00)
    static let secondary = Color(red: 0.13, green: 0.84, blue: 0.91)
    static let tertiary = Color(red: 0.42, green: 0.85, blue: 1.00)
    static let page = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let surface = Color(red: 0.03, green: 0.06, blue: 0.13)
    static let surfaceStrong = Color(red: 0.04, green: 0.08, blue: 0.15)
    static let border = Color(red: 0.37, green: 0.67, blue: 1.00).opacity(0.20)
    static let background = LinearGradient(
        colors: [
            page,
            surface,
            Color(red: 0.02, green: 0.08, blue: 0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let card = surface.opacity(0.88)
    static let inset = Color.white.opacity(0.07)
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

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(
                    .regular.tint(CodexiOSTheme.primary.opacity(isEnabled ? 0.50 : 0.24)).interactive(),
                    in: .rect(cornerRadius: 18)
                )
                .opacity(configuration.isPressed ? 0.78 : 1)
        } else {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    CodexiOSTheme.primaryGradient.opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
}

struct CodexiOSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(.regular.tint(CodexiOSTheme.surfaceStrong.opacity(0.72)).interactive(), in: .rect(cornerRadius: 18))
                .opacity(configuration.isPressed ? 0.78 : 1)
        } else {
            configuration.label
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(CodexiOSTheme.inset.opacity(configuration.isPressed ? 0.70 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(CodexiOSTheme.border, lineWidth: 1)
                }
        }
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
