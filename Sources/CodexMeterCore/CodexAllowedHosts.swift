import Foundation

public enum CodexAllowedHosts {
    public static let chatGPTAuthHosts: Set<String> = [
        "auth.openai.com",
        "chatgpt.com"
    ]

    public static func isAllowedChatGPTAuthURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return chatGPTAuthHosts.contains(host)
    }
}
