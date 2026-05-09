import Foundation

public enum CodexLocalUsageAggregator {
    public static func snapshot(
        entries: [CodexLocalUsageEntry],
        dataPath: String,
        capturedAt: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        configReport: CodexLocalConfigReport = CodexLocalConfigReport(severity: .ok, issues: [])
    ) -> CodexLocalUsageSummary {
        let deduped = deduplicate(entries)
        let todayStart = calendar.startOfDay(for: capturedAt)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: capturedAt)?.start
            ?? todayStart.addingTimeInterval(-(7 * 24 * 60 * 60))
        let latest = deduped.max { $0.timestamp < $1.timestamp }
        let models = modelSummaries(from: deduped)

        return CodexLocalUsageSummary(
            capturedAt: capturedAt,
            dataPath: dataPath,
            total: periodSummary(for: deduped),
            today: periodSummary(for: deduped.filter { $0.timestamp >= todayStart && $0.timestamp <= capturedAt }),
            week: periodSummary(for: deduped.filter { $0.timestamp >= weekStart && $0.timestamp <= capturedAt }),
            sessions: sessionSummaries(from: deduped),
            projects: projectSummaries(from: deduped),
            modelSummaries: models,
            fiveHourBlocks: fiveHourBlocks(from: deduped, calendar: calendar),
            wasteSignals: wasteSignals(entries: deduped),
            configReport: configReport,
            latestProjectName: latest?.projectPath.map(projectDisplayName),
            latestModel: latest?.model,
            contextWindowPercent: nil
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
                    commandCount: values.reduce(0) { $0 + $1.commandCount },
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
                    commandCount: values.reduce(0) { $0 + $1.commandCount },
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
                    detail: "\(Int((tokens.cacheHitRate * 100).rounded()))% cached input. Good when intentional, waste when repeated reads keep looping."
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

        return signals
    }

    private static func projectDisplayName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty ?? path
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
