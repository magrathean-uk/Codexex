#if os(macOS)
import OSLog

enum CodexLog {
    static let subsystem = "com.magrathean.CodexexApp"
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let helper = Logger(subsystem: subsystem, category: "helper")
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
#endif
