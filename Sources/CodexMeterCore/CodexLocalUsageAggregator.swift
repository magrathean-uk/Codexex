import Foundation

public enum CodexLocalUsageAggregator {
    public static func snapshot(
        entries: [CodexLocalUsageEntry],
        dataPath: String,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        configReport: CodexLocalConfigReport = CodexLocalConfigReport(severity: .ok, issues: []),
        coverage: CodexLocalUsageCoverage = .unknown
    ) -> CodexLocalUsageSummary {
        let deduped = deduplicate(entries)
        let todayStart = calendar.startOfDay(for: capturedAt)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: capturedAt)?.start
            ?? todayStart.addingTimeInterval(-(7 * 24 * 60 * 60))
        let latest = deduped.max { $0.timestamp < $1.timestamp }
        let models = modelSummaries(from: deduped)
        let sessions = sessionSummaries(from: deduped)
        let total = periodSummary(for: deduped)
        let latestContextWindowPercent = deduped
            .compactMap { entry -> (Date, Double)? in
                guard let percent = entry.rateLimits?.contextWindowPercent else { return nil }
                return (entry.timestamp, percent)
            }
            .max { lhs, rhs in lhs.0 < rhs.0 }?
            .1

        return CodexLocalUsageSummary(
            capturedAt: capturedAt,
            dataPath: dataPath,
            total: total,
            today: periodSummary(for: deduped.filter { $0.timestamp >= todayStart && $0.timestamp <= capturedAt }),
            week: periodSummary(for: deduped.filter { $0.timestamp >= weekStart && $0.timestamp <= capturedAt }),
            sessions: sessions,
            projects: projectSummaries(from: deduped),
            modelSummaries: models,
            fiveHourBlocks: fiveHourBlocks(from: deduped, calendar: calendar),
            wasteSignals: wasteSignals(entries: deduped),
            configReport: configReport,
            latestProjectName: latest?.projectPath.map(projectDisplayName),
            latestModel: latest?.model,
            contextWindowPercent: latestContextWindowPercent,
            sessionAutopsies: sessionAutopsies(from: sessions, totalTokens: total.totalTokens),
            attributionConfidence: attributionConfidence(entries: deduped),
            coverage: coverage
        )
    }

    private static func deduplicate(_ entries: [CodexLocalUsageEntry]) -> [CodexLocalUsageEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            let key = "\(entry.sourcePath)#\(entry.id)"
            return seen.insert(key).inserted
        }
    }

    private static func periodSummary(for entries: [CodexLocalUsageEntry]) -> CodexLocalUsagePeriodSummary {
        CodexLocalUsagePeriodSummary(
            entryCount: entries.count,
            tokens: entries.reduce(.zero) { $0.adding($1.tokens) }
        )
    }

    private static func sessionSummaries(from entries: [CodexLocalUsageEntry]) -> [CodexLocalSessionSummary] {
        Dictionary(grouping: entries, by: \.sessionID)
            .map { sessionID, values in
                let sorted = values.sorted { $0.timestamp < $1.timestamp }
                let latest = sorted.last!
                return CodexLocalSessionSummary(
                    id: sessionID,
                    projectPath: latest.projectPath,
                    latestModel: latest.model,
                    startedAt: sorted.first!.timestamp,
                    lastActivityAt: latest.timestamp,
                    entryCount: values.count,
                    commandCount: values.reduce(0) { codexSaturatingNonnegativeAdd($0, $1.commandCount) },
                    tokens: values.reduce(.zero) { $0.adding($1.tokens) }
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens.totalTokens != rhs.tokens.totalTokens {
                    return lhs.tokens.totalTokens > rhs.tokens.totalTokens
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
    }

    private static func projectSummaries(from entries: [CodexLocalUsageEntry]) -> [CodexLocalProjectSummary] {
        let withProject = entries.compactMap { entry -> (String, CodexLocalUsageEntry)? in
            guard let path = entry.projectPath else { return nil }
            return (path, entry)
        }

        return Dictionary(grouping: withProject, by: { $0.0 })
            .map { path, pairs in
                let values = pairs.map(\.1)
                let latest = values.max { $0.timestamp < $1.timestamp }!
                return CodexLocalProjectSummary(
                    id: path,
                    displayName: projectDisplayName(path),
                    path: path,
                    latestModel: latest.model,
                    lastActivityAt: latest.timestamp,
                    sessionCount: Set(values.map(\.sessionID)).count,
                    commandCount: values.reduce(0) { codexSaturatingNonnegativeAdd($0, $1.commandCount) },
                    tokens: values.reduce(.zero) { $0.adding($1.tokens) }
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens.totalTokens != rhs.tokens.totalTokens {
                    return lhs.tokens.totalTokens > rhs.tokens.totalTokens
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func modelSummaries(from entries: [CodexLocalUsageEntry]) -> [CodexLocalModelSummary] {
        Dictionary(grouping: entries, by: \.model)
            .map { model, values in
                CodexLocalModelSummary(
                    model: model,
                    entryCount: values.count,
                    tokens: values.reduce(.zero) { $0.adding($1.tokens) }
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens.totalTokens != rhs.tokens.totalTokens {
                    return lhs.tokens.totalTokens > rhs.tokens.totalTokens
                }
                return lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedAscending
            }
    }

    private static func fiveHourBlocks(
        from entries: [CodexLocalUsageEntry],
        calendar: Calendar
    ) -> [CodexLocalUsageBlock] {
        Dictionary(grouping: entries) { entry in
            blockStart(for: entry.timestamp, calendar: calendar)
        }
        .map { start, values in
            CodexLocalUsageBlock(
                id: "\(Int(start.timeIntervalSince1970))",
                startsAt: start,
                endsAt: start.addingTimeInterval(5 * 60 * 60),
                tokens: values.reduce(.zero) { $0.adding($1.tokens) },
                entryCount: values.count
            )
        }
        .sorted { $0.startsAt < $1.startsAt }
    }

    private static func blockStart(for date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let elapsed = max(0, date.timeIntervalSince(dayStart))
        let blockIndex = floor(elapsed / (5 * 60 * 60))
        return dayStart.addingTimeInterval(blockIndex * 5 * 60 * 60)
    }

    private static func wasteSignals(entries: [CodexLocalUsageEntry]) -> [CodexLocalWasteSignal] {
        var signals: [CodexLocalWasteSignal] = []
        let tokens = entries.reduce(CodexLocalTokenUsage.zero) { $0.adding($1.tokens) }

        if tokens.totalTokens >= 50_000 && tokens.cacheHitRate >= 0.65 {
            signals.append(
                CodexLocalWasteSignal(
                    id: "high-cache-read",
                    kind: .highCacheRead,
                    title: "High cache read",
                    detail: "\(Int((tokens.cacheHitRate * 100).rounded()))% cached input. Watch repeated reads."
                )
            )
        }

        if let heavyToolSession = sessionSummaries(from: entries).first(where: { $0.commandCount >= 10 }) {
            signals.append(
                CodexLocalWasteSignal(
                    id: "tool-loop-\(heavyToolSession.id)",
                    kind: .toolLoop,
                    title: "Tool loop",
                    detail: "\(heavyToolSession.commandCount) shell/tool completions in one session."
                )
            )
        }

        if let overkill = entries.first(where: {
            $0.model.localizedCaseInsensitiveContains("max")
            && $0.tokens.totalTokens >= 50_000
            && Double($0.tokens.outputTokens) / Double(max(1, $0.tokens.totalTokens)) < 0.02
        }) {
            signals.append(
                CodexLocalWasteSignal(
                    id: "model-overkill-\(overkill.model)",
                    kind: .modelOverkill,
                    title: "Model overkill",
                    detail: "\(overkill.model) spent \(overkill.tokens.totalTokens) tokens for a small output."
                )
            )
        }

        if let heavySession = sessionSummaries(from: entries).first(where: { $0.tokens.totalTokens >= 150_000 }) {
            signals.append(
                CodexLocalWasteSignal(
                    id: "heavy-session-\(heavySession.id)",
                    kind: .heavySession,
                    title: "Heavy session",
                    detail: "\(projectDisplayName(heavySession.projectPath ?? "Unknown")) used \(compactTokens(heavySession.tokens.totalTokens)) tokens."
                )
            )
        }

        if let spike = entries.sorted(by: { $0.timestamp > $1.timestamp }).first(where: { $0.tokens.totalTokens >= 75_000 }) {
            signals.append(
                CodexLocalWasteSignal(
                    id: "sudden-spike-\(spike.id)",
                    kind: .suddenSpike,
                    title: "Sudden spike",
                    detail: "\(compactTokens(spike.tokens.totalTokens)) tokens in one turn."
                )
            )
        }

        return signals.sorted { lhs, rhs in
            signalPriority(lhs.kind) > signalPriority(rhs.kind)
        }
    }

    private static func sessionAutopsies(
        from sessions: [CodexLocalSessionSummary],
        totalTokens: Int
    ) -> [CodexLocalSessionAutopsy] {
        sessions.map { session in
            let share = totalTokens > 0
                ? (Double(session.tokens.totalTokens) / Double(totalTokens)) * 100
                : 0
            return CodexLocalSessionAutopsy(
                id: session.id,
                projectName: session.projectPath.map(projectDisplayName),
                model: session.latestModel,
                tokens: session.tokens,
                totalSharePercent: share,
                commandCount: session.commandCount,
                entryCount: session.entryCount,
                lastActivityAt: session.lastActivityAt
            )
        }
    }

    private static func attributionConfidence(entries: [CodexLocalUsageEntry]) -> CodexLocalAttributionConfidence {
        guard entries.isEmpty == false else {
            return .unknown
        }

        let hasMissingContext = entries.contains { entry in
            entry.projectPath?.nilIfEmpty == nil || entry.model.nilIfEmpty == nil || entry.model == "unknown"
        }

        if hasMissingContext {
            return CodexLocalAttributionConfidence(
                level: .partial,
                title: "Partial confidence",
                detail: "Some local session rows are missing project or model context."
            )
        }

        return CodexLocalAttributionConfidence(
            level: .high,
            title: "High confidence",
            detail: "Official local Codex session logs provide session, project, and model burn. Per-user ownership is not claimed."
        )
    }

    private static func projectDisplayName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty ?? path
    }

    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(Int((Double(value) / 1_000_000).rounded()))M"
        }
        if value >= 1_000 {
            return "\(Int((Double(value) / 1_000).rounded()))K"
        }
        return "\(value)"
    }

    private static func signalPriority(_ kind: CodexLocalWasteSignalKind) -> Int {
        switch kind {
        case .heavySession:
            return 50
        case .suddenSpike:
            return 40
        case .modelOverkill:
            return 30
        case .toolLoop:
            return 20
        case .highCacheRead:
            return 10
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
