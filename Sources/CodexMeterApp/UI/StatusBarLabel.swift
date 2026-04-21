#if os(macOS)
import AppKit
import SwiftUI
import CodexMeterCore

struct StatusBarLabel: View {
    let snapshot: CodexSnapshot?
    let isRefreshing: Bool
    let hasError: Bool
    let severity: CodexQuotaSeverity?

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
            } else if let severity {
                Circle()
                    .fill(Self.dotColor(for: severity))
                    .frame(width: 7, height: 7)
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

    static func menuBarImage(
        isRefreshing: Bool,
        hasError: Bool,
        severity: CodexQuotaSeverity?
    ) -> NSImage? {
        if isRefreshing {
            return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        }
        if hasError {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        }
        guard let severity else { return nil }

        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        dotNSColor(for: severity).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
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

    private static func dotColor(for severity: CodexQuotaSeverity) -> Color {
        Color(nsColor: dotNSColor(for: severity))
    }

    private static func dotNSColor(for severity: CodexQuotaSeverity) -> NSColor {
        switch severity {
        case .tooEarly:
            return .systemGray
        case .safe:
            return .systemGreen
        case .watch:
            return .systemYellow
        case .risk:
            return .systemRed
        }
    }
}
#endif
