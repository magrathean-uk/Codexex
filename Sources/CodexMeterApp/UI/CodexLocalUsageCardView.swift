#if os(macOS)
import SwiftUI
import CodexMeterCore

struct CodexLocalUsageCardView: View {
    let summary: CodexLocalUsageSummary

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(spacing: 10) {
                    metric("Today", value: compactTokens(summary.today.totalTokens), systemImage: "bolt.fill")
                    metric("Week", value: compactTokens(summary.week.totalTokens), systemImage: "calendar")
                    metric("Sessions", value: "\(summary.sessions.count)", systemImage: "terminal.fill")
                }

                Divider()
                    .overlay(CodexTheme.hairline)

                lowerRows
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Codex burn")
                    .font(.system(size: 13, weight: .semibold))

                Text(summary.latestProjectName ?? "Session usage")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let context = summary.contextWindowPercent {
                Text("Context \(Int(context.rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(context >= 80 ? .red : context >= 60 ? .orange : CodexTheme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CodexTheme.control.opacity(0.82), in: Capsule())
            }
        }
    }

    private var lowerRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let model = summary.latestModel {
                infoRow("Model", value: model)
            }

            if let top = summary.projects.first {
                infoRow("Top project", value: "\(top.displayName) · \(compactTokens(top.tokens.totalTokens))")
            }

            if let signal = summary.wasteSignals.first {
                infoRow(signal.title, value: signal.detail)
            } else if let issue = summary.configReport.issues.first {
                infoRow(issue.title, value: issue.detail)
            }
        }
    }

    private func metric(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .contentTransition(.numericText())

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CodexTheme.control.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexTheme.dim)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(CodexTheme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(Int((Double(value) / 1_000_000).rounded()))M"
        }
        if value >= 1_000 {
            return "\(Int((Double(value) / 1_000).rounded()))K"
        }
        return "\(value)"
    }
}
#endif
