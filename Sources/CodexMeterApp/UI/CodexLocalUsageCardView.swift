#if os(macOS)
import SwiftUI
import CodexMeterCore

enum CodexLocalUsageHeaderAccessory: Equatable {
    case context(String)
    case confidence(String)

    static func resolve(
        needsSessionsAccess: Bool,
        contextWindowPercent: Double?,
        attributionConfidenceTitle: String
    ) -> CodexLocalUsageHeaderAccessory {
        if let contextWindowPercent {
            return .context("Context \(Int(contextWindowPercent.rounded()))%")
        }
        return .confidence(attributionConfidenceTitle)
    }
}

enum CodexLocalUsageText {
    static func headerSummary(sessions: Int, projects: Int, users: Int) -> String {
        "\(sessions) sessions · \(projects) projects · \(users) users"
    }
}

struct CodexLocalUsageCardView: View {
    let summary: CodexLocalUsageSummary
    var grantAccess: (() -> Void)?

    var body: some View {
        GlassCard(style: .primary) {
            VStack(alignment: .leading, spacing: 10) {
                header

                HStack(spacing: 10) {
                    metric("Indexed tokens", value: compactTokens(summary.total.totalTokens), systemImage: "sum")
                    metric("Cached input", value: compactTokens(summary.total.cachedInputTokens), systemImage: "tray.full.fill")
                    metric("Output", value: compactTokens(summary.total.outputTokens), systemImage: "bolt.fill")
                }

                lowerRows
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.coverage.isComplete ? "All indexed sessions" : "Recent indexed sessions")
                    .font(.system(size: 16, weight: .semibold))

                Text(CodexLocalUsageText.headerSummary(
                    sessions: summary.sessions.count,
                    projects: summary.projects.count,
                    users: inferredUserCount
                ))
                .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.muted)
                    .lineLimit(1)

                Text(summary.coverage.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            switch CodexLocalUsageHeaderAccessory.resolve(
                needsSessionsAccess: needsSessionsAccess,
                contextWindowPercent: summary.contextWindowPercent,
                attributionConfidenceTitle: summary.attributionConfidence.title
            ) {
            case .context(let text):
                headerPill(text, color: contextColor, showsHelp: false)
            case .confidence(let text):
                headerPill(text, color: confidenceColor, showsHelp: true)
            }
        }
    }

    private var needsSessionsAccess: Bool {
        summary.configReport.issues.contains { $0.kind == .missingSessionData }
    }

    private var inferredUserCount: Int {
        summary.sessions.isEmpty ? 0 : 1
    }

    private var lowerRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = summary.configReport.issues.first, summary.sessions.isEmpty {
                emptyState(issue)
            } else {
                ForEach(Array(summary.sessionAutopsies.prefix(3).enumerated()), id: \.element.id) { index, autopsy in
                    infoRow(index == 0 ? "Top session" : "Session \(index + 1)", value: autopsyText(autopsy))
                }

                if summary.sessionAutopsies.count > 3 {
                    infoRow("More", value: "\(summary.sessionAutopsies.count - 3) more sessions in local history")
                }

                if let top = summary.projects.first {
                    infoRow("Top project", value: "\(top.displayName) · \(compactTokens(top.tokens.totalTokens)) indexed tokens")
                }

                if let model = summary.modelSummaries.first {
                    infoRow("Top model", value: "\(model.model) · \(compactTokens(model.tokens.totalTokens))")
                }

                if let signal = summary.wasteSignals.first {
                    infoRow(signal.title, value: signal.detail)
                } else if let issue = summary.configReport.issues.first {
                    issueRow(issue)
                } else {
                    infoRow("Attribution", value: summary.attributionConfidence.detail)
                }
            }
        }
    }

    private var confidenceColor: Color {
        switch summary.attributionConfidence.level {
        case .high:
            return CodexTheme.accent
        case .partial:
            return .orange
        case .unknown:
            return CodexTheme.dim
        }
    }

    private var contextColor: Color {
        guard let context = summary.contextWindowPercent else { return CodexTheme.dim }
        return context >= 80 ? .red : context >= 60 ? .orange : CodexTheme.dim
    }

    private func metric(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)

            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.numericText())

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(minHeight: GlassTokens.infoChipHeight, alignment: .leading)
        .background(CodexTheme.surfaceRaised.opacity(0.58), in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
        }
    }

    private func headerPill(_ text: String, color: Color, showsHelp: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)

            if showsHelp {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.dim)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(CodexTheme.control.opacity(0.86), in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
        }
    }

    private func emptyState(_ issue: CodexLocalConfigIssue) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(CodexTheme.dim)
                .frame(width: 36, height: 36)
                .background(CodexTheme.control.opacity(0.76), in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CodexTheme.text)

                Text(issue.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CodexTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: GlassTokens.emptyStateHeight, alignment: .leading)
        .background(CodexTheme.surfaceRaised.opacity(0.50), in: RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlassTokens.pillRadius, style: .continuous)
                .strokeBorder(CodexTheme.hairlineStrong, lineWidth: 1)
        }
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

    private func issueRow(_ issue: CodexLocalConfigIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(issue.title, value: issue.detail)

            if issue.kind == .missingSessionData, let grantAccess {
                Button("Grant Sessions Access", action: grantAccess)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func autopsyText(_ autopsy: CodexLocalSessionAutopsy) -> String {
        let project = autopsy.projectName ?? "Unknown project"
        let share = Int(autopsy.totalSharePercent.rounded())
        return "\(project) · \(autopsy.model) · \(compactTokens(autopsy.tokens.totalTokens)) · \(share)%"
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
