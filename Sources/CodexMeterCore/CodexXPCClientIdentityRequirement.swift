import Foundation

public enum CodexXPCClientIdentityRequirement {
    public static let appBundleIdentifier = "com.magrathean.CodexexApp"
    public static let teamIdentifier = "NPSQV9WYS5"
    public static let developmentBypassEnvironmentKey = "CODEXEX_DISABLE_XPC_CODE_SIGNING_REQUIREMENT"

    public static var mainAppRequirement: String {
        #"identifier "\#(appBundleIdentifier)" and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
    }

    public static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    public static func allowsDevelopmentBypass(
        isDebugBuild: Bool = Self.isDebugBuild,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard isDebugBuild else { return false }
        return environment[developmentBypassEnvironmentKey] == "1"
    }
}
