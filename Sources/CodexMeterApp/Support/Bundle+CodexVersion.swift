#if os(macOS)
import Foundation

extension Bundle {
    var codexexVersionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build.isEmpty == false {
            return "\(version) (\(build))"
        }
        return version
    }
}
#endif
