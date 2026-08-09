#if os(macOS)
import CodexMeterCore
import SwiftUI

struct LimitCardView: View {
    let presentation: PopupLimitPresentation
    let resetDisplayStyle: CodexResetDisplayStyle
    let displayMode: CodexMenuBarDisplayMode
    let showFiveHour: Bool

    private var limit: CodexLimit { presentation.limit }
    private var headlineFont: Font {
        .system(size: GlassTokens.quotaHeadlineSize, weight: .semibold)
    }
    private var contentSpacing: CGFloat { 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(limit.displayName)
                    .font(.system(size: GlassTokens.popupBodyFontSize, weight: .semibold))
                    .foregroundStyle(CodexTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer(minLength: 8)
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
    }

    private var visibleWindows: [(title: String, window: CodexQuotaWindow)] {
        PopupPresentation.visibleWindowRows(
            for: limit,
            includeInactive: limit.bucket == .spark,
            showFiveHour: showFiveHour
        )
    }

    private func windowRow(title: String, window: CodexQuotaWindow) -> some View {
        let now = Date()
        let resetText = CodexResetTextFormatting.resetText(
            style: resetDisplayStyle,
            now: now,
            resetAt: window.resetsAt
        )
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                        .foregroundStyle(CodexTheme.muted)
                        .lineLimit(1)

                    Text(resetText)
                        .font(.system(size: GlassTokens.popupMetaFontSize))
                        .foregroundStyle(CodexTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                Text(windowValueText(for: window))
                    .font(headlineFont)
                    .foregroundStyle(CodexTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            UsageBar(
                progress: windowProgress(for: window),
                bucket: limit.bucket,
                label: "\(title) \(windowValueLabel)",
                value: "\(windowValueText(for: window)) \(windowValueLabel), \(resetText)"
            )
        }
        .accessibilityIdentifier(windowAccessibilityIdentifier(for: title))
    }

    private func windowValueText(for window: CodexQuotaWindow) -> String {
        switch displayMode {
        case .used, .pace:
            return window.usedPercentText
        case .remaining:
            return window.remainingPercentText
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

    private func windowAccessibilityIdentifier(for title: String) -> String {
        let windowName = switch title {
        case "5H": "fiveHour"
        case "Weekly": "weekly"
        default: "quota"
        }
        return "mac.popup.\(limit.bucket.rawValue).\(windowName)"
    }
}

struct CompactLimitCardView: View {
    let presentation: PopupLimitPresentation

    var body: some View {
        HStack(spacing: 10) {
            Text(presentation.compactDisplayName)
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .semibold))
                .foregroundStyle(CodexTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Text("Idle")
                .font(.system(size: GlassTokens.popupMetaFontSize, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
        }
        .frame(minHeight: 18)
    }
}

struct UsageBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress = 0.0
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
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: GlassTokens.quotaBarHeight / 2, style: .continuous)
                    .fill(limitTrackColor(for: bucket))

                if visibleProgress > 0 {
                    let fillWidth = max(6, proxy.size.width * visibleProgress)

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
        .onAppear {
            syncProgress(animated: true)
        }
        .onChange(of: progress) { _, _ in
            syncProgress(animated: true)
        }
        .transaction { transaction in
            transaction.disablesAnimations = false
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.isEmpty ? "\(Int((progress * 100).rounded()))%" : value)
    }

    private var clampedProgress: Double {
        progress.clamped(to: 0 ... 1)
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

        withAnimation(.easeOut(duration: 0.38)) {
            displayedProgress = target
        }
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
