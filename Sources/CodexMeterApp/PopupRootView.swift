#if os(macOS)
import SwiftUI
import CodexMeterCore
import Observation

struct PopupRootView: View {
    @Bindable var model: CodexMenuBarModel

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(14)
            }
        }
        .frame(width: 340, height: 360)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            ForEach(snapshot.limits) { limit in
                LimitCardView(limit: limit)
            }
        } else {
            GlassCard {
                Text("Waiting for quota data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitCardView: View {
    let limit: CodexLimit

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(limit.displayName)
                        .font(.headline)

                    Spacer()

                    if let primary = limit.primary {
                        Text(primary.usedPercentText)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }

                if let primary = limit.primary {
                    windowBlock(title: "Primary", window: primary)
                }

                if let secondary = limit.secondary {
                    Divider()
                    windowBlock(title: "Secondary", window: secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func windowBlock(title: String, window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(window.windowText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: window.clampedUsedPercent, total: 100)
                .controlSize(.regular)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                metric("Used", window.usedPercentText)
                metric("Left", window.remainingPercentText)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(CodexFormatting.relativeResetText(now: Date(), resetAt: window.resetsAt))
                    .font(.subheadline.weight(.medium))
                Text(CodexFormatting.absoluteResetText(window.resetsAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
    }
}
#endif
