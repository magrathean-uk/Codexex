#if os(macOS)
import SwiftUI
import CodexMeterCore

struct StatusBarLabel: View {
    let snapshot: CodexSnapshot?
    let isRefreshing: Bool
    let hasError: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(labelText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 2)
    }

    private var labelText: String {
        guard let snapshot else {
            return hasError ? "CH -- CW --" : "CH … CW …"
        }

        let codexLimit = snapshot.codexLimit
        let fiveHour = codexLimit?.primary?.windowDurationMinutes == 300
            ? codexLimit?.primary
            : codexLimit?.secondary?.windowDurationMinutes == 300
            ? codexLimit?.secondary
            : codexLimit?.primary ?? codexLimit?.secondary

        let weekly = codexLimit?.primary?.windowDurationMinutes == 10_080
            ? codexLimit?.primary
            : codexLimit?.secondary?.windowDurationMinutes == 10_080
            ? codexLimit?.secondary
            : codexLimit?.secondary ?? codexLimit?.primary

        var pieces: [String] = []

        if let codex = fiveHour {
            pieces.append("CH \(codex.usedPercentText)")
        } else {
            pieces.append("CH --")
        }

        if let codexWeek = weekly {
            pieces.append("CW \(codexWeek.usedPercentText)")
        } else {
            pieces.append("CW --")
        }

        return pieces.joined(separator: " ")
    }
}
#endif
