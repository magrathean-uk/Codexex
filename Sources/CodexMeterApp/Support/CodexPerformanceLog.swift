#if os(macOS) || os(iOS)
import Foundation
import OSLog

enum CodexPerformanceLog {
    static let subsystem = "com.magrathean.CodexexApp.performance"
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let helper = Logger(subsystem: subsystem, category: "helper")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let analytics = Logger(subsystem: subsystem, category: "analytics")
    static let popup = Logger(subsystem: subsystem, category: "popup")
}
#endif
