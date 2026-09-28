#if os(macOS)
import AppKit
import SwiftUI
import CodexMeterCore

struct PopupResetDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: CodexMenuBarModel
    let snapshot: CodexSnapshot
    let onOpenSettings: () -> Void

    static func backgroundNSColor(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.10, green: 0.11, blue: 0.11, alpha: 1)
            : NSColor(red: 0.97, green: 0.98, blue: 0.97, alpha: 1)
    }

    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        backgroundNSColor(for: appearance)
    })

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.96, blue: 0.68)
            : Color(red: 0.04, green: 0.43, blue: 0.21)
    }

    private var fiveHourWindow: CodexQuotaWindow? {
        guard snapshot.showsFiveHourLimit else { return nil }
        return snapshot.codexLimit?.fiveHourWindow
    }

    private var weeklyWindow: CodexQuotaWindow? {
        snapshot.codexLimit?.weeklyWindow
    }

    private var showsUsedQuota: Bool {
        model.menuBarDisplayMode == .used
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let activeFiveHourWindow = activeFiveHourWindow(now: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 30)

                    Text(activeFiveHourWindow == nil && weeklyWindow != nil ? "Weekly allowance" : "Your next reset")
                        .font(.system(size: 27, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 15)

                    if let activeFiveHourWindow {
                        fiveHourHero(activeFiveHourWindow, now: context.date)
                    } else if let weeklyWindow {
                        weeklyAllowanceHero(weeklyWindow)
                    } else {
                        Text("Reset time unavailable")
                            .font(.system(size: 20, weight: .semibold))
                    }

                    if let weeklyWindow {
                        weeklyReset(
                            weeklyWindow,
                            now: context.date,
                            showsAllowance: activeFiveHourWindow != nil
                        )
                        .padding(.top, 38)
                    }

                    if model.lastError != nil {
                        Text("Could not refresh. Showing the last check.")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(.top, 22)
                    }

                    footer
                        .padding(.top, 35)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: GlassTokens.popupMaxHeight)
        }
        .foregroundStyle(.primary)
        .background(Self.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Codexex")
                .font(.system(size: 19, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                .accessibilityIdentifier("mac.popup.settings")

            Button("Refresh", systemImage: "arrow.clockwise") {
                refresh()
            }
            .disabled(model.isRefreshing)
            .accessibilityIdentifier("mac.popup.refresh")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .medium))
    }

    private func fiveHourHero(_ window: CodexQuotaWindow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let resetsAt = window.resetsAt {
                Text(resetsAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 64, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(dayLabel(for: resetsAt, now: now)) · 5-hour window")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Text(relativeReset(resetsAt, now: now))
                    .font(.system(size: 32, weight: .semibold))
                    .padding(.top, 18)
            }

            Text(availabilityText(for: window, name: "5-hour"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
        }
    }

    private func weeklyAllowanceHero(_ window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(percentageText(for: window))
                .font(.system(size: 62, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent)
                            .frame(width: geometry.size.width * displayedPercent(for: window) / 100)
                    }
            }
                .frame(height: 7)
                .accessibilityHidden(true)
                .padding(.top, 19)
        }
    }

    private func weeklyReset(
        _ window: CodexQuotaWindow,
        now: Date,
        showsAllowance: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Weekly reset")
                .font(.system(size: 21, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            if let resetsAt = window.resetsAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(resetsAt.formatted(.dateTime.weekday(.wide))) \(resetsAt.formatted(.dateTime.day().month(.wide)))")
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(resetsAt.formatted(date: .omitted, time: .shortened)) · \(relativeReset(resetsAt, now: now))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Reset time unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if showsAllowance {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Weekly allowance")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(percentageText(for: window))
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.top, 5)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdatedAt = model.lastUpdatedAt {
                Text("Checked \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not checked yet")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Refresh") { refresh() }
                .foregroundStyle(accent)
                .disabled(model.isRefreshing)
                .accessibilityIdentifier("mac.popup.refreshFooter")
        }
        .font(.system(size: 12))
    }

    private func refresh() {
        Task { await model.refreshNow(manual: true) }
    }

    private func activeFiveHourWindow(now: Date) -> CodexQuotaWindow? {
        guard let fiveHourWindow, let resetsAt = fiveHourWindow.resetsAt, resetsAt > now else {
            return nil
        }
        return fiveHourWindow
    }

    private func displayedPercent(for window: CodexQuotaWindow) -> Double {
        showsUsedQuota ? window.clampedUsedPercent : window.remainingPercent
    }

    private func percentageText(for window: CodexQuotaWindow) -> String {
        "\(Int(displayedPercent(for: window).rounded()))% \(showsUsedQuota ? "used" : "left")"
    }

    private func availabilityText(for window: CodexQuotaWindow, name: String) -> String {
        if showsUsedQuota {
            return "\(window.usedPercentText) of your \(name) allowance has been used."
        }
        if window.remainingPercent <= 0 {
            return "Your \(name) allowance is currently used up."
        }
        return "\(window.remainingPercentText) of your \(name) allowance is still available."
    }

    private func dayLabel(for date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? "Today"
            : date.formatted(.dateTime.weekday(.wide))
    }

    private func relativeReset(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes <= 0 { return "now" }
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            return "in \(days) \(days == 1 ? "day" : "days")"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "in \(remainingMinutes)m" }
        return "in \(hours)h \(String(format: "%02d", remainingMinutes))m"
    }
}
#endif
