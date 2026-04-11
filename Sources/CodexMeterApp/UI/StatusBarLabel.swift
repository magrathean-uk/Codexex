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

    static func makeTitle(
        snapshot: CodexSnapshot?,
        isRefreshing: Bool,
        hasError: Bool,
        showFiveHour: Bool,
        showWeekly: Bool
    ) -> String {
        guard let snapshot else {
            let fiveHour = showFiveHour ? (hasError ? "5H --" : "5H …") : nil
            let weekly = showWeekly ? (hasError ? "W --" : "W …") : nil
            return [fiveHour, weekly].compactMap { $0 }.joined(separator: " ")
        }

        let codexLimit = snapshot.codexLimit
        let fiveHour = codexLimit?.fiveHourWindow
        let weekly = codexLimit?.weeklyWindow

        var pieces: [String] = []

        if showFiveHour {
            if let codex = fiveHour {
                pieces.append("5H \(codex.usedPercentText)")
            } else {
                pieces.append("5H --")
            }
        }

        if showWeekly {
            if let codexWeek = weekly {
                pieces.append("W \(codexWeek.usedPercentText)")
            } else {
                pieces.append("W --")
            }
        }

        return pieces.isEmpty ? "Codexex" : pieces.joined(separator: " ")
    }

    private var labelText: String {
        Self.makeTitle(
            snapshot: snapshot,
            isRefreshing: isRefreshing,
            hasError: hasError,
            showFiveHour: true,
            showWeekly: true
        )
    }
}
#endif
