import Foundation

public enum CodexBinaryLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        for candidate in candidatePaths(environment: environment) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func candidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()

        var ordered: [String] = []

        if let override = environment["CODEXMETER_CODEX_PATH"], override.isEmpty == false {
            ordered.append(override)
        }

        if let path = environment["PATH"], path.isEmpty == false {
            let pathCandidates = path
                .split(separator: ":")
                .map(String.init)
                .map { "\($0)/codex" }
            ordered.append(contentsOf: pathCandidates)
        }

        ordered.append(contentsOf: [
            "\(home)/.local/bin/codex",
            "\(home)/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ])

        var seen = Set<String>()
        return ordered.filter { seen.insert($0).inserted }
    }
}
