import SwiftUI
import CodexMeterCore

struct CodexiOSResetDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(CodexiOSSettingsKeys.showUsedQuota) private var showUsedQuota = false
    @ScaledMetric(relativeTo: .largeTitle) private var dashboardTitleSize = 42
    @ScaledMetric(relativeTo: .largeTitle) private var resetTimeSize = 102
    @ScaledMetric(relativeTo: .title) private var relativeResetSize = 50
    @ScaledMetric(relativeTo: .largeTitle) private var allowanceSize = 78

    @Bindable var model: CodexiOSModel
    let snapshot: CodexSnapshot
    let onMatrixThemeEnabled: () -> Void

    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.11, blue: 0.11, alpha: 1)
            : UIColor(red: 0.97, green: 0.98, blue: 0.97, alpha: 1)
    })

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.96, blue: 0.68)
            : Color(red: 0.04, green: 0.43, blue: 0.21)
    }

    private var fiveHourWindow: CodexQuotaWindow? {
        guard snapshot.showsFiveHourLimit, let limit = snapshot.codexLimit else { return nil }
        return CodexiOSQuotaPresentation.fiveHourWindow(for: limit)
    }

    private var weeklyWindow: CodexQuotaWindow? {
        guard let limit = snapshot.codexLimit else { return nil }
        return CodexiOSQuotaPresentation.weeklyWindow(for: limit)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let activeFiveHourWindow = activeFiveHourWindow(now: context.date)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 38)

                Text(activeFiveHourWindow == nil && weeklyWindow != nil ? "Weekly allowance" : "Your next reset")
                    .font(.system(size: dashboardTitleSize, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 22)

                if let activeFiveHourWindow {
                    resetHero(window: activeFiveHourWindow, name: "5-hour", now: context.date)
                } else if let weeklyWindow {
                    weeklyAllowanceHero(weeklyWindow)
                } else {
                    unavailableResetHero
                }

                if let weeklyWindow {
                    weeklyReset(
                        weeklyWindow,
                        now: context.date,
                        showsAllowance: activeFiveHourWindow != nil
                    )
                        .padding(.top, 62)
                }

                if let errorMessage = model.errorMessage {
                    Text("Could not refresh. Showing the last check. \(errorMessage)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                }

                footer
                    .padding(.top, 72)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .foregroundStyle(.primary)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Codexex")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            NavigationLink {
                CodexiOSSettingsView(model: model, onMatrixThemeEnabled: onMatrixThemeEnabled)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("ios.dashboard.settings")

            Button {
                Task { await model.refresh() }
            } label: {
                Group {
                    if model.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(model.isRefreshing)
            .accessibilityLabel(model.isRefreshing ? "Refreshing quota" : "Refresh quota")
            .accessibilityIdentifier("ios.dashboard.refresh")
        }
        .buttonStyle(.plain)
    }

    private func resetHero(window: CodexQuotaWindow, name: String, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let resetsAt = window.resetsAt {
                Text(resetsAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: resetTimeSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Next reset at \(resetsAt.formatted(date: .omitted, time: .shortened))")
            }

            Text("\(dayLabel(for: window.resetsAt, now: now)) · \(name) window")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            if let resetsAt = window.resetsAt {
                Text(relativeReset(resetsAt, now: now))
                    .font(.system(size: relativeResetSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }

            Text(availabilityText(for: window, name: name))
                .font(.headline)
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
    }

    private var unavailableResetHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset time unavailable")
                .font(.title2.weight(.semibold))
            Text("Refresh to check your current allowance.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func weeklyAllowanceHero(_ window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(percentageText(for: window))
                .font(.system(size: allowanceSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: displayedPercent(for: window), total: 100)
                .tint(accent)
                .accessibilityHidden(true)
                .padding(.top, 24)
        }
    }

    private func weeklyReset(
        _ window: CodexQuotaWindow,
        now: Date,
        showsAllowance: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Weekly reset")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if let resetsAt = window.resetsAt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(resetsAt.formatted(.dateTime.weekday(.wide))) \(resetsAt.formatted(.dateTime.day().month(.wide)))")
                        .font(.title3.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(resetsAt.formatted(date: .omitted, time: .shortened)) · \(relativeReset(resetsAt, now: now))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Reset time unavailable")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if showsAllowance {
                weeklyAllowance(window)
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var footer: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    footerStatus
                    refreshButton
                }
            } else {
                HStack(spacing: 12) {
                    footerStatus
                    Spacer(minLength: 8)
                    refreshButton
                }
            }
        }
        .font(.callout)
    }

    private var footerStatus: some View {
        Group {
            if let lastUpdatedAt = model.lastUpdatedAt {
                Text("Checked \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not checked yet")
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var refreshButton: some View {
        Button("Refresh") {
            Task { await model.refresh() }
        }
        .foregroundStyle(accent)
        .disabled(model.isRefreshing)
        .accessibilityIdentifier("ios.dashboard.refreshFooter")
    }

    @ViewBuilder
    private func weeklyAllowance(_ window: CodexQuotaWindow) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                weeklyAllowanceLabel
                weeklyAllowancePercentage(window)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                weeklyAllowanceLabel
                Spacer(minLength: 8)
                weeklyAllowancePercentage(window)
            }
        }
    }

    private var weeklyAllowanceLabel: some View {
        Text("Weekly allowance")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func weeklyAllowancePercentage(_ window: CodexQuotaWindow) -> some View {
        Text(percentageText(for: window))
            .font(.title3.weight(.semibold))
            .foregroundStyle(accent)
            .monospacedDigit()
    }

    private func activeFiveHourWindow(now: Date) -> CodexQuotaWindow? {
        if let fiveHourWindow, let resetsAt = fiveHourWindow.resetsAt, resetsAt > now {
            return fiveHourWindow
        }
        return nil
    }

    private func displayedPercent(for window: CodexQuotaWindow) -> Double {
        showUsedQuota ? window.clampedUsedPercent : window.remainingPercent
    }

    private func percentageText(for window: CodexQuotaWindow) -> String {
        "\(Int(displayedPercent(for: window).rounded()))% \(showUsedQuota ? "used" : "left")"
    }

    private func availabilityText(for window: CodexQuotaWindow, name: String) -> String {
        if showUsedQuota {
            return "\(window.usedPercentText) of your \(name) allowance has been used."
        }
        if window.remainingPercent <= 0 {
            return "Your \(name) allowance is currently used up."
        }
        return "\(window.remainingPercentText) of your \(name) allowance is still available."
    }

    private func dayLabel(for date: Date?, now: Date) -> String {
        guard let date else { return "Upcoming" }
        return Calendar.current.isDate(date, inSameDayAs: now)
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
