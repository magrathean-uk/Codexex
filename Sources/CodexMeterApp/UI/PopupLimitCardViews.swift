#if os(macOS)
import CodexMeterCore
import SwiftUI

struct LimitCardView: View {
    let presentation: PopupLimitPresentation
    let resetDisplayStyle: CodexResetDisplayStyle
    let displayMode: CodexMenuBarDisplayMode

    private var limit: CodexLimit { presentation.limit }
    private var headlineFont: Font {
        .system(size: GlassTokens.quotaHeadlineSize, weight: .semibold)
    }
    private var contentSpacing: CGFloat { 10 }
    private var headlineWindow: CodexQuotaWindow? {
        PopupPresentation.headlineWindow(for: limit)
    }

    var body: some View {
        PopupPlainSection {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(limit.displayName)
                        .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                        .foregroundStyle(CodexTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Spacer(minLength: 8)

                    if let headlineWindow {
                        Text(windowValueText(for: headlineWindow))
                            .font(headlineFont)
                            .foregroundStyle(CodexTheme.text)
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                    }
                }

                ForEach(visibleWindows, id: \.title) { item in
                    windowRow(title: item.title, window: item.window)
                }

                if let credits = presentation.visibleCredits {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Credits")
                            .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(credits.displayText)
                            .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                            .foregroundStyle(credits.isNegativeBalance ? Color.red : .secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(minHeight: GlassTokens.limitCardMinHeight, alignment: .center)
        }
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                    .foregroundStyle(CodexTheme.muted)

                Spacer()

                Text(windowValueText(for: window))
                    .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                    .foregroundStyle(CodexTheme.text)
                    .monospacedDigit()

                Text(resetText)
                    .font(.system(size: GlassTokens.popupMetaFontSize))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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
    let presentation: PopupLimitPresentation

    var body: some View {
        PopupPlainSection {
            HStack(spacing: 10) {
                Text(presentation.limit.displayName)
                    .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))

                Spacer()

                Text("Idle")
                    .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageBar: View {
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
                RoundedRectangle(cornerRadius: GlassTokens.quotaBarHeight / 2, style: .continuous)
                    .fill(limitTrackColor(for: bucket))

                if clamped > 0 {
                    let fillWidth = max(6, proxy.size.width * clamped)

                    RoundedRectangle(cornerRadius: GlassTokens.quotaBarHeight / 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: limitGradient(for: bucket),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .clipShape(RoundedRectangle(cornerRadius: GlassTokens.quotaBarHeight / 2, style: .continuous))
                }
            }
        }
        .frame(height: GlassTokens.quotaBarHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.isEmpty ? "\(Int((progress * 100).rounded()))%" : value)
    }
}

func limitAccentColor(for bucket: CodexLimitBucket) -> Color {
    switch bucket {
    case .spark:
        return CodexTheme.spark2
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
        return CodexTheme.control.opacity(0.86)
    case .codex, .other:
        return CodexTheme.control.opacity(0.86)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
