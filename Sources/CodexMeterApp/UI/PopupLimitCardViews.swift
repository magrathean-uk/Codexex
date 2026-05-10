#if os(macOS)
import CodexMeterCore
import SwiftUI

struct LimitCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let presentation: PopupLimitPresentation
    let resetDisplayStyle: CodexResetDisplayStyle
    let displayMode: CodexMenuBarDisplayMode

    private var limit: CodexLimit { presentation.limit }
    private var cardStyle: GlassSurfaceStyle {
        presentation.style == .hero ? .primary : .secondary
    }
    private var headlineFont: Font {
        .system(size: 28, weight: .semibold)
    }
    private var contentSpacing: CGFloat { 12 }
    private var headlineWindow: CodexQuotaWindow? {
        PopupPresentation.headlineWindow(for: limit)
    }

    var body: some View {
        GlassCard(style: cardStyle) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(limit.displayName)
                        .font(.system(size: presentation.style == .hero ? 15 : 14, weight: .semibold))
                        .foregroundStyle(CodexTheme.text)

                    Spacer()

                    if let headlineWindow {
                        Text(windowValueText(for: headlineWindow))
                            .font(headlineFont)
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .numericText(value: windowValuePercent(for: headlineWindow))
                            )
                    }
                }

                ForEach(visibleWindows, id: \.title) { item in
                    windowRow(title: item.title, window: item.window)
                }

                if let credits = presentation.visibleCredits {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Credits")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(credits.displayText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(credits.isNegativeBalance ? Color.red : .secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
    }

    private var visibleWindows: [(title: String, window: CodexQuotaWindow)] {
        PopupPresentation.visibleWindowRows(
            for: limit,
            includeInactive: limit.bucket == .spark
        )
    }

    private func windowRow(title: String, window: CodexQuotaWindow) -> some View {
        let now = Date()
        let resetText = CodexResetTextFormatting.resetText(
            style: resetDisplayStyle,
            now: now,
            resetAt: window.resetsAt
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.muted)

                Spacer()

                Text(windowValueText(for: window))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.text)
                    .contentTransition(
                        accessibilityReduceMotion
                            ? .identity
                            : .numericText(value: windowValuePercent(for: window))
                    )

                Text(resetText)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.dim)
            }

            UsageBar(
                progress: windowProgress(for: window),
                bucket: limit.bucket,
                label: "\(title) \(windowValueLabel)",
                value: "\(windowValueText(for: window)) \(windowValueLabel), \(resetText)"
            )
        }
    }

    private func windowValueText(for window: CodexQuotaWindow) -> String {
        switch displayMode {
        case .used, .pace:
            return window.usedPercentText
        case .remaining:
            return window.remainingPercentText
        }
    }

    private func windowValuePercent(for window: CodexQuotaWindow) -> Double {
        switch displayMode {
        case .used, .pace:
            return window.usedPercent
        case .remaining:
            return window.remainingPercent
        }
    }

    private func windowProgress(for window: CodexQuotaWindow) -> Double {
        switch displayMode {
        case .used, .pace:
            return window.usedPercent / 100
        case .remaining:
            return PopupPresentation.quotaRemainingProgress(for: window)
        }
    }

    private var windowValueLabel: String {
        switch displayMode {
        case .used, .pace:
            return "used"
        case .remaining:
            return "remaining"
        }
    }
}

struct CompactLimitCardView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let presentation: PopupLimitPresentation

    var body: some View {
        GlassCard(style: .secondary) {
            HStack(spacing: 10) {
                Circle()
                    .fill(limitAccentColor(for: presentation.limit.bucket))
                    .frame(width: 8, height: 8)

                Text(presentation.limit.displayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Idle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .transition(accessibilityReduceMotion ? .identity : .opacity)
    }
}

struct UsageBar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let progress: Double
    let bucket: CodexLimitBucket
    let label: String
    let value: String

    init(progress: Double, bucket: CodexLimitBucket, label: String = "Usage", value: String = "") {
        self.progress = progress
        self.bucket = bucket
        self.label = label
        self.value = value
    }

    var body: some View {
        GeometryReader { proxy in
            let clamped = progress.clamped(to: 0 ... 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(limitTrackColor(for: bucket))

                if clamped > 0 {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: limitGradient(for: bucket),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: 6)
        .allowsHitTesting(false)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.isEmpty ? "\(Int((progress * 100).rounded()))%" : value)
    }
}

func limitAccentColor(for bucket: CodexLimitBucket) -> Color {
    switch bucket {
    case .spark:
        return Color(red: 0.66, green: 0.38, blue: 0.84)
    case .codex, .other:
        return CodexTheme.accent
    }
}

func limitGradient(for bucket: CodexLimitBucket) -> [Color] {
    switch bucket {
    case .spark:
        return [
            CodexTheme.spark,
            CodexTheme.spark2
        ]
    case .codex, .other:
        return [
            CodexTheme.accent,
            CodexTheme.accent2
        ]
    }
}

func limitTrackColor(for bucket: CodexLimitBucket) -> Color {
    switch bucket {
    case .spark:
        return Color.white.opacity(0.06)
    case .codex, .other:
        return Color.white.opacity(0.06)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
